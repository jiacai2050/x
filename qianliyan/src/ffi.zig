const std = @import("std");
const assert = std.debug.assert;
const sqlite_driver = @import("sqlite_driver.zig");
const types = @import("types.zig");
const SqliteDriver = sqlite_driver.SqliteDriver;

pub const CDbColumnType = enum(c_int) {
    null = 0,
    integer = 1,
    real = 2,
    text = 3,
    blob = 4,
};

pub const CDbColumnDef = extern struct {
    name: [*:0]const u8,
    type_name: [*:0]const u8,
};

pub const CDbBlobVal = extern struct {
    data: [*]const u8,
    size: usize,
};

pub const CDbValueUnion = extern union {
    int_val: i64,
    real_val: f64,
    text_val: [*:0]const u8,
    blob_val: CDbBlobVal,
};

pub const CDbValue = extern struct {
    type: CDbColumnType,
    value: CDbValueUnion,
};

pub const CDbBatchResult = extern struct {
    column_count: u32,
    columns: [*]const CDbColumnDef,
    row_count: u32,
    values: [*]const CDbValue,
    has_more: bool,
    execution_time_ns: u64,
};

comptime {
    assert(@sizeOf(CDbColumnType) == @sizeOf(c_int));
    assert(@sizeOf(CDbColumnDef) == 2 * @sizeOf(?*anyopaque));
    assert(@sizeOf(CDbBlobVal) == @sizeOf(?*anyopaque) + @sizeOf(usize));
    assert(@sizeOf(CDbBatchResult) > 0);
}

const InternalResult = struct {
    arena: std.heap.ArenaAllocator,
    c_result: CDbBatchResult,
};

pub const DbContext = struct {
    driver: SqliteDriver,
    gpa: std.mem.Allocator,
};

fn setError(gpa: std.mem.Allocator, error_out: ?*?[*:0]u8, err_msg: []const u8) void {
    if (error_out) |out| {
        const copy = gpa.dupeSentinel(u8, err_msg, 0) catch return;
        out.* = copy.ptr;
    }
}

pub export fn db_open(path: ?[*:0]const u8, error_out: ?*?[*:0]u8) ?*DbContext {
    // The C ABI boundary cannot pass a fat-pointer Zig std.mem.Allocator from the Swift host.
    // We use std.heap.c_allocator here to integrate with the OS libc malloc/free runtime safely
    // across threads, paired with db_close() to guarantee symmetrical deallocation.
    const gpa = std.heap.c_allocator;
    if (error_out) |out| {
        out.* = null;
    }

    const ctx = gpa.create(DbContext) catch {
        setError(gpa, error_out, "Out of memory");
        return null;
    };
    errdefer gpa.destroy(ctx);

    const driver = SqliteDriver.open(gpa, .{
        .path = path,
        .read_only = false,
        .create = true,
    }) catch |err| {
        const msg = std.fmt.allocPrint(
            gpa,
            "Failed to open database: {s}",
            .{@errorName(err)},
        ) catch "Failed to open database";
        defer gpa.free(msg);
        setError(gpa, error_out, msg);
        return null;
    };

    ctx.* = .{
        .driver = driver,
        .gpa = gpa,
    };
    return ctx;
}

pub export fn db_close(handle: ?*DbContext) void {
    if (handle) |ctx| {
        ctx.driver.close();
        const gpa = ctx.gpa;
        gpa.destroy(ctx);
    }
}

pub export fn db_interrupt(handle: ?*DbContext) void {
    if (handle) |ctx| {
        ctx.driver.interrupt();
    }
}

pub export fn db_free_string(str: ?[*:0]u8) void {
    if (str) |s| {
        const span = std.mem.span(s);
        std.heap.c_allocator.free(span[0 .. span.len + 1]);
    }
}

pub export fn db_free_result(result: ?*CDbBatchResult) void {
    if (result) |res| {
        const internal: *InternalResult = @fieldParentPtr("c_result", res);
        var arena = internal.arena;
        arena.deinit();
    }
}

