const std = @import("std");

pub const types = @import("types.zig");
pub const DbValue = types.DbValue;
pub const ColumnDef = types.ColumnDef;
pub const TableDef = types.TableDef;
pub const SchemaResult = types.SchemaResult;
pub const QueryResult = types.QueryResult;

pub const sqlite_driver = @import("sqlite_driver.zig");
pub const SqliteDriver = sqlite_driver.SqliteDriver;

pub const ffi = @import("ffi.zig");

// Force compilation and symbol inclusion for all exported C-ABI functions.
comptime {
    _ = ffi.db_alloc;
    _ = ffi.db_free;
    _ = ffi.db_open;
    _ = ffi.db_close;
    _ = ffi.db_errmsg;
    _ = ffi.db_get_schema;
    _ = ffi.db_free_schema;
    _ = ffi.db_get_schema_json;
    _ = ffi.db_free_string;
    _ = ffi.db_query;
    _ = ffi.db_fetch_more;
    _ = ffi.db_close_cursor;
    _ = ffi.db_interrupt;
    _ = ffi.db_free_result;
}

// Test: SQLite Driver in-memory end-to-end functionality.
// Goal: Verify table creation, DDL execution, data insertion, schema inspection,
// and typed query retrieval across all supported SQLite storage classes.
test "sqlite driver in-memory end-to-end test" {
    const testing = std.testing;
    const gpa = testing.allocator;

    var driver = try SqliteDriver.open(gpa, .{
        .path = null, // In-memory database.
        .read_only = false,
        .create = true,
    });
    defer driver.close();

    // 1. Create table with various data types.
    try driver.exec(
        \\CREATE TABLE users (
        \\    id INTEGER PRIMARY KEY,
        \\    name TEXT NOT NULL,
        \\    score REAL,
        \\    avatar BLOB,
        \\    bio TEXT
        \\);
    );

    // 2. Insert records and create index.
    try driver.exec(
        \\INSERT INTO users (id, name, score, avatar, bio)
        \\VALUES (1, 'Alice', 98.5, X'DEADBEEF', 'Software Engineer');
    );
    try driver.exec(
        \\INSERT INTO users (id, name, score, avatar, bio)
        \\VALUES (2, 'Bob', 85.0, NULL, NULL);
    );
    try driver.exec("CREATE INDEX idx_users_name ON users(name);");

    // 3. Inspect schema via getSchema.
    var schema = try driver.getSchema(gpa);
    defer schema.deinit();

    try testing.expectEqual(@as(u32, 1), schema.schema.table_count);
    try testing.expectEqualStrings("users", schema.schema.tables[0].getName());
    try testing.expect(schema.schema.tables[0].getSql().?.len > 0);
    try testing.expectEqual(@as(u32, 5), schema.schema.tables[0].column_count);
    try testing.expectEqualStrings("id", schema.schema.tables[0].columns[0].getName());
    try testing.expectEqualStrings("INTEGER", schema.schema.tables[0].columns[0].getTypeName());
    try testing.expectEqual(@as(u32, 1), schema.schema.tables[0].columns[0].pk);
    try testing.expectEqual(@as(u32, 0), schema.schema.tables[0].columns[1].pk);
    try testing.expectEqual(@as(u32, 1), schema.schema.tables[0].index_count);
    try testing.expectEqualStrings("idx_users_name", schema.schema.tables[0].indexes[0].getName());
    try testing.expectEqual(@as(u32, 1), schema.schema.tables[0].indexes[0].column_count);
    try testing.expectEqualStrings("name", schema.schema.tables[0].indexes[0].columns[0].data[0..schema.schema.tables[0].indexes[0].columns[0].size]);

    // 4. Dynamic query execution.
    var res = try driver.query(
        gpa,
        "SELECT id, name, score, avatar, bio FROM users ORDER BY id ASC;",
        null,
    );
    defer res.deinit();

    try testing.expectEqual(@as(usize, 5), res.columns.len);
    try testing.expectEqualStrings("id", res.columns[0].getName());
    try testing.expectEqualStrings("INTEGER", res.columns[0].getTypeName());
    try testing.expectEqualStrings("name", res.columns[1].getName());
    try testing.expectEqualStrings("TEXT", res.columns[1].getTypeName());
    try testing.expectEqualStrings("score", res.columns[2].getName());
    try testing.expectEqualStrings("REAL", res.columns[2].getTypeName());
    try testing.expectEqualStrings("avatar", res.columns[3].getName());
    try testing.expectEqualStrings("BLOB", res.columns[3].getTypeName());
    try testing.expectEqualStrings("bio", res.columns[4].getName());
    try testing.expectEqualStrings("TEXT", res.columns[4].getTypeName());
    try testing.expectEqual(@as(usize, 2), res.row_count);
    try testing.expect(!res.has_more);

    // Check row 0 (Alice).
    const row0 = res.getRow(0);
    try testing.expectEqual(@as(i64, 1), row0[0].value.int_val);
    try testing.expectEqualStrings("Alice", row0[1].value.text_val.data[0..row0[1].value.text_val.size]);
    try testing.expectEqual(@as(f64, 98.5), row0[2].value.real_val);
    try testing.expectEqualSlices(u8, &[_]u8{ 0xDE, 0xAD, 0xBE, 0xEF }, row0[3].value.blob_val.data[0..row0[3].value.blob_val.size]);
    try testing.expectEqualStrings("Software Engineer", row0[4].value.text_val.data[0..row0[4].value.text_val.size]);

    // Check row 1 (Bob).
    const row1 = res.getRow(1);
    try testing.expectEqual(@as(i64, 2), row1[0].value.int_val);
    try testing.expectEqualStrings("Bob", row1[1].value.text_val.data[0..row1[1].value.text_val.size]);
    try testing.expectEqual(types.DbColumnType.null, row1[3].type);
    try testing.expectEqual(types.DbColumnType.null, row1[4].type);
}

