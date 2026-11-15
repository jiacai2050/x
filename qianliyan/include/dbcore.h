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
    const char* name;
    const char* type_name;
} DbColumnDef;

typedef struct {
    DbColumnType type;
    union {
        int64_t int_val;
        double real_val;
        const char* text_val;
        struct {
            const uint8_t* data;
            size_t size;
        } blob_val;
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

// Allocate heap buffer inside Zig runtime.
uint8_t* db_alloc(size_t size);

// Free heap buffer allocated by db_alloc.
void db_free(uint8_t* ptr, size_t size);

// Open database from filesystem path. Returns handle, or NULL on error with error_out set.
DbHandle db_open(const char* path, char** error_out);

// Close database handle.
void db_close(DbHandle handle);

// Retrieve schema as JSON string. Caller must free with db_free_string.
char* db_get_schema_json(DbHandle handle, char** error_out);

// Free heap string allocated by Zig.
void db_free_string(char* str);

// Synchronously execute query and return batch result.
DbBatchResult* db_query(DbHandle handle, const char* sql, uint32_t limit, char** error_out);

// Interrupt a long running query on the handle. Safe to call from another thread.
void db_interrupt(DbHandle handle);

// Free result allocated by db_query.
void db_free_result(DbBatchResult* result);

#ifdef __cplusplus
}
#endif

#endif // DB_CORE_H
