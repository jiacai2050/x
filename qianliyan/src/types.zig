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

    pub fn slice(self: DbSlice) []const u8 {
        return self.data[0..self.size];
    }

    pub fn dupe(self: DbSlice, allocator: std.mem.Allocator) !DbSlice {
        const copy = try allocator.dupe(u8, self.slice());
        return .{ .data = copy.ptr, .size = copy.len };
    }
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

    pub fn getText(self: DbValue) ?[]const u8 {
        if (self.type == .text) {
            return self.value.text_val.slice();
        }
        return null;
    }

    pub fn getBlob(self: DbValue) ?[]const u8 {
        if (self.type == .blob) {
            return self.value.blob_val.slice();
        }
        return null;
    }

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
            .text => try writer.writeAll(self.value.text_val.slice()),
            .blob => try writer.print("<Blob {d}B>", .{self.value.blob_val.size}),
        }
    }
};

comptime {
    assert(@sizeOf(DbSlice) == 2 * @sizeOf(usize));
    assert(@sizeOf(DbValueUnion) == @max(@sizeOf(i64), @sizeOf(DbSlice)));
    assert(@offsetOf(DbValue, "value") >= @sizeOf(DbColumnType));
    assert(@sizeOf(DbValue) == @offsetOf(DbValue, "value") + @sizeOf(DbValueUnion));
}

/// C-compatible column definition for query results (matching DbColumnDef in include/dbcore.h)
pub const DbColumnDef = extern struct {
    name: DbSlice,
    type_name: DbSlice,

    pub fn getName(self: DbColumnDef) []const u8 {
        return self.name.slice();
    }

    pub fn getTypeName(self: DbColumnDef) []const u8 {
        return self.type_name.slice();
    }
};

/// C-compatible column definition for table schema (matching DbColumnInfo in include/dbcore.h)
pub const DbColumnInfo = extern struct {
    name: DbSlice,
    type_name: DbSlice,
    pk: u32 = 0,

    pub fn getName(self: DbColumnInfo) []const u8 {
        return self.name.slice();
    }

    pub fn getTypeName(self: DbColumnInfo) []const u8 {
        return self.type_name.slice();
    }
};

/// C-compatible index definition (matching DbIndexDef in include/dbcore.h)
pub const DbIndexDef = extern struct {
    name: DbSlice,
    is_unique: bool,
    column_count: u32,
    columns: [*]const DbSlice,

    pub fn getName(self: DbIndexDef) []const u8 {
        return self.name.slice();
    }
};

/// C-compatible table definition (matching DbTableDef in include/dbcore.h)
pub const DbTableDef = extern struct {
    name: DbSlice,
    sql: DbSlice,
    column_count: u32,
    columns: [*]const DbColumnInfo,
    index_count: u32,
    indexes: [*]const DbIndexDef,

    pub fn getName(self: DbTableDef) []const u8 {
        return self.name.slice();
    }

    pub fn getSql(self: DbTableDef) ?[]const u8 {
        if (self.sql.size == 0) return null;
        return self.sql.slice();
    }
};

/// C-compatible schema result (matching DbSchemaResult in include/dbcore.h)
pub const DbSchemaResult = extern struct {
    table_count: u32,
    tables: [*]const DbTableDef,
};

comptime {
    assert(@sizeOf(DbColumnDef) == 2 * @sizeOf(DbSlice));
    assert(@offsetOf(DbColumnInfo, "pk") == 2 * @sizeOf(DbSlice));
    assert(@sizeOf(DbIndexDef) >=
        @sizeOf(DbSlice) + @sizeOf(bool) + @sizeOf(u32) + @sizeOf([*]const DbSlice));
    assert(@offsetOf(DbTableDef, "columns") >= 2 * @sizeOf(DbSlice) + @sizeOf(u32));
    assert(@offsetOf(DbTableDef, "indexes") >=
        @offsetOf(DbTableDef, "columns") + @sizeOf([*]const DbColumnInfo) + @sizeOf(u32));
    assert(@offsetOf(DbSchemaResult, "tables") >= @sizeOf(u32));
    assert(@sizeOf(DbSchemaResult) ==
        @offsetOf(DbSchemaResult, "tables") + @sizeOf([*]const DbTableDef));
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
        assert(row < self.row_count);
        const col_count = self.columns.len;
        const start = row * col_count;
        return self.values[start .. start + col_count];
    }

    pub fn getCell(self: QueryResult, row: usize, col: usize) DbValue {
        assert(row < self.row_count);
        assert(col < self.columns.len);
        return self.values[row * self.columns.len + col];
    }
};

comptime {
    assert(@sizeOf(SchemaResult) > 0);
    assert(@sizeOf(QueryResult) > 0);
}
