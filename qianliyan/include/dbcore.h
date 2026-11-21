#ifndef DB_CORE_H
#define DB_CORE_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void* DbHandle;

typedef enum {
    DB_TYPE_NULL = 0,
    DB_TYPE_INTEGER = 1,
    DB_TYPE_REAL = 2,
    DB_TYPE_TEXT = 3,
    DB_TYPE_BLOB = 4,
} DbColumnType;

typedef struct {
    const char* data;
    size_t size;
} DbSlice;

typedef struct {
    DbSlice name;
    DbSlice type_name;
} DbColumnDef;

typedef struct {
    DbColumnType type;
    union {
        int64_t int_val;
        double real_val;
        DbSlice text_val;
        DbSlice blob_val;
    } value;
} DbValue;

typedef struct {
    uint32_t column_count;
    const DbColumnDef* columns;
    uint32_t row_count;
    // Flattened 1D array of values: (row * column_count) + col
    const DbValue* values;
    bool has_more;
    uint64_t execution_time_ns;
} DbBatchResult;

// Native C Schema Structures
typedef struct {
    DbSlice name;
    DbSlice type_name;
    uint32_t pk;
} DbColumnInfo;

typedef struct {
    DbSlice name;
    bool is_unique;
    uint32_t column_count;
    const DbSlice* columns;
} DbIndexDef;

typedef struct {
    DbSlice name;
    DbSlice sql;
    uint32_t column_count;
    const DbColumnInfo* columns;
    uint32_t index_count;
    const DbIndexDef* indexes;
} DbTableDef;

typedef struct {
    uint32_t table_count;
    const DbTableDef* tables;
} DbSchemaResult;

// Allocate heap buffer inside Zig runtime.
uint8_t* db_alloc(size_t size);

// Free heap buffer allocated by db_alloc.
void db_free(uint8_t* ptr, size_t size);

// Open database from filesystem path. Returns handle, or NULL on error.
// Optional error_out can be passed, or caller can read db_errmsg(handle).
DbHandle db_open(const char* path, char** error_out);

// Close database handle.
void db_close(DbHandle handle);

// Get last error message for the database handle without needing to free it.
const char* db_errmsg(DbHandle handle);

// Native C Schema Inspection. Caller must free with db_free_schema.
DbSchemaResult* db_get_schema(DbHandle handle, char** error_out);

// Free schema result allocated by db_get_schema.
void db_free_schema(DbSchemaResult* schema);

// Retrieve schema as JSON string (Kept for WebAssembly compatibility). Caller must free with db_free_string.
char* db_get_schema_json(DbHandle handle, char** error_out);

// Free heap string allocated by Zig.
void db_free_string(char* str);

// Synchronously execute query and return batch result.
DbBatchResult* db_query(DbHandle handle, const char* sql, uint32_t limit, char** error_out);

// Fetch next batch of rows from the currently active cursor on this handle.
// Note on current limitation:
// Each DbHandle currently maintains a single active cursor. If another query, DDL, or schema
// inspection is run on this handle in between, the previous cursor is invalidated and closed.
// Returns next batch result, or NULL if no active cursor exists / on error. Caller frees with db_free_result.
DbBatchResult* db_fetch_more(DbHandle handle, uint32_t limit, char** error_out);

// Close any active cursor on the database handle and release database locks.
void db_close_cursor(DbHandle handle);

// Interrupt a long running query on the handle. Safe to call from another thread.
void db_interrupt(DbHandle handle);

// Free result allocated by db_query.
void db_free_result(DbBatchResult* result);

#ifdef __cplusplus
}
#endif

#endif // DB_CORE_H
