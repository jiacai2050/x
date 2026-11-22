# Qianliyan WebAssembly (WASM) Architecture

Qianliyan Web runs entirely client-side inside the browser. It requires no backend server, uploads no database files, and executes SQLite queries in-process via WebAssembly.

---

## 1. Core Architecture

- **Unified Engine**: Compiles the same Zig database core (`src/sqlite_driver.zig` + `stdgo.database.sql`) to `wasm32-wasi`.
- **In-Browser WASI VFS**: Mounts user databases into virtual file descriptors via `@bjorn3/browser_wasi_shim`.
- **Direct Linear Memory Access**: JavaScript decodes typed records directly from Wasm linear memory (`memory.buffer`) without intermediate serialization.
- **Offline Support**: A Service Worker precaches the Wasm binary and dependencies for complete offline execution.

---

## 2. Architecture Diagram

```mermaid
flowchart TD
    subgraph Browser ["Browser Frontend (HTML / JS / Tailwind CSS)"]
        UI_Drop["File Dropzone<br/>(Local .sqlite file)"]
        UI_Editor["SQL Editor<br/>(Selection-aware execution)"]
        UI_Sidebar["Sidebar<br/>(Table schema & DDL viewer)"]
        UI_Grid["Result Grid<br/>(Virtual scroll, CSV/JSON export)"]
    end

    subgraph Runtime ["Browser Runtime & WASI VFS"]
        SW["Service Worker (sw.js)<br/>(Offline cache-first interception)"]
        WASI_Shim["browser_wasi_shim<br/>(WASI preview 1 syscalls)"]
        VFS["Virtual File System<br/>(fd 3: 'database.sqlite')"]
    end

    subgraph Bridge ["Linear Memory Bridge"]
        Mem["Linear Memory (memory.buffer)<br/>(DataView, Singleton TextDecoder/Encoder)"]
        Alloc["Memory Management<br/>(db_alloc / db_free)"]
    end

    subgraph WasmCore ["Zig Core Engine (qianliyan.wasm)"]
        WasmEntry["src/wasm.zig<br/>(Exported C-ABI symbols)"]
        Context["SqliteDriver / DbContext<br/>(Pooled connection & active cursor)"]
        Arena["ArenaAllocator<br/>(Per-batch query memory lifecycle)"]
        SQLite["SQLite C Engine<br/>(VFS read/write via WASI libc)"]
    end

    UI_Drop -->|"ArrayBuffer -> Uint8Array"| VFS
    VFS --> WASI_Shim
    WASI_Shim --> SQLite

    UI_Editor -->|"Run Query"| Alloc
    Alloc -->|"Write UTF-8 SQL"| Mem
    Mem -->|"db_query(handle, sqlPtr)"| WasmEntry

    WasmEntry --> Context
    Context --> Arena
    Context --> SQLite

    Arena -.->|"db_free_result"| WasmEntry
    Mem -.->|"DataView decode DbSlice"| UI_Grid
    WasmEntry -.->|"db_get_schema_json"| UI_Sidebar
```

---

## 3. Database Mounting & Opening Flow

When a user selects or drops a SQLite file, it is mounted into the virtual file system without network transfer:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Page as "Browser UI (index.html)"
    participant VFS as "browser_wasi_shim (VFS)"
    participant Wasm as "WebAssembly Instance"
    participant Zig as "Zig Core Engine"

    User->>Page: Drop .sqlite file
    Page->>Page: Read ArrayBuffer as Uint8Array
    Page->>VFS: PreopenDirectory('/', [['database.sqlite', File(bytes)]])
    Page->>Wasm: WebAssembly.instantiate(compiledModule, wasiImport)
    Wasm->>VFS: wasi.start(instance)

    Page->>Wasm: db_alloc(pathBytes.length)
    Wasm-->>Page: Return pathPtr
    Page->>Wasm: Write 'database.sqlite\0' to memory.buffer[pathPtr]

    Page->>Wasm: db_open(pathPtr, errPtr)
    Wasm->>Zig: SqliteDriver.open('database.sqlite')
    Zig->>VFS: read via WASI fd 3
    VFS-->>Zig: SQLite file header & schema pages
    Zig-->>Wasm: Return DbContext pointer
    Wasm-->>Page: Return currentDbHandle

    Page->>Wasm: db_free(pathPtr, len)
    Page->>Wasm: db_get_schema_json(currentDbHandle, &err)
    Wasm->>Zig: Inspect tables, columns, indexes
    Zig-->>Page: Return JSON string pointer
    Page->>Page: JSON.parse() and render table tree
