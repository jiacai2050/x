const std = @import("std");
const assert = std.debug.assert;
const stdgo = @import("stdgo");
const sql = stdgo.database.sql;
const types = @import("types.zig");

fn getMonotonicNs() u64 {
    var ts: std.c.timespec = undefined;
    const rc = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    assert(rc == 0);
    const total_ns = @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
    if (total_ns > 0) {
        return @intCast(total_ns);
    } else {
        return 0;
    }
}

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
        sqlite_drv.* = sql.sqlite.SQLiteDriver.init(gpa);

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
            _ = c.pc.interrupt();
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
        const pc = try self.db.conn(.none);
        defer pc.release();
        const exec_res = pc.exec(sql_str, &.{}, .none) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        // Result is discarded after successful execution as caller only expects void.
        assert(@sizeOf(@TypeOf(exec_res)) > 0);
    }

    /// Cursor represents an in-flight, streaming query execution on an active SQLite connection.
    ///
    /// Architecture & Current Limitations:
    /// 1. Single Active Cursor per Database Instance:
    ///    To prevent SQLite read lock contention and connection starvation (as max_open_conns is 1),
    ///    only ONE cursor may be active at any given time.
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
        pc: *sql.PooledConn,
        stmt: sql.driver.Stmt,
        rows: sql.driver.Rows,
        columns: []types.DbColumnDef,
        buffered_row: ?[]types.DbValue = null,
        closed: bool = false,

        fn freeBufferedRow(self: *Cursor) void {
            if (self.buffered_row) |row| {
                for (row) |val| {
                    switch (val.type) {
                        .text => self.driver.gpa.free(val.value.text_val.data[0..val.value.text_val.size]),
                        .blob => self.driver.gpa.free(val.value.blob_val.data[0..val.value.blob_val.size]),
                        else => {},
                    }
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
            self.stmt.close();
            self.pc.release();
            self.driver.gpa.free(self.columns);
            self.driver.gpa.destroy(self);
        }

        pub fn fetch(self: *Cursor, gpa: std.mem.Allocator, limit: usize) !types.QueryResult {
            var arena = std.heap.ArenaAllocator.init(gpa);
            errdefer arena.deinit();
            const arena_allocator = arena.allocator();

            const start_time_ns = getMonotonicNs();

            const col_count = self.columns.len;
            var columns = try arena_allocator.alloc(types.DbColumnDef, col_count);
            for (self.columns, 0..) |col, i| {
                const name_duped = try arena_allocator.dupe(u8, col.name.data[0..col.name.size]);
                const type_duped = try arena_allocator.dupe(u8, col.type_name.data[0..col.type_name.size]);
                columns[i] = .{
                    .name = .{ .data = name_duped.ptr, .size = name_duped.len },
                    .type_name = .{ .data = type_duped.ptr, .size = type_duped.len },
                };
            }

            var value_list: std.ArrayList(types.DbValue) = .empty;
            var row_count: usize = 0;
            var has_more = false;

            // 1. If we have a buffered row from a previous peek, emit it first.
            if (self.buffered_row) |buffered| {
                for (buffered) |val| {
                    const cell: types.DbValue = switch (val.type) {
                        .null => .{ .type = .null, .value = .{ .int_val = 0 } },
                        .integer => .{ .type = .integer, .value = .{ .int_val = val.value.int_val } },
                        .real => .{ .type = .real, .value = .{ .real_val = val.value.real_val } },
                        .text => blk: {
                            const slice = val.value.text_val.data[0..val.value.text_val.size];
                            const duped = try arena_allocator.dupe(u8, slice);
                            break :blk .{
                                .type = .text,
                                .value = .{ .text_val = .{ .data = duped.ptr, .size = duped.len } },
                            };
                        },
                        .blob => blk: {
                            const slice = val.value.blob_val.data[0..val.value.blob_val.size];
                            const duped = try arena_allocator.dupe(u8, slice);
                            break :blk .{
                                .type = .blob,
                                .value = .{ .blob_val = .{ .data = duped.ptr, .size = duped.len } },
                            };
                        },
                    };
                    try value_list.append(arena_allocator, cell);
                }
                row_count += 1;
                self.freeBufferedRow();
            }

            const io = self.driver.threaded.io();
            const dest_buf = try arena_allocator.alloc(sql.Value, col_count);

            // 2. Read up to `limit` rows.
            while (row_count < limit and (try self.rows.next(io, dest_buf, .none))) {
                for (dest_buf) |val| {
                    const cell: types.DbValue = switch (val) {
                        .null => .{ .type = .null, .value = .{ .int_val = 0 } },
                        .int => |v| .{ .type = .integer, .value = .{ .int_val = v } },
                        .float => |v| .{ .type = .real, .value = .{ .real_val = v } },
                        .bool => |b| .{ .type = .integer, .value = .{ .int_val = if (b) 1 else 0 } },
                        .string => |s| blk: {
                            const duped = try arena_allocator.dupe(u8, s);
                            break :blk .{
                                .type = .text,
                                .value = .{ .text_val = .{ .data = duped.ptr, .size = duped.len } },
                            };
                        },
                        .bytes => |b| blk: {
                            const duped = try arena_allocator.dupe(u8, b);
                            break :blk .{
                                .type = .blob,
                                .value = .{ .blob_val = .{ .data = duped.ptr, .size = duped.len } },
                            };
                        },
                    };
                    try value_list.append(arena_allocator, cell);
                }
                row_count += 1;
            }

            // 3. If row_count reaches limit, peek one row ahead to determine has_more.
            if (row_count >= limit and limit < std.math.maxInt(usize)) {
                if (try self.rows.next(io, dest_buf, .none)) {
                    has_more = true;
                    const buf = try self.driver.gpa.alloc(types.DbValue, col_count);
                    var buf_idx: usize = 0;
                    errdefer {
                        for (buf[0..buf_idx]) |val| {
                            switch (val.type) {
                                .text => self.driver.gpa.free(val.value.text_val.data[0..val.value.text_val.size]),
                                .blob => self.driver.gpa.free(val.value.blob_val.data[0..val.value.blob_val.size]),
                                else => {},
                            }
                        }
                        self.driver.gpa.free(buf);
                    }
                    for (dest_buf) |val| {
                        buf[buf_idx] = switch (val) {
                            .null => .{ .type = .null, .value = .{ .int_val = 0 } },
                            .int => |v| .{ .type = .integer, .value = .{ .int_val = v } },
                            .float => |v| .{ .type = .real, .value = .{ .real_val = v } },
                            .bool => |b| .{ .type = .integer, .value = .{ .int_val = if (b) 1 else 0 } },
                            .string => |s| blk: {
                                const duped = try self.driver.gpa.dupe(u8, s);
                                break :blk .{
                                    .type = .text,
                                    .value = .{ .text_val = .{ .data = duped.ptr, .size = duped.len } },
                                };
                            },
                            .bytes => |b| blk: {
                                const duped = try self.driver.gpa.dupe(u8, b);
                                break :blk .{
                                    .type = .blob,
                                    .value = .{ .blob_val = .{ .data = duped.ptr, .size = duped.len } },
                                };
                            },
                        };
                        buf_idx += 1;
                    }
                    self.buffered_row = buf;
                }
            }

            if (self.rows.err()) |err| {
                self.driver.recordError(self.pc.lastError());
                return err;
            }

            const end_time_ns = getMonotonicNs();
            const duration_ns: u64 = if (end_time_ns > start_time_ns)
                end_time_ns - start_time_ns
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

        const pc = try self.db.conn(.none);
        errdefer if (!cursor_created) pc.release();

        const io = self.threaded.io();
        var stmt = pc.raw.prepare(io, sql_str, .none) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        errdefer if (!cursor_created) stmt.close();

        var raw_rows = stmt.query(io, &.{}, .none) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        errdefer if (!cursor_created) raw_rows.close();

        const col_count = raw_rows.columnCount();

        var cursor_cols = try self.gpa.alloc(types.DbColumnDef, col_count);
        errdefer if (!cursor_created) self.gpa.free(cursor_cols);
        for (0..col_count) |i| {
            const col_name = raw_rows.columnName(i);
            const col_type = if (raw_rows.vtable.columnTypeDatabaseTypeName) |f|
                f(raw_rows.ptr, i) orelse ""
            else
                "";
            cursor_cols[i] = .{
                .name = .{ .data = col_name.ptr, .size = col_name.len },
                .type_name = .{ .data = col_type.ptr, .size = col_type.len },
            };
        }

        const cursor = try self.gpa.create(Cursor);
        errdefer if (!cursor_created) self.gpa.destroy(cursor);
        cursor.* = .{
            .driver = self,
            .pc = pc,
            .stmt = stmt,
            .rows = raw_rows,
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
        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const arena_allocator = arena.allocator();

        var tables_res = try self.query(
            arena_allocator,
            "SELECT name, sql FROM sqlite_master WHERE type='table' " ++
                "AND name NOT LIKE 'sqlite_%' ORDER BY name;",
            null,
        );
        defer tables_res.deinit();

        var tables: std.ArrayList(types.DbTableDef) = .empty;

        for (0..tables_res.row_count) |tri| {
            const row = tables_res.getRow(tri);
            if (row.len < 2) continue;
            const table_name = switch (row[0].type) {
                .text => row[0].value.text_val.data[0..row[0].value.text_val.size],
                else => continue,
            };
            const table_sql = switch (row[1].type) {
                .text => row[1].value.text_val.data[0..row[1].value.text_val.size],
                else => "",
            };

            // 1. Fetch column definitions using PRAGMA table_info.
            const pragma_col_sql = try std.fmt.allocPrint(
                arena_allocator,
                "PRAGMA table_info(\"{s}\");",
                .{table_name},
            );
            var col_res = try self.query(arena_allocator, pragma_col_sql, null);
            defer col_res.deinit();

            var columns: std.ArrayList(types.DbColumnInfo) = .empty;
            for (0..col_res.row_count) |cri| {
                const col_row = col_res.getRow(cri);
                if (col_row.len < 3) continue;
                const col_name = switch (col_row[1].type) {
                    .text => try arena_allocator.dupe(u8, col_row[1].value.text_val.data[0..col_row[1].value.text_val.size]),
                    else => "",
                };
                const col_type = switch (col_row[2].type) {
                    .text => try arena_allocator.dupe(u8, col_row[2].value.text_val.data[0..col_row[2].value.text_val.size]),
                    else => "",
                };
                const pk_val: u32 = if (col_row.len > 5) switch (col_row[5].type) {
                    .integer => if (col_row[5].value.int_val > 0) @intCast(col_row[5].value.int_val) else 0,
                    else => 0,
                } else 0;
                try columns.append(arena_allocator, .{
                    .name = .{ .data = col_name.ptr, .size = col_name.len },
                    .type_name = .{ .data = col_type.ptr, .size = col_type.len },
                    .pk = pk_val,
                });
            }

            // 2. Fetch index definitions using PRAGMA index_list.
            const pragma_idx_sql = try std.fmt.allocPrint(
                arena_allocator,
                "PRAGMA index_list(\"{s}\");",
                .{table_name},
            );
            var idx_res = try self.query(arena_allocator, pragma_idx_sql, null);
            defer idx_res.deinit();

            var indexes: std.ArrayList(types.DbIndexDef) = .empty;
            for (0..idx_res.row_count) |iri| {
                const idx_row = idx_res.getRow(iri);
                // index_list columns: 0:seq, 1:name, 2:unique, 3:origin, 4:partial.
                if (idx_row.len < 3) continue;
                const idx_name = switch (idx_row[1].type) {
                    .text => try arena_allocator.dupe(u8, idx_row[1].value.text_val.data[0..idx_row[1].value.text_val.size]),
                    else => continue,
                };
                const is_unique = switch (idx_row[2].type) {
                    .integer => idx_row[2].value.int_val == 1,
                    else => false,
                };

                // Fetch indexed columns via PRAGMA index_info("index_name").
                const pragma_idx_info_sql = try std.fmt.allocPrint(
                    arena_allocator,
                    "PRAGMA index_info(\"{s}\");",
                    .{idx_name},
                );
                var idx_col_res = try self.query(arena_allocator, pragma_idx_info_sql, null);
                defer idx_col_res.deinit();

                var idx_columns: std.ArrayList(types.DbSlice) = .empty;
                for (0..idx_col_res.row_count) |iiri| {
                    const info_row = idx_col_res.getRow(iiri);
                    // index_info columns: 0:seqno, 1:cid, 2:name.
                    if (info_row.len > 2) {
                        switch (info_row[2].type) {
                            .text => {
                                const s = info_row[2].value.text_val;
                                const col_duped = try arena_allocator.dupe(u8, s.data[0..s.size]);
                                try idx_columns.append(arena_allocator, .{ .data = col_duped.ptr, .size = col_duped.len });
                            },
                            else => {},
                        }
                    }
                }

                const idx_cols_slice = try idx_columns.toOwnedSlice(arena_allocator);
                try indexes.append(arena_allocator, .{
                    .name = .{ .data = idx_name.ptr, .size = idx_name.len },
                    .is_unique = is_unique,
                    .column_count = @intCast(idx_cols_slice.len),
                    .columns = idx_cols_slice.ptr,
                });
            }

            const cols_slice = try columns.toOwnedSlice(arena_allocator);
            const idxs_slice = try indexes.toOwnedSlice(arena_allocator);
            const tbl_name_duped = try arena_allocator.dupe(u8, table_name);
            const tbl_sql_duped = try arena_allocator.dupe(u8, table_sql);

            try tables.append(arena_allocator, .{
                .name = .{ .data = tbl_name_duped.ptr, .size = tbl_name_duped.len },
                .sql = .{ .data = tbl_sql_duped.ptr, .size = tbl_sql_duped.len },
                .column_count = @intCast(cols_slice.len),
                .columns = cols_slice.ptr,
                .index_count = @intCast(idxs_slice.len),
                .indexes = idxs_slice.ptr,
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
