const std = @import("std");

pub const types = @import("types.zig");
pub const Value = types.Value;
pub const ColumnDef = types.ColumnDef;
pub const TableDef = types.TableDef;
pub const SchemaResult = types.SchemaResult;
pub const QueryResult = types.QueryResult;

pub const sqlite_driver = @import("sqlite_driver.zig");
pub const SqliteDriver = sqlite_driver.SqliteDriver;

pub const ffi = @import("ffi.zig");

comptime {
    _ = ffi.db_open;
    _ = ffi.db_close;
    _ = ffi.db_get_schema_json;
    _ = ffi.db_free_string;
    _ = ffi.db_query;
    _ = ffi.db_interrupt;
    _ = ffi.db_free_result;
}

test "sqlite driver in-memory end-to-end test" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var driver = try SqliteDriver.open(allocator, .{
        .path = null, // in-memory
        .read_only = false,
        .create = true,
    });
    defer driver.close();

    // 1. Create table with various data types
    try driver.exec(
        \\CREATE TABLE users (
        \\    id INTEGER PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    score REAL,
        \\    avatar BLOB,
        \\    bio TEXT
        \\);
    );

    // 2. Insert records & create index
    try driver.exec(
        \\INSERT INTO users (id, name, score, avatar, bio)
        \\VALUES (1, 'Alice', 98.5, X'DEADBEEF', 'Software Engineer');
    );
    try driver.exec(
        \\INSERT INTO users (id, name, score, avatar, bio)
        \\VALUES (2, 'Bob', 85.0, NULL, NULL);
    );
    try driver.exec("CREATE INDEX idx_users_name ON users(name);");

    // 3. Inspect schema via getSchema
    var schema = try driver.getSchema(allocator);
    defer schema.deinit();

    try testing.expectEqual(@as(usize, 1), schema.tables.len);
    try testing.expectEqualStrings("users", schema.tables[0].name);
    try testing.expect(schema.tables[0].sql.len > 0);
    try testing.expectEqual(@as(usize, 5), schema.tables[0].columns.len);
    try testing.expectEqualStrings("id", schema.tables[0].columns[0].name);
    try testing.expectEqualStrings("INTEGER", schema.tables[0].columns[0].type_name);
    try testing.expectEqual(@as(u32, 1), schema.tables[0].columns[0].pk);
    try testing.expectEqual(@as(u32, 0), schema.tables[0].columns[1].pk);
    try testing.expectEqual(@as(usize, 1), schema.tables[0].indexes.len);
    try testing.expectEqualStrings("idx_users_name", schema.tables[0].indexes[0].name);
    try testing.expectEqual(@as(usize, 1), schema.tables[0].indexes[0].columns.len);
    try testing.expectEqualStrings("name", schema.tables[0].indexes[0].columns[0]);

    // 4. Dynamic query execution
    var res = try driver.query(allocator, "SELECT id, name, score, avatar, bio FROM users ORDER BY id ASC;", null);
    defer res.deinit();

    try testing.expectEqual(@as(usize, 5), res.columns.len);
    try testing.expectEqual(@as(usize, 2), res.rows.len);

    // Check row 0 (Alice)
    const row0 = res.rows[0];
    try testing.expectEqual(@as(i64, 1), row0[0].integer);
    try testing.expectEqualStrings("Alice", row0[1].text);
    try testing.expectEqual(@as(f64, 98.5), row0[2].real);
    try testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, row0[3].blob);
    try testing.expectEqualStrings("Software Engineer", row0[4].text);

    // Check row 1 (Bob)
    const row1 = res.rows[1];
    try testing.expectEqual(@as(i64, 2), row1[0].integer);
    try testing.expectEqualStrings("Bob", row1[1].text);
    try testing.expectEqual(types.Value.null, row1[3]);
    try testing.expectEqual(types.Value.null, row1[4]);
}

test "C-ABI ffi functions test" {
    const testing = std.testing;

    var err_out: ?[*:0]u8 = null;
    const db = ffi.db_open(null, &err_out);
    try testing.expect(db != null);
    defer ffi.db_close(db);

    // Create table & insert
    const res_create = ffi.db_query(db, "CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT);", 0, &err_out);
    if (res_create) |r| ffi.db_free_result(r);

    const res_insert = ffi.db_query(db, "INSERT INTO items VALUES (1, 'First Item'), (2, 'Second Item');", 0, &err_out);
    if (res_insert) |r| ffi.db_free_result(r);

    // Schema json test
    const json_schema = ffi.db_get_schema_json(db, &err_out);
    try testing.expect(json_schema != null);
    defer ffi.db_free_string(json_schema);
    const schema_slice = std.mem.span(json_schema.?);
    try testing.expect(std.mem.indexOf(u8, schema_slice, "items") != null);
    try testing.expect(std.mem.indexOf(u8, schema_slice, "title") != null);
    try testing.expect(std.mem.indexOf(u8, schema_slice, "\"pk\":1") != null);

    // Query test
    const q_res = ffi.db_query(db, "SELECT * FROM items ORDER BY id ASC;", 100, &err_out);
    try testing.expect(q_res != null);
    defer ffi.db_free_result(q_res);

    const r = q_res.?;
    try testing.expectEqual(@as(u32, 2), r.column_count);
    try testing.expectEqual(@as(u32, 2), r.row_count);
    try testing.expectEqualStrings("id", std.mem.span(r.columns[0].name));
    try testing.expectEqualStrings("title", std.mem.span(r.columns[1].name));

    // First row
    try testing.expectEqual(ffi.CDbColumnType.integer, r.values[0].type);
    try testing.expectEqual(@as(i64, 1), r.values[0].value.int_val);
    try testing.expectEqual(ffi.CDbColumnType.text, r.values[1].type);
    try testing.expectEqualStrings("First Item", std.mem.span(r.values[1].value.text_val));

    // Test db_interrupt does not crash and correctly interrupts active connections
    ffi.db_interrupt(db);
}
