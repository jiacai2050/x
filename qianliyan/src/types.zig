const std = @import("std");
const assert = std.debug.assert;

/// Represents a dynamically-typed SQL value.
/// Used to pass row data across database queries and serialization boundaries.
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
        // Format options are unused because SQL values use standard literal formatting.
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

comptime {
    assert(@sizeOf(Value) > 0);
}

/// Metadata describing a single table or query result column.
pub const ColumnDef = struct {
    name: []const u8,
    type_name: []const u8,
    pk: u32 = 0,
};

comptime {
    assert(@sizeOf(ColumnDef) >= 2 * @sizeOf([]const u8) + @sizeOf(u32));
}

/// Metadata describing an index on a table.
pub const IndexDef = struct {
    name: []const u8,
    unique: bool,
    columns: []const []const u8 = &.{},
};

comptime {
    assert(@sizeOf(IndexDef) > 0);
}

/// Comprehensive schema definition for a single database table.
pub const TableDef = struct {
    name: []const u8,
    sql: []const u8,
    columns: []const ColumnDef,
    indexes: []const IndexDef,
};

comptime {
    assert(@sizeOf(TableDef) > 0);
}

/// Self-contained schema inspection result whose allocations belong to its arena.
pub const SchemaResult = struct {
    arena: std.heap.ArenaAllocator,
    tables: []const TableDef,

    pub fn deinit(self: *SchemaResult) void {
        self.arena.deinit();
    }
};

/// Self-contained query execution result whose allocations belong to its arena.
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

comptime {
    assert(@sizeOf(SchemaResult) > 0);
    assert(@sizeOf(QueryResult) > 0);
}
