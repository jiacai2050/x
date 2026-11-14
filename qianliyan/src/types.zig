const std = @import("std");

pub const Value = union(enum) {
    null,
    integer: i64,
    real: f64,
    text: []const u8,
    blob: []const u8,

    pub fn format(
        self: Value,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .null => try writer.writeAll("NULL"),
            .integer => |v| try writer.print("{d}", .{v}),
            .real => |v| try writer.print("{d}", .{v}),
            .text => |v| try writer.writeAll(v),
            .blob => |v| try writer.print("<Blob {d}B>", .{v.len}),
        }
    }
};

pub const ColumnDef = struct {
    name: []const u8,
    type_name: []const u8,
    pk: u32 = 0,
};

pub const IndexDef = struct {
    name: []const u8,
    unique: bool,
    columns: []const []const u8 = &.{},
};

pub const TableDef = struct {
    name: []const u8,
    sql: []const u8,
    columns: []const ColumnDef,
    indexes: []const IndexDef,
};

pub const SchemaResult = struct {
    arena: std.heap.ArenaAllocator,
    tables: []const TableDef,

    pub fn deinit(self: *SchemaResult) void {
        self.arena.deinit();
    }
};

pub const QueryResult = struct {
    arena: std.heap.ArenaAllocator,
    columns: []const ColumnDef,
    rows: []const []const Value,
    has_more: bool,
    execution_time_ns: u64,

    pub fn deinit(self: *QueryResult) void {
        self.arena.deinit();
    }
};