// Test: C-ABI FFI exported functions test.
// Goal: Verify C-ABI lifecycle functions including handle creation, schema serialization,
// memory freeing, query batches, interruption safety, and exact error propagation.
test "C-ABI ffi functions test" {
    const testing = std.testing;

    var err_out: ?[*:0]u8 = null;
    const db = ffi.db_open(null, &err_out);
    try testing.expect(db != null);
    defer ffi.db_close(db);

    // Create table and insert records.
    const res_create = ffi.db_query(
        db,
        "CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT);",
        0,
        &err_out,
    );
    if (res_create) |r| ffi.db_free_result(r);

    const res_insert = ffi.db_query(
        db,
        "INSERT INTO items VALUES (1, 'First Item'), (2, 'Second Item');",
        0,
        &err_out,
    );
    if (res_insert) |r| ffi.db_free_result(r);

    // Schema JSON serialization test.
    const json_schema = ffi.db_get_schema_json(db, &err_out);
    try testing.expect(json_schema != null);
    defer ffi.db_free_string(json_schema);
    const schema_slice = std.mem.span(json_schema.?);
    try testing.expect(std.mem.indexOf(u8, schema_slice, "items") != null);
    try testing.expect(std.mem.indexOf(u8, schema_slice, "title") != null);
    try testing.expect(std.mem.indexOf(u8, schema_slice, "\"pk\":1") != null);

    // Native C-ABI schema inspection test.
    const native_schema = ffi.db_get_schema(db, &err_out);
    try testing.expect(native_schema != null);
    defer ffi.db_free_schema(native_schema);
    const s = native_schema.?;
    try testing.expectEqual(@as(u32, 1), s.table_count);
    try testing.expectEqualStrings("items", s.tables[0].getName());
    try testing.expectEqual(@as(u32, 2), s.tables[0].column_count);
    try testing.expectEqualStrings("id", s.tables[0].columns[0].getName());
    try testing.expectEqual(@as(u32, 1), s.tables[0].columns[0].pk);

    // Batch query test.
    const q_res = ffi.db_query(db, "SELECT * FROM items ORDER BY id ASC;", 100, &err_out);
    try testing.expect(q_res != null);
    defer ffi.db_free_result(q_res);

    const r = q_res.?;
    try testing.expectEqual(@as(u32, 2), r.column_count);
    try testing.expectEqual(@as(u32, 2), r.row_count);
    try testing.expectEqualStrings("id", r.columns[0].getName());
    try testing.expectEqualStrings("title", r.columns[1].getName());

    // First row verification.
    try testing.expectEqual(ffi.CDbColumnType.integer, r.values[0].type);
    try testing.expectEqual(@as(i64, 1), r.values[0].value.int_val);
    try testing.expectEqual(ffi.CDbColumnType.text, r.values[1].type);
    const text_slice = r.values[1].value.text_val.data[0..r.values[1].value.text_val.size];
    try testing.expectEqualStrings("First Item", text_slice);

    // Cursor & fetch_more test:
    const res_insert3 = ffi.db_query(
        db,
        "INSERT INTO items VALUES (3, 'Third Item');",
        0,
        &err_out,
    );
    if (res_insert3) |r_ins| ffi.db_free_result(r_ins);

    // Initial query with limit = 1 -> should have has_more = true
    const cur_res1 = ffi.db_query(db, "SELECT * FROM items ORDER BY id ASC;", 1, &err_out);
    try testing.expect(cur_res1 != null);
    defer ffi.db_free_result(cur_res1);
    try testing.expectEqual(@as(u32, 1), cur_res1.?.row_count);
    try testing.expect(cur_res1.?.has_more);
    try testing.expectEqual(@as(i64, 1), cur_res1.?.values[0].value.int_val);

    // Fetch next batch with limit = 1 -> should have has_more = true
    const cur_res2 = ffi.db_fetch_more(db, 1, &err_out);
    try testing.expect(cur_res2 != null);
    defer ffi.db_free_result(cur_res2);
    try testing.expectEqual(@as(u32, 1), cur_res2.?.row_count);
    try testing.expect(cur_res2.?.has_more);
    try testing.expectEqual(@as(i64, 2), cur_res2.?.values[0].value.int_val);

    // Fetch next batch with limit = 1 -> returns last item, has_more = false, auto closes cursor
    const cur_res3 = ffi.db_fetch_more(db, 1, &err_out);
    try testing.expect(cur_res3 != null);
    defer ffi.db_free_result(cur_res3);
    try testing.expectEqual(@as(u32, 1), cur_res3.?.row_count);
    try testing.expect(!cur_res3.?.has_more);
    try testing.expectEqual(@as(i64, 3), cur_res3.?.values[0].value.int_val);

    // Next fetch returns null because cursor was closed automatically
    const cur_res4 = ffi.db_fetch_more(db, 1, &err_out);
    try testing.expect(cur_res4 == null);

    // Test explicit db_close_cursor
    const cur_res5 = ffi.db_query(db, "SELECT * FROM items ORDER BY id ASC;", 1, &err_out);
    try testing.expect(cur_res5 != null);
    defer ffi.db_free_result(cur_res5);
    try testing.expect(cur_res5.?.has_more);
    ffi.db_close_cursor(db);
    const cur_res6 = ffi.db_fetch_more(db, 1, &err_out);
    try testing.expect(cur_res6 == null);

    // Test db_interrupt does not crash and safely handles connection interruption.
    ffi.db_interrupt(db);

    // Test lastError exact error reporting on syntax error via db_query.
    const err_res = ffi.db_query(db, "SELECT * FORM items;", 0, &err_out);
    try testing.expect(err_res == null);
    try testing.expect(err_out != null);
    if (err_out) |e_str| {
        defer ffi.db_free_string(e_str);
        const span = std.mem.span(e_str);
        try testing.expect(std.mem.indexOf(u8, span, "syntax error") != null);
    }
    // Verify db_errmsg retrieves the exact same message without requiring deallocation.
    const errmsg = ffi.db_errmsg(db);
    try testing.expect(errmsg != null);
    try testing.expect(std.mem.indexOf(u8, std.mem.span(errmsg.?), "syntax error") != null);

    // Test empty statement / comment only / semicolon does not panic and cleanly returns Empty SQL statement error.
    const empty_res = ffi.db_query(db, ";", 0, &err_out);
    try testing.expect(empty_res == null);
    try testing.expect(err_out != null);
    if (err_out) |e_str| {
        defer ffi.db_free_string(e_str);
        try testing.expectEqualStrings("Empty SQL statement", std.mem.span(e_str));
        err_out = null;
    }

    const comment_res = ffi.db_query(db, "-- only a comment", 0, &err_out);
    try testing.expect(comment_res == null);
    try testing.expect(err_out != null);
    if (err_out) |e_str| {
        defer ffi.db_free_string(e_str);
        try testing.expectEqualStrings("Empty SQL statement", std.mem.span(e_str));
        err_out = null;
    }
}

