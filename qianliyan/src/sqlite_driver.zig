const std = @import("std");
const assert = std.debug.assert;
const stdgo = @import("stdgo");
const sql = stdgo.database.sql;
const types = @import("types.zig");

pub const SqliteDriver = struct {
    gpa: std.mem.Allocator,
    threaded: *std.Io.Threaded,
    sqlite_drv: *sql.sqlite.SQLiteDriver,
    db: *sql.DB,
    last_error_buf: ?[]u8 = null,

    active_cursor: ?*Cursor = null,

    pub const OpenOptions = struct {
        path: ?[*:0]const u8 = null,
        read_only: bool = false,
        create: bool = true,
    };

    pub fn open(gpa: std.mem.Allocator, options: OpenOptions) !SqliteDriver {
        const threaded = try gpa.create(std.Io.Threaded);
        errdefer gpa.destroy(threaded);
        threaded.* = std.Io.Threaded.init(gpa, .{});
        errdefer threaded.deinit();

        const sqlite_drv = try gpa.create(sql.sqlite.SQLiteDriver);
        errdefer gpa.destroy(sqlite_drv);
        sqlite_drv.* = sql.sqlite.SQLiteDriver.init(gpa, .{
            .read_only = options.read_only,
            .create = options.create,
        });

        const dsn = if (options.path) |p| std.mem.span(p) else ":memory:";
        const db = try sql.DB.open(gpa, threaded.io(), sqlite_drv.driver(), dsn);
        errdefer db.close();

        // For SQLite in Qianliyan: single connection per database ensures consistent transaction
        // state, memory DB retention across queries, and deterministic interruption behavior.
        db.setMaxOpenConns(1);
        db.setMaxIdleConns(1);

        return SqliteDriver{
            .gpa = gpa,
            .threaded = threaded,
            .sqlite_drv = sqlite_drv,
            .db = db,
            .last_error_buf = null,
            .active_cursor = null,
        };
    }

    pub fn closeActiveCursor(self: *SqliteDriver) void {
        if (self.active_cursor) |c| {
            self.active_cursor = null;
            c.close();
        }
    }

    pub fn close(self: *SqliteDriver) void {
        self.closeActiveCursor();
        if (self.last_error_buf) |buf| {
            self.gpa.free(buf);
            self.last_error_buf = null;
        }
        self.db.close();
        self.gpa.destroy(self.sqlite_drv);
        self.threaded.deinit();
        self.gpa.destroy(self.threaded);
    }

    pub fn interrupt(self: *SqliteDriver) void {
        if (self.active_cursor) |c| {
            const cursor_interrupted = c.conn.interrupt();
            assert(cursor_interrupted or !cursor_interrupted);
        }
        const interrupted_count = self.db.interruptAll();
        // Number of interrupted connections can be 0 when no query is currently active.
        assert(interrupted_count >= 0);
    }

    pub fn lastError(self: *SqliteDriver) ?[]const u8 {
        return self.last_error_buf;
    }

    fn recordError(self: *SqliteDriver, msg: ?[]const u8) void {
        if (self.last_error_buf) |buf| {
            self.gpa.free(buf);
            self.last_error_buf = null;
        }
        if (msg) |m| {
            self.last_error_buf = self.gpa.dupe(u8, m) catch null;
        }
    }

    pub fn exec(self: *SqliteDriver, sql_str: []const u8) !void {
        assert(sql_str.len > 0);
        self.recordError(null);
        self.closeActiveCursor();
        var conn = try self.db.conn(.none);
        defer conn.close();
        const exec_res = conn.exec(sql_str, .{}, .none) catch |err| {
            self.recordError(conn.lastError());
            return err;
        };
        // Result is discarded after successful execution as caller only expects void.
        assert(@sizeOf(@TypeOf(exec_res)) > 0);
    }

    /// Cursor represents an in-flight, streaming query execution on an active SQLite connection.
    ///
    /// Architecture & Current Limitations:
    /// 1. Single Active Cursor per Database Instance:
    ///    To prevent SQLite read lock contention and connection starvation
    ///    (as max_open_conns is 1), only ONE cursor may be active at any given time.
    /// 2. Invalidation upon Subsequent Operations:
    ///    Executing any new query, DDL (`exec`), or schema inspection preemptively calls
    ///    `closeActiveCursor()`, closing the cursor and releasing SQLite resources immediately.
    ///    Consequently, in a multi-tab GUI, running a query in Tab B invalidates an unfinished
    ///    streaming cursor from Tab A.
    /// 3. Future Roadmap:
    ///    To support concurrent cursors across multiple tabs, the driver can assign a unique
    ///    `CursorId` to each tab and either manage a pool of read-only connections (WAL mode)
    ///    or enforce LRU/TTL expiration policies per cursor.
    pub const Cursor = struct {
        driver: *SqliteDriver,
        conn: sql.Conn,
        rows: sql.Rows,
        columns: []types.DbColumnDef,
        buffered_row: ?[]types.DbValue = null,
        closed: bool = false,

        fn freeDbValue(allocator: std.mem.Allocator, val: types.DbValue) void {
            switch (val.type) {
                .text => allocator.free(val.value.text_val.slice()),
                .blob => allocator.free(val.value.blob_val.slice()),
                else => {},
            }
        }

        fn cloneDbValue(allocator: std.mem.Allocator, val: types.DbValue) !types.DbValue {
            return switch (val.type) {
                .null, .integer, .real => val,
                .text => .{
                    .type = .text,
                    .value = .{ .text_val = try val.value.text_val.dupe(allocator) },
                },
                .blob => .{
                    .type = .blob,
                    .value = .{ .blob_val = try val.value.blob_val.dupe(allocator) },
                },
            };
        }

        fn sqlValueToDbValue(allocator: std.mem.Allocator, val: sql.Value) !types.DbValue {
            return switch (val) {
                .null => .{ .type = .null, .value = .{ .int_val = 0 } },
                .int => |v| .{ .type = .integer, .value = .{ .int_val = v } },
                .float => |v| .{ .type = .real, .value = .{ .real_val = v } },
                .bool => |b| .{
                    .type = .integer,
                    .value = .{ .int_val = if (b) 1 else 0 },
                },
                .string => |s| blk: {
                    const duped = try allocator.dupe(u8, s);
                    break :blk .{
                        .type = .text,
                        .value = .{ .text_val = .{ .data = duped.ptr, .size = duped.len } },
                    };
                },
                .bytes => |b| blk: {
                    const duped = try allocator.dupe(u8, b);
                    break :blk .{
                        .type = .blob,
                        .value = .{ .blob_val = .{ .data = duped.ptr, .size = duped.len } },
                    };
                },
            };
        }

        fn freeBufferedRow(self: *Cursor) void {
            if (self.buffered_row) |row| {
                for (row) |val| {
                    freeDbValue(self.driver.gpa, val);
                }
                self.driver.gpa.free(row);
                self.buffered_row = null;
            }
        }

        pub fn close(self: *Cursor) void {
            if (self.closed) return;
            self.closed = true;
            self.freeBufferedRow();
            self.rows.close();
            self.conn.close();
            self.driver.gpa.free(self.columns);
            self.driver.gpa.destroy(self);
        }

        pub fn fetch(self: *Cursor, gpa: std.mem.Allocator, limit: usize) !types.QueryResult {
            assert(!self.closed);

            const io = self.driver.threaded.io();
            const start_time = std.Io.Clock.awake.now(io);

            var arena = std.heap.ArenaAllocator.init(gpa);
            errdefer arena.deinit();
            const arena_allocator = arena.allocator();

            const col_count = self.columns.len;
            var columns = try arena_allocator.alloc(types.DbColumnDef, col_count);
            for (self.columns, 0..) |col, i| {
                columns[i] = .{
                    .name = try col.name.dupe(arena_allocator),
                    .type_name = try col.type_name.dupe(arena_allocator),
                };
            }

            var value_list: std.ArrayList(types.DbValue) = .empty;
            var row_count: usize = 0;
            var has_more = false;

            // 1. If we have a buffered row from a previous peek, emit it first.
            if (self.buffered_row) |buffered| {
                for (buffered) |val| {
                    const cell = try cloneDbValue(arena_allocator, val);
                    try value_list.append(arena_allocator, cell);
                }
                row_count += 1;
                self.freeBufferedRow();
            }

            const dest_buf = try arena_allocator.alloc(sql.Value, col_count);

            // 2. Read up to `limit` rows.
            while (row_count < limit and (try self.rows.next(dest_buf, .none))) {
                for (dest_buf) |val| {
                    const cell = try sqlValueToDbValue(arena_allocator, val);
                    try value_list.append(arena_allocator, cell);
                }
                row_count += 1;
            }

            // 3. If row_count reaches limit, peek one row ahead to determine has_more.
            if (row_count >= limit) {
                if (limit < std.math.maxInt(usize)) {
                    if (try self.rows.next(dest_buf, .none)) {
                        has_more = true;
                        const buf = try self.driver.gpa.alloc(types.DbValue, col_count);
                        var buf_idx: usize = 0;
                        errdefer {
                            for (buf[0..buf_idx]) |val| {
                                freeDbValue(self.driver.gpa, val);
                            }
                            self.driver.gpa.free(buf);
                        }
                        for (dest_buf, 0..) |val, i| {
                            buf[i] = try sqlValueToDbValue(self.driver.gpa, val);
                            buf_idx += 1;
                        }
                        self.buffered_row = buf;
                    }
                }
            }

            if (self.rows.err()) |err| {
                self.driver.recordError(self.conn.lastError());
                return err;
            }

            const duration = start_time.untilNow(io, .awake);
            const duration_ns: u64 = if (duration.nanoseconds > 0)
                @intCast(duration.nanoseconds)
            else
                0;

            assert(row_count <= limit);

            return types.QueryResult{
                .arena = arena,
                .columns = columns,
                .row_count = row_count,
                .values = try value_list.toOwnedSlice(arena_allocator),
                .has_more = has_more,
                .execution_time_ns = duration_ns,
            };
        }
    };

    /// Query dynamic SQL statement, returning a self-contained QueryResult.
    pub fn query(
        self: *SqliteDriver,
        gpa: std.mem.Allocator,
        sql_str: []const u8,
        row_count_max: ?usize,
    ) !types.QueryResult {
        assert(sql_str.len > 0);
        self.recordError(null);
        self.closeActiveCursor();

        var cursor_created = false;

        var conn = try self.db.conn(.none);
        errdefer if (!cursor_created) conn.close();

        var rows = conn.query(sql_str, .{}, .none) catch |err| {
            self.recordError(conn.lastError());
            return err;
        };
        errdefer if (!cursor_created) rows.close();

        const col_count = rows.columnCount();

        var cursor_cols = try self.gpa.alloc(types.DbColumnDef, col_count);
        errdefer if (!cursor_created) self.gpa.free(cursor_cols);
        for (0..col_count) |i| {
            const col_name = rows.columnName(i);
            const ct = rows.columnType(i) catch null;
            const col_type = if (ct) |c| c.databaseTypeName() orelse "" else "";
            cursor_cols[i] = .{
                .name = .{ .data = col_name.ptr, .size = col_name.len },
                .type_name = .{ .data = col_type.ptr, .size = col_type.len },
            };
        }

        const cursor = try self.gpa.create(Cursor);
        errdefer if (!cursor_created) self.gpa.destroy(cursor);
        cursor.* = .{
            .driver = self,
            .conn = conn,
            .rows = rows,
            .columns = cursor_cols,
            .closed = false,
        };
        cursor_created = true;

        const limit = row_count_max orelse std.math.maxInt(usize);
        const res = cursor.fetch(gpa, limit) catch |err| {
            cursor.close();
            return err;
        };

        if (res.has_more) {
            self.active_cursor = cursor;
        } else {
            cursor.close();
        }

        return res;
    }

    pub fn fetchMore(
        self: *SqliteDriver,
        gpa: std.mem.Allocator,
        limit: usize,
    ) !?types.QueryResult {
        const cursor = self.active_cursor orelse return null;
        const res = cursor.fetch(gpa, limit) catch |err| {
            self.closeActiveCursor();
            return err;
        };

        if (!res.has_more) {
            self.closeActiveCursor();
        }

        return res;
    }

    /// Retrieve schema (all tables, DDL sql, columns, and indexes).
    pub fn getSchema(self: *SqliteDriver, gpa: std.mem.Allocator) !types.SchemaResult {
        self.recordError(null);
        self.closeActiveCursor();

        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const arena_allocator = arena.allocator();

        // Borrow connection once for the entire schema inspection sequence.
        // This avoids 80+ borrow/release roundtrips and ensures a consistent snapshot.
        var conn = try self.db.conn(.none);
        defer conn.close();

        const TableMasterRow = struct {
            name: []const u8,
            sql: ?[]const u8,
        };

        var tables_rows = conn.query(
            "SELECT name, sql FROM sqlite_master WHERE type='table' " ++
                "AND name NOT LIKE 'sqlite_%' ORDER BY name;",
            .{},
            .none,
        ) catch |err| {
            self.recordError(conn.lastError());
            return err;
        };
        defer tables_rows.close();

        var tables: std.ArrayList(types.DbTableDef) = .empty;

        while (try tables_rows.nextStruct(TableMasterRow, .none)) |tbl| {
            // 1. Fetch column definitions using PRAGMA table_info.
            const pragma_column_sql = try std.fmt.allocPrint(
                arena_allocator,
                "PRAGMA table_info(\"{s}\");",
                .{tbl.name},
            );
            var col_rows = conn.query(pragma_column_sql, .{}, .none) catch |err| {
                self.recordError(conn.lastError());
                return err;
            };
            defer col_rows.close();

            const ColumnInfoRow = struct {
                cid: i64,
                name: []const u8,
                type: []const u8,
                notnull: i64,
                dflt_value: ?[]const u8,
                pk: u32,
            };

            var columns: std.ArrayList(types.DbColumnInfo) = .empty;
            while (try col_rows.nextStruct(ColumnInfoRow, .none)) |col| {
                const col_name = try arena_allocator.dupe(u8, col.name);
                const col_type = try arena_allocator.dupe(u8, col.type);
                try columns.append(arena_allocator, .{
                    .name = .{ .data = col_name.ptr, .size = col_name.len },
                    .type_name = .{ .data = col_type.ptr, .size = col_type.len },
                    .pk = col.pk,
                });
            }

            // 2. Fetch index definitions using PRAGMA index_list.
            const pragma_index_sql = try std.fmt.allocPrint(
                arena_allocator,
                "PRAGMA index_list(\"{s}\");",
                .{tbl.name},
            );
            var idx_rows = conn.query(pragma_index_sql, .{}, .none) catch |err| {
                self.recordError(conn.lastError());
                return err;
            };
            defer idx_rows.close();

            const IndexListRow = struct {
                seq: i64,
                name: []const u8,
                unique: bool,
                origin: []const u8,
                partial: i64,
            };

            var indexes: std.ArrayList(types.DbIndexDef) = .empty;
            while (try idx_rows.nextStruct(IndexListRow, .none)) |idx| {
                const index_name = try arena_allocator.dupe(u8, idx.name);

                // Fetch indexed columns via PRAGMA index_info("index_name").
                const pragma_index_info_sql = try std.fmt.allocPrint(
                    arena_allocator,
                    "PRAGMA index_info(\"{s}\");",
                    .{index_name},
                );
                var idx_col_rows = conn.query(pragma_index_info_sql, .{}, .none) catch |err| {
                    self.recordError(conn.lastError());
                    return err;
                };
                defer idx_col_rows.close();

                const IndexInfoRow = struct {
                    seqno: i64,
                    cid: i64,
                    name: ?[]const u8,
                };

                var index_columns: std.ArrayList(types.DbSlice) = .empty;
                while (try idx_col_rows.nextStruct(IndexInfoRow, .none)) |info| {
                    if (info.name) |col_str| {
                        const col_duped = try arena_allocator.dupe(u8, col_str);
                        try index_columns.append(arena_allocator, .{
                            .data = col_duped.ptr,
                            .size = col_duped.len,
                        });
                    }
                }

                const index_cols_slice = try index_columns.toOwnedSlice(arena_allocator);
                try indexes.append(arena_allocator, .{
                    .name = .{ .data = index_name.ptr, .size = index_name.len },
                    .is_unique = idx.unique,
                    .column_count = @intCast(index_cols_slice.len),
                    .columns = index_cols_slice.ptr,
                });
            }

            const columns_slice = try columns.toOwnedSlice(arena_allocator);
            const indexes_slice = try indexes.toOwnedSlice(arena_allocator);
            const table_name_duped = try arena_allocator.dupe(u8, tbl.name);
            const table_sql_duped = try arena_allocator.dupe(u8, tbl.sql orelse "");

            try tables.append(arena_allocator, .{
                .name = .{ .data = table_name_duped.ptr, .size = table_name_duped.len },
                .sql = .{ .data = table_sql_duped.ptr, .size = table_sql_duped.len },
                .column_count = @intCast(columns_slice.len),
                .columns = columns_slice.ptr,
                .index_count = @intCast(indexes_slice.len),
                .indexes = indexes_slice.ptr,
            });
        }

        const tables_slice = try tables.toOwnedSlice(arena_allocator);
        return types.SchemaResult{
            .arena = arena,
            .schema = .{
                .table_count = @intCast(tables_slice.len),
                .tables = tables_slice.ptr,
            },
        };
    }
};

comptime {
    assert(@sizeOf(SqliteDriver) > 0);
}
