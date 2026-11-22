# Qianliyan WebAssembly (WASM) Architecture & Data Flow

This document details the client-side architecture, virtual file system (VFS), and linear memory bridge of Qianliyan WebAssembly.

---

## 1. Architectural Philosophy

Qianliyan Web runs **100% inside the user's browser**. There are zero backend servers, zero database uploads, and zero tracking:

- **Unified Core**: Compiles the exact same Zig database engine (`src/sqlite_driver.zig` + `stdgo.database.sql`) to `wasm32-wasi`.
- **In-Browser WASI VFS**: Leverages a browser-side WASI shim (`@bjorn3/browser_wasi_shim`) to mount user database files into virtual file descriptors.
- **Direct Linear Memory Access**: JavaScript reads typed records and UTF-8 strings directly out of WebAssembly linear memory (`memory.buffer`).

---

## 2. System Architecture Overview

```mermaid
flowchart TD
    subgraph Browser ["Web Browser Frontend (HTML / JS / Tailwind CSS)"]
        UI_Drop["Dropzone & File Input<br/>(Local .sqlite file)"]
        UI_Editor["SQL Editor<br/>(Query input & Sample DB trigger)"]
        UI_Sidebar["Sidebar & Table Tree<br/>(Schema & Index Viewer)"]
        UI_Grid["Result Data Grid<br/>(Scrollable table, CSV/JSON export)"]
    end

    subgraph Runtime ["Browser Runtime & WASI VFS"]
        WASI_Shim["browser_wasi_shim<br/>(WASI Snapshot Preview 1)"]
        VFS["Virtual File System (PreopenDirectory)<br/>(fd 3: Virtual 'database.sqlite')"]
    end

    subgraph Bridge ["Linear Memory Bridge (JS DataView)"]
        Mem["Wasm Linear Memory (memory.buffer)<br/>(TypedArray, TextEncoder, TextDecoder)"]
        Alloc["Memory Allocator<br/>(db_alloc / db_free)"]
    end

    subgraph WasmCore ["Zig Core Engine (qianliyan.wasm)"]
        WasmEntry["src/wasm.zig<br/>(Exported C-ABI symbols)"]
        Context["SqliteDriver / DbContext<br/>(Single-connection pooled execution)"]
        Arena["ArenaAllocator<br/>(Per-batch query memory lifecycle)"]
        SQLite["SQLite C Engine<br/>(Direct VFS read/write via WASI libc)"]
    end

    UI_Drop -->|"ArrayBuffer -> Uint8Array"| VFS
    VFS --> WASI_Shim
    WASI_Shim -->|"wasi_snapshot_preview1"| SQLite

    UI_Editor -->|"Run Query"| Alloc
    Alloc -->|"write SQL string"| Mem
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

When a user selects or drops a SQLite file, it is mounted into the virtual file system without sending any bytes over the network:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Page as "Browser UI (index.html)"
    participant VFS as "browser_wasi_shim (VFS)"
    participant Wasm as "WebAssembly Instance"
    participant Zig as "Zig Core Engine"

    User->>Page: Drop .sqlite file
    Page->>Page: Read file as ArrayBuffer into Uint8Array
    Page->>VFS: Create PreopenDirectory('/', [['database.sqlite', File(userBytes)]])
    Page->>Wasm: WebAssembly.instantiate(qianliyan.wasm, wasiImport)
    Wasm->>VFS: wasi.start(instance)

    Note over Page: Allocate path string in Wasm linear memory
    Page->>Wasm: db_alloc(pathBytes.length)
    Wasm-->>Page: Return pathPtr
    Page->>Wasm: Write 'database.sqlite\0' into memory.buffer[pathPtr]

    Page->>Wasm: db_open(pathPtr, errPtr)
    Wasm->>Zig: SqliteDriver.open('database.sqlite')
    Zig->>VFS: openat / read via WASI fd 3
    VFS-->>Zig: SQLite file header & schema pages
    Zig-->>Wasm: Return DbContext pointer
    Wasm-->>Page: Return currentDbHandle

    Page->>Wasm: db_free(pathPtr, len)
    Page->>Wasm: db_get_schema_json(currentDbHandle, &err)
    Wasm->>Zig: Inspect tables, columns, indexes and serialize to JSON
    Zig-->>Page: Return JSON string pointer
    Page->>Page: JSON.parse() and render sidebar tables
```

---

## 4. Query Execution & Zero-Copy Reading Flow