fn writeJsonString(list: *std.ArrayList(u8), gpa: std.mem.Allocator, str: []const u8) !void {
    try list.append(gpa, '"');
    for (str) |ch| {
        switch (ch) {
            '"' => try list.appendSlice(gpa, "\\\""),
            '\\' => try list.appendSlice(gpa, "\\\\"),
            '\n' => try list.appendSlice(gpa, "\\n"),
            '\r' => try list.appendSlice(gpa, "\\r"),
            '\t' => try list.appendSlice(gpa, "\\t"),
            else => try list.append(gpa, ch),
        }
    }
    try list.append(gpa, '"');
}

pub export fn db_get_schema_json(handle: ?*DbContext, error_out: ?*?[*:0]u8) ?[*:0]u8 {
    const ctx = handle orelse {
        setError(std.heap.c_allocator, error_out, "Null db handle");
        return null;
    };
    if (error_out) |out| {
        out.* = null;
    }

    var schema = ctx.driver.getSchema(ctx.gpa) catch |err| {
        const msg = std.fmt.allocPrint(
            ctx.gpa,
            "Failed to inspect schema: {s}",
            .{@errorName(err)},
        ) catch "Failed to inspect schema";
        defer ctx.gpa.free(msg);
        setError(ctx.gpa, error_out, msg);
        return null;
    };
    defer schema.deinit();

    // Serialize schema to JSON string for Swift JSONDecoder.
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(ctx.gpa);

    list.appendSlice(ctx.gpa, "[") catch return null;
    for (schema.tables, 0..) |tbl, i| {
        if (i > 0) list.appendSlice(ctx.gpa, ",") catch return null;
        list.appendSlice(ctx.gpa, "{\"name\":") catch return null;
        writeJsonString(&list, ctx.gpa, tbl.name) catch return null;

        list.appendSlice(ctx.gpa, ",\"sql\":") catch return null;
        writeJsonString(&list, ctx.gpa, tbl.sql) catch return null;

        // Table Columns
        list.appendSlice(ctx.gpa, ",\"columns\":[") catch return null;
        for (tbl.columns, 0..) |col, ci| {
            if (ci > 0) list.appendSlice(ctx.gpa, ",") catch return null;
            list.appendSlice(ctx.gpa, "{\"name\":") catch return null;
            writeJsonString(&list, ctx.gpa, col.name) catch return null;
            list.appendSlice(ctx.gpa, ",\"type\":") catch return null;
            writeJsonString(&list, ctx.gpa, col.type_name) catch return null;
            const pk_str = std.fmt.allocPrint(
                ctx.gpa,
                ",\"pk\":{d}}}",
                .{col.pk},
            ) catch return null;
            defer ctx.gpa.free(pk_str);
            list.appendSlice(ctx.gpa, pk_str) catch return null;
        }
        list.appendSlice(ctx.gpa, "]") catch return null;

        // Table Indexes
        list.appendSlice(ctx.gpa, ",\"indexes\":[") catch return null;
        for (tbl.indexes, 0..) |idx, ii| {
            if (ii > 0) list.appendSlice(ctx.gpa, ",") catch return null;
            list.appendSlice(ctx.gpa, "{\"name\":") catch return null;
            writeJsonString(&list, ctx.gpa, idx.name) catch return null;
            const unique_str = if (idx.unique) "true" else "false";
            const idx_mid = std.fmt.allocPrint(
                ctx.gpa,
                ",\"unique\":{s},\"columns\":[",
                .{unique_str},
            ) catch return null;
            defer ctx.gpa.free(idx_mid);
            list.appendSlice(ctx.gpa, idx_mid) catch return null;

            for (idx.columns, 0..) |col_name, ci| {
                if (ci > 0) list.appendSlice(ctx.gpa, ",") catch return null;
                writeJsonString(&list, ctx.gpa, col_name) catch return null;
            }
            list.appendSlice(ctx.gpa, "]}") catch return null;
        }
        list.appendSlice(ctx.gpa, "]}") catch return null;
    }
    list.appendSlice(ctx.gpa, "]") catch return null;

    const null_terminated = ctx.gpa.dupeSentinel(u8, list.items, 0) catch return null;
    return null_terminated.ptr;
}

