const root = @import("root.zig");

// Force compilation and symbol inclusion for all exported C-ABI functions.
comptime {
    _ = root.ffi.db_alloc;
    _ = root.ffi.db_free;
    _ = root.ffi.db_open;
    _ = root.ffi.db_close;
    _ = root.ffi.db_errmsg;
    _ = root.ffi.db_get_schema;
    _ = root.ffi.db_free_schema;
    _ = root.ffi.db_get_schema_json;
    _ = root.ffi.db_free_string;
    _ = root.ffi.db_query;
    _ = root.ffi.db_interrupt;
    _ = root.ffi.db_fetch_more;
    _ = root.ffi.db_close_cursor;
    _ = root.ffi.db_free_result;
}

/// Entry point when compiled as a WebAssembly WASI executable.
/// It performs no-op initialization so that exported C-ABI functions remain accessible.
pub fn main() void {}
