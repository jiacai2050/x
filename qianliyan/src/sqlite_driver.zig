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

        var stmt = pc.raw.prepare(sql_str) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        defer stmt.close();

        var raw_rows = stmt.query(&.{}) catch |err| {
            self.recordError(pc.lastError());
            return err;
        };
        defer raw_rows.close();

        const col_names = raw_rows.columns();
        const col_count = col_names.len;

        var columns = try arena_allocator.alloc(types.ColumnDef, col_count);
        for (col_names, 0..) |col_name, i| {
            columns[i] = .{
                .name = try arena_allocator.dupe(u8, col_name),
                .type_name = "",
                .pk = 0,
            };
        }

        var row_list: std.ArrayList([]const types.Value) = .empty;
        var has_more = false;
        const limit = row_count_max orelse std.math.maxInt(usize);
        const loop_bound = if (limit < std.math.maxInt(usize))
            limit + 1
        else
            std.math.maxInt(usize);

        const dest_buf = try arena_allocator.alloc(sql.Value, col_count);
        var iteration_count: usize = 0;

        while (iteration_count < loop_bound and raw_rows.next(dest_buf)) : (iteration_count += 1) {
            if (row_list.items.len >= limit) {
                has_more = true;
                break;
            }

            var row_values = try arena_allocator.alloc(types.Value, col_count);
            for (dest_buf, 0..) |val, i| {
                row_values[i] = switch (val) {
                    .null => .null,
                    .int => |v| .{ .integer = v },
                    .float => |v| .{ .real = v },
                    .bool => |b| .{ .integer = if (b) 1 else 0 },
                    .string => |s| .{ .text = try arena_allocator.dupe(u8, s) },
                    .bytes => |b| .{ .blob = try arena_allocator.dupe(u8, b) },
                };
            }
            try row_list.append(arena_allocator, row_values);
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

        assert(row_list.items.len <= limit);

        return types.QueryResult{
            .arena = arena,
            .columns = columns,
            .rows = try row_list.toOwnedSlice(arena_allocator),
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

        var tables: std.ArrayList(types.TableDef) = .empty;

        for (tables_res.rows) |row| {
            if (row.len < 2) continue;
            const table_name = switch (row[0]) {
                .text => |t| t,
                else => continue,
            };
            const table_sql = switch (row[1]) {
                .text => |t| t,
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

            var columns: std.ArrayList(types.ColumnDef) = .empty;
            for (col_res.rows) |col_row| {
                if (col_row.len < 3) continue;
                const col_name = switch (col_row[1]) {
                    .text => |t| try arena_allocator.dupe(u8, t),
                    else => "",
                };
                const col_type = switch (col_row[2]) {
                    .text => |t| try arena_allocator.dupe(u8, t),
                    else => "",
                };
                const pk_val: u32 = if (col_row.len > 5) switch (col_row[5]) {
                    .integer => |v| if (v > 0) @intCast(v) else 0,
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

            var indexes: std.ArrayList(types.IndexDef) = .empty;
            for (idx_res.rows) |idx_row| {
                // index_list columns: 0:seq, 1:name, 2:unique, 3:origin, 4:partial.
                if (idx_row.len < 3) continue;
                const idx_name = switch (idx_row[1]) {
                    .text => |t| try arena_allocator.dupe(u8, t),
                    else => continue,
                };
                const is_unique = switch (idx_row[2]) {
                    .integer => |v| v == 1,
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

                var idx_columns: std.ArrayList([]const u8) = .empty;
                for (idx_col_res.rows) |info_row| {
                    // index_info columns: 0:seqno, 1:cid, 2:name.
                    if (info_row.len > 2) {
                        switch (info_row[2]) {
                            .text => |t| {
                                const col_duped = try arena_allocator.dupe(u8, t);
                                try idx_columns.append(arena_allocator, col_duped);
                            },
                            else => {},
                        }
                    }
                }

                try indexes.append(arena_allocator, .{
                    .name = idx_name,
                    .unique = is_unique,
                    .columns = try idx_columns.toOwnedSlice(arena_allocator),
                });
            }

            try tables.append(arena_allocator, .{
                .name = try arena_allocator.dupe(u8, table_name),
                .sql = try arena_allocator.dupe(u8, table_sql),
                .columns = try columns.toOwnedSlice(arena_allocator),
                .indexes = try indexes.toOwnedSlice(arena_allocator),
            });
        }

        return types.SchemaResult{
            .arena = arena,
            .tables = try tables.toOwnedSlice(arena_allocator),
        };
    }
};

comptime {
    assert(@sizeOf(SqliteDriver) > 0);
}
