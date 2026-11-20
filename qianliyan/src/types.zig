const std = @import("std");
const assert = std.debug.assert;

/// C-compatible column types matching include/dbcore.h
pub const DbColumnType = enum(c_int) {
    null = 0,
    integer = 1,
    real = 2,
    text = 3,
    blob = 4,
};

/// Slice carrying pointer and explicit byte length
pub const DbSlice = extern struct {
    data: [*]const u8,
    size: usize,
};

pub const DbValueUnion = extern union {
    int_val: i64,
    real_val: f64,
    text_val: DbSlice,
    blob_val: DbSlice,
};

/// Universal C-ABI compatible database value
pub const DbValue = extern struct {
    type: DbColumnType,
    value: DbValueUnion,

    pub fn format(
        self: DbValue,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        switch (self.type) {
            .null => try writer.writeAll("NULL"),
            .integer => try writer.print("{d}", .{self.value.int_val}),
            .real => try writer.print("{d}", .{self.value.real_val}),
            .text => try writer.writeAll(self.value.text_val.data[0..self.value.text_val.size]),
            .blob => try writer.print("<Blob {d}B>", .{self.value.blob_val.size}),
        }
    }
};

comptime {
    assert(@sizeOf(DbValue) > 0);
}

/// C-compatible column definition for query results (matching DbColumnDef in include/dbcore.h)
pub const DbColumnDef = extern struct {
    name: [*:0]const u8,
    type_name: [*:0]const u8,
};

/// C-compatible column definition for table schema (matching DbColumnInfo in include/dbcore.h)
pub const DbColumnInfo = extern struct {
    name: [*:0]const u8,
    type_name: [*:0]const u8,
    pk: u32 = 0,
};

/// C-compatible index definition (matching DbIndexDef in include/dbcore.h)
pub const DbIndexDef = extern struct {
    name: [*:0]const u8,
    is_unique: bool,
    column_count: u32,
    columns: [*]const [*:0]const u8,
};

/// C-compatible table definition (matching DbTableDef in include/dbcore.h)
pub const DbTableDef = extern struct {
    name: [*:0]const u8,
    sql: ?[*:0]const u8,
    column_count: u32,
    columns: [*]const DbColumnInfo,
    index_count: u32,
    indexes: [*]const DbIndexDef,
};

/// C-compatible schema result (matching DbSchemaResult in include/dbcore.h)
pub const DbSchemaResult = extern struct {
    table_count: u32,
    tables: [*]const DbTableDef,
};

comptime {
    assert(@sizeOf(DbColumnDef) == 2 * @sizeOf(?*anyopaque));
    assert(@sizeOf(DbColumnInfo) > 0);
    assert(@sizeOf(DbIndexDef) > 0);
    assert(@sizeOf(DbTableDef) > 0);
    assert(@sizeOf(DbSchemaResult) > 0);
}

// Backward-compatible type aliases
pub const ColumnDef = DbColumnDef;
pub const ColumnInfo = DbColumnInfo;
pub const IndexDef = DbIndexDef;
pub const TableDef = DbTableDef;

/// Self-contained schema inspection result whose allocations belong to its arena.
pub const SchemaResult = struct {
    arena: std.heap.ArenaAllocator,
    schema: DbSchemaResult,

    pub fn deinit(self: *SchemaResult) void {
        self.arena.deinit();
    }
};

/// Self-contained query execution result whose allocations belong to its arena.
pub const QueryResult = struct {
    arena: std.heap.ArenaAllocator,
    columns: []const DbColumnDef,
    row_count: usize,
    values: []const DbValue, // Flattened 1D slice: (row * columns.len) + col
    has_more: bool,
    execution_time_ns: u64,

    pub fn deinit(self: *QueryResult) void {
        self.arena.deinit();
    }

    pub fn getRow(self: QueryResult, row: usize) []const DbValue {
        const col_count = self.columns.len;
        const start = row * col_count;
        return self.values[start .. start + col_count];
    }

    pub fn getCell(self: QueryResult, row: usize, col: usize) DbValue {
        return self.values[row * self.columns.len + col];
    }
};

comptime {
    assert(@sizeOf(SchemaResult) > 0);
    assert(@sizeOf(QueryResult) > 0);
}