pub export fn db_query(
    handle: ?*DbContext,
    sql: ?[*:0]const u8,
    limit: u32,
    error_out: ?*?[*:0]u8,
) ?*CDbBatchResult {
    const ctx = handle orelse {
        setError(std.heap.c_allocator, error_out, "Null db handle");
        return null;
    };
    if (error_out) |out| {
        out.* = null;
    }

    const sql_str = if (sql) |s| std.mem.span(s) else {
        setError(ctx.gpa, error_out, "Empty SQL statement");
        return null;
    };
    if (sql_str.len == 0) {
        setError(ctx.gpa, error_out, "Empty SQL statement");
        return null;
    }

    const row_count_max: ?usize = if (limit > 0) @intCast(limit) else null;

    var zig_result = ctx.driver.query(ctx.gpa, sql_str, row_count_max) catch |err| {
        const msg = if (ctx.driver.lastError()) |le|
            le
        else switch (err) {
            error.Interrupted, error.QueryInterrupted => "Query was cancelled by user",
            error.SQLitePrepareFailed, error.PrepareFailed => "SQL syntax error or invalid table",
            else => "Query execution failed",
        };
        setError(ctx.gpa, error_out, msg);
        return null;
    };
    defer zig_result.deinit();

    var arena = std.heap.ArenaAllocator.init(ctx.gpa);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    const internal = arena_allocator.create(InternalResult) catch return null;

    const col_count = zig_result.columns.len;
    const row_count = zig_result.rows.len;

    var c_columns = arena_allocator.alloc(CDbColumnDef, col_count) catch return null;
    for (zig_result.columns, 0..) |col, i| {
        c_columns[i] = .{
            .name = (arena_allocator.dupeSentinel(u8, col.name, 0) catch return null).ptr,
            .type_name = (arena_allocator.dupeSentinel(
                u8,
                col.type_name,
                0,
            ) catch return null).ptr,
        };
    }

    const total_values = col_count * row_count;
    var c_values = arena_allocator.alloc(CDbValue, total_values) catch return null;

    for (zig_result.rows, 0..) |row, r| {
        assert(row.len == col_count);
        for (row, 0..) |val, c| {
            const idx = r * col_count + c;
            assert(idx < total_values);
            switch (val) {
                .null => {
                    c_values[idx] = .{
                        .type = .null,
                        .value = .{ .int_val = 0 },
                    };
                },
                .integer => |v| {
                    c_values[idx] = .{
                        .type = .integer,
                        .value = .{ .int_val = v },
                    };
                },
                .real => |v| {
                    c_values[idx] = .{
                        .type = .real,
                        .value = .{ .real_val = v },
                    };
                },
                .text => |t| {
                    const text_copy = (arena_allocator.dupeSentinel(
                        u8,
                        t,
                        0,
                    ) catch return null).ptr;
                    c_values[idx] = .{
                        .type = .text,
                        .value = .{ .text_val = text_copy },
                    };
                },
                .blob => |b| {
                    const blob_copy = (arena_allocator.dupe(u8, b) catch return null).ptr;
                    c_values[idx] = .{
                        .type = .blob,
                        .value = .{
                            .blob_val = .{
                                .data = blob_copy,
                                .size = b.len,
                            },
                        },
                    };
                },
            }
        }
    }

    internal.* = .{
        .arena = arena,
        .c_result = .{
            .column_count = @intCast(col_count),
            .columns = c_columns.ptr,
            .row_count = @intCast(row_count),
            .values = c_values.ptr,
            .has_more = zig_result.has_more,
            .execution_time_ns = zig_result.execution_time_ns,
        },
    };

    return &internal.c_result;
}