```

---

## 4. Query Execution & Memory Decoding Flow

Queries execute against SQLite in browser memory. The frontend extracts records directly using `DataView` and a singleton `TextDecoder`:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Editor as "SQL Editor"
    participant Engine as "JS Query Runner"
    participant Mem as "Linear Memory Buffer"
    participant Wasm as "Zig Core Wasm"
    participant SQLite as "SQLite Engine"

    User->>Editor: Run Query (⌘ + Enter)
    Editor->>Editor: Validate selection (filter empty or lonely semicolon)
    Editor->>Engine: runQuery(sql)

    Note over Engine: Encode SQL using singleton TextEncoder
    Engine->>Wasm: db_alloc(sqlBytes.length)
    Wasm-->>Engine: Return sqlPtr
    Engine->>Mem: Uint8Array.set(sqlBytes, sqlPtr)

    Engine->>Wasm: db_query(currentDbHandle, sqlPtr, 500, errPtr)
    Wasm->>SQLite: sqlite3_prepare_v2 + sqlite3_step
    SQLite-->>Wasm: Populate rows in Zig ArenaAllocator
    Wasm-->>Engine: Return resPtr (*CDbBatchResult)
    Engine->>Wasm: db_free(sqlPtr, sqlBytes.length)

    Note over Engine: Unpack C struct directly from memory.buffer
    Engine->>Mem: DataView read col_count, row_count, valuesPtr, hasMore
    loop For each cell
        Engine->>Mem: Read DbSlice (dataPtr, size)
        Engine->>Engine: utf8Decoder.decode(Uint8Array(buffer, dataPtr, size))
    end

    Engine->>Wasm: db_free_result(resPtr)
    Note over Wasm: Zig ArenaAllocator.deinit() frees batch memory

    Engine-->>User: Render rows in paginated data grid
```

---

## 5. Streaming Pagination & Interruption Flow

To prevent Wasm linear memory bloat on large tables:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Grid as "HTML Result Grid"
    participant Engine as "JS Query Runner"
    participant Wasm as "Zig Core Wasm"
    participant SQLite as "SQLite Engine"

    alt User fetches more rows
        User->>Grid: Click 'Load More (+500)'
        Grid->>Engine: fetchMoreRows()
        Engine->>Wasm: db_fetch_more(handle, 500, &errPtr)
        Wasm->>SQLite: Pull next 500 rows from active cursor
        Wasm-->>Engine: Return next CDbBatchResult
        Engine->>Engine: Unpack & append rows to currentResult
        Engine->>Wasm: db_free_result(resPtr)
        Engine-->>User: Append rows without full re-render
    else User interrupts query
        User->>Grid: Click 'Cancel'
        Grid->>Engine: cancelQuery()
        Engine->>Wasm: db_interrupt(handle)
        Wasm->>SQLite: sqlite3_interrupt(db)
        Note over SQLite: Query aborts with SQLITE_INTERRUPT
    end
```

---

## 6. Technical Guarantees

| Mechanism                    | Implementation                                            | Guarantee                                                                   |
| :--------------------------- | :-------------------------------------------------------- | :-------------------------------------------------------------------------- |
| **Module Precompilation**    | `WebAssembly.compile` runs once during initialization.    | Subsequent database loads skip JIT compilation.                             |
| **Zero-GC Decoders**         | Global singleton `TextDecoder` and `TextEncoder`.         | Eliminates per-cell object allocations on large datasets.                   |
| **64-bit Integer Safety**    | Checks `BigInt` bounds against `Number.MAX_SAFE_INTEGER`. | Prevents Snowflake ID and timestamp precision loss.                         |
| **Streaming Pagination**     | Cursor streams in 500-row batches via `db_fetch_more`.    | Prevents linear memory exhaustion on large tables.                          |
| **Instant Cancellation**     | `db_interrupt` routes directly to `sqlite3_interrupt`.    | Aborts long queries without crashing the Wasm runtime.                      |
| **Deterministic Freeing**    | Per-query child `ArenaAllocator`.                         | Calling `db_free_result` frees batch memory in $O(1)$ time with zero leaks. |
| **Buffer Detachment Safety** | Resolves `memory.buffer` dynamically on each access.      | Avoids detached buffer errors when Wasm memory grows.                       |
| **Offline Execution**        | Service Worker (`sw.js`) precaches binary and assets.     | Operates without network connectivity after initial load.                   |