Queries execute directly against SQLite in browser memory. The frontend reads records using `DataView` and a global singleton `TextDecoder`:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Editor as "SQL Editor"
    participant Engine as "JS Query Runner"
    participant Mem as "Linear Memory Buffer"
    participant Wasm as "Zig Core Wasm"
    participant SQLite as "SQLite Engine"

    User->>Editor: Click Run (or press ⌘ + Enter)
    Editor->>Editor: Validate selection (filter empty or lonely semicolon)
    Editor->>Engine: runQuery(sql)

    Note over Engine: Encode SQL via singleton TextEncoder
    Engine->>Wasm: db_alloc(sqlBytes.length)
    Wasm-->>Engine: Return sqlPtr
    Engine->>Mem: Uint8Array.set(sqlBytes, sqlPtr)

    Engine->>Wasm: db_query(currentDbHandle, sqlPtr, 500, errPtr)
    Wasm->>SQLite: sqlite3_prepare_v2 + sqlite3_step
    SQLite-->>Wasm: Produce rows in Zig ArenaAllocator
    Wasm-->>Engine: Return resPtr (*CDbBatchResult)
    Engine->>Wasm: db_free(sqlPtr, sqlBytes.length)

    Note over Engine: Unpack C struct directly from memory.buffer
    Engine->>Mem: DataView read column_count, row_count, valuesPtr, hasMore
    loop For each column and cell
        Engine->>Mem: Read DbSlice (dataPtr, size)
        Engine->>Engine: utf8Decoder.decode(Uint8Array(buffer, dataPtr, size))
    end

    Engine->>Wasm: db_free_result(resPtr)
    Note over Wasm: Zig ArenaAllocator.deinit() frees batch memory

    Engine-->>User: Render rows into responsive HTML Table (with pagination)
```

---

## 5. Streaming Pagination & Query Cancellation Flow

To mirror the native macOS experience and avoid WASM linear memory bloat:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Grid as "HTML Result Grid"
    participant Engine as "JS Query Runner"
    participant Wasm as "Zig Core Wasm"
    participant SQLite as "SQLite Engine"

    alt User loads more rows
        User->>Grid: Click 'Load More (+500)'
        Grid->>Engine: fetchMoreRows()
        Engine->>Wasm: db_fetch_more(handle, 500, &errPtr)
        Wasm->>SQLite: Fetch next batch from active cursor
        Wasm-->>Engine: Return next CDbBatchResult
        Engine->>Engine: Unpack & append rows to currentResult
        Engine->>Wasm: db_free_result(resPtr)
        Engine-->>User: Update table & pagination indicator smoothly
    else User cancels long query
        User->>Grid: Click 'Cancel'
        Grid->>Engine: cancelQuery()
        Engine->>Wasm: db_interrupt(handle)
        Wasm->>SQLite: sqlite3_interrupt(db)
        Note over SQLite: Query halts with SQLITE_INTERRUPT
    end
```

---

## 6. Memory Management & Performance Guarantees

| Concern                                   | Solution in Qianliyan WASM                                                                                                                                                                                                       |
| :---------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Module Precompilation Cache**           | `WebAssembly.compile` is run once at startup. Database switches call `WebAssembly.instantiate(wasmModule, ...)` directly, eliminating JIT re-compilation delay.                                                                  |
| **Zero GC Pressure on Decoding**          | Global singleton `TextDecoder` and `TextEncoder` instances decode all `DbSlice` strings and encode SQL, eliminating thousands of transient object allocations per query.                                                         |
| **Memory Isolation**                      | WebAssembly sandboxing ensures SQLite and Zig cannot access arbitrary browser memory or filesystem outside of preopened descriptors.                                                                                             |
| **Streaming Pagination (`LIMIT 500`)**    | Queries stream in 500-row batches via `db_fetch_more`, preventing large tables from overflowing 32-bit WASM memory.                                                                                                              |
| **Instant Cancellation (`db_interrupt`)** | `db_interrupt` routes directly to `sqlite3_interrupt` to abort runaway queries without crashing the WASM runtime.                                                                                                                |
| **Zero Memory Leaks**                     | Queries run inside a per-execution `ArenaAllocator`. Calling `db_free_result` frees all allocations for that batch in $O(1)$ time.                                                                                               |
| **Linear Memory Buffer Detachment**       | In WebAssembly, when memory grows via `memory.grow()`, old `ArrayBuffer` instances become detached. Qianliyan always re-queries `wasmInstance.exports.memory.buffer` immediately before constructing `DataView` or `Uint8Array`. |
| **In-Memory & Sample DB Support**         | Calling `db_open(0, 0)` invokes SQLite `:memory:` mode directly in WASM RAM, allowing dynamic table generation and ad-hoc experiments without loading files.                                                                     |
