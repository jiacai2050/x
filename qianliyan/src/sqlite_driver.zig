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
        };
    }

    pub fn close(self: *SqliteDriver) void {
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
        const pc = try self.db.conn();
        defer pc.release();
        const exec_res = pc.exec(sql_str, &.{}) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        // Result is discarded after successful execution as caller only expects void.
        assert(@sizeOf(@TypeOf(exec_res)) > 0);
    }

    /// Query dynamic SQL statement, returning a self-contained QueryResult.
    pub fn query(
        self: *SqliteDriver,
        gpa: std.mem.Allocator,
        sql_str: [:0]const u8,
        row_count_max: ?usize,
    ) !types.QueryResult {
        assert(sql_str.len > 0);
        self.recordError(null);

        var arena = std.heap.ArenaAllocator.init(gpa);
        errdefer arena.deinit();
        const arena_allocator = arena.allocator();

        const start_time_ns = getMonotonicNs();

        const pc = try self.db.conn();
        defer pc.release();

        const ctx = stdgo.context.background();
        var stmt = pc.raw.prepare(ctx, sql_str) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        defer stmt.close();

        var raw_rows = stmt.query(ctx, &.{}) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        defer raw_rows.close();

        const col_names = raw_rows.columns();
        const col_count = col_names.len;

        var columns = try arena_allocator.alloc(types.DbColumnDef, col_count);
        for (col_names, 0..) |col_name, i| {
            columns[i] = .{
                .name = (try arena_allocator.dupeSentinel(u8, col_name, 0)).ptr,
                .type_name = "",
            };
        }

        var value_list: std.ArrayList(types.DbValue) = .empty;
        var row_count: usize = 0;
        var has_more = false;
        const limit = row_count_max orelse std.math.maxInt(usize);
        const loop_bound = if (limit < std.math.maxInt(usize))
            limit + 1
        else
            std.math.maxInt(usize);

        const dest_buf = try arena_allocator.alloc(sql.Value, col_count);
        var iteration_count: usize = 0;

        while (iteration_count < loop_bound and raw_rows.next(dest_buf)) : (iteration_count += 1) {
            if (row_count >= limit) {
                has_more = true;
                break;
            }

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

        if (raw_rows.err()) |err| {
            self.recordError(pc.lastError());
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
            const pragma_col_sql = try std.fmt.allocPrintSentinel(
                arena_allocator,
                "PRAGMA table_info(\"{s}\");",
                .{table_name},
                0,
            );
            var col_res = try self.query(arena_allocator, pragma_col_sql, null);
            defer col_res.deinit();

            var columns: std.ArrayList(types.DbColumnInfo) = .empty;
            for (0..col_res.row_count) |cri| {
                const col_row = col_res.getRow(cri);
                if (col_row.len < 3) continue;
                const col_name = switch (col_row[1].type) {
                    .text => (try arena_allocator.dupeSentinel(u8, col_row[1].value.text_val.data[0..col_row[1].value.text_val.size], 0)).ptr,
                    else => "",
                };
                const col_type = switch (col_row[2].type) {
                    .text => (try arena_allocator.dupeSentinel(u8, col_row[2].value.text_val.data[0..col_row[2].value.text_val.size], 0)).ptr,
                    else => "",
                };
                const pk_val: u32 = if (col_row.len > 5) switch (col_row[5].type) {
                    .integer => if (col_row[5].value.int_val > 0) @intCast(col_row[5].value.int_val) else 0,
                    else => 0,
                } else 0;
                try columns.append(arena_allocator, .{
                    .name = col_name,
                    .type_name = col_type,
                    .pk = pk_val,
                });
            }

            // 2. Fetch index definitions using PRAGMA index_list.
            const pragma_idx_sql = try std.fmt.allocPrintSentinel(
                arena_allocator,
                "PRAGMA index_list(\"{s}\");",
                .{table_name},
                0,
            );
            var idx_res = try self.query(arena_allocator, pragma_idx_sql, null);
            defer idx_res.deinit();

            var indexes: std.ArrayList(types.DbIndexDef) = .empty;
            for (0..idx_res.row_count) |iri| {
                const idx_row = idx_res.getRow(iri);
                // index_list columns: 0:seq, 1:name, 2:unique, 3:origin, 4:partial.
                if (idx_row.len < 3) continue;
                const idx_name = switch (idx_row[1].type) {
                    .text => (try arena_allocator.dupeSentinel(u8, idx_row[1].value.text_val.data[0..idx_row[1].value.text_val.size], 0)).ptr,
                    else => continue,
                };
                const is_unique = switch (idx_row[2].type) {
                    .integer => idx_row[2].value.int_val == 1,
                    else => false,
                };

                // Fetch indexed columns via PRAGMA index_info("index_name").
                const pragma_idx_info_sql = try std.fmt.allocPrintSentinel(
                    arena_allocator,
                    "PRAGMA index_info(\"{s}\");",
                    .{idx_name},
                    0,
                );
                var idx_col_res = try self.query(arena_allocator, pragma_idx_info_sql, null);
                defer idx_col_res.deinit();

                var idx_columns: std.ArrayList([*:0]const u8) = .empty;
                for (0..idx_col_res.row_count) |iiri| {
                    const info_row = idx_col_res.getRow(iiri);
                    // index_info columns: 0:seqno, 1:cid, 2:name.
                    if (info_row.len > 2) {
                        switch (info_row[2].type) {
                            .text => {
                                const s = info_row[2].value.text_val;
                                const col_duped = (try arena_allocator.dupeSentinel(u8, s.data[0..s.size], 0)).ptr;
                                try idx_columns.append(arena_allocator, col_duped);
                            },
                            else => {},
                        }
                    }
                }

                const idx_cols_slice = try idx_columns.toOwnedSlice(arena_allocator);
                try indexes.append(arena_allocator, .{
                    .name = idx_name,
                    .is_unique = is_unique,
                    .column_count = @intCast(idx_cols_slice.len),
                    .columns = idx_cols_slice.ptr,
                });
            }

            const cols_slice = try columns.toOwnedSlice(arena_allocator);
            const idxs_slice = try indexes.toOwnedSlice(arena_allocator);
            const tbl_name_c = (try arena_allocator.dupeSentinel(u8, table_name, 0)).ptr;
            const tbl_sql_c: ?[*:0]const u8 = if (table_sql.len > 0)
                (try arena_allocator.dupeSentinel(u8, table_sql, 0)).ptr
            else
                null;

            try tables.append(arena_allocator, .{
                .name = tbl_name_c,
                .sql = tbl_sql_c,
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
