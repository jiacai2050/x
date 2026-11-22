# Qianliyan macOS Client Architecture & Data Flow

This document details the internal architecture, state management, and end-to-end data flow of Qianliyan on macOS.

---

## 1. System Architecture Overview

The macOS client is built using pure **SwiftUI** and **AppKit**, communicating with the **Zig Core** database engine via an in-process **C-ABI bridge** (`CQianliyan`).

```mermaid
flowchart TD
    subgraph UI ["Presentation Layer (SwiftUI / AppKit)"]
        Home["HomeView<br/>(Recent DBs & Double-click Open)"]
        Sidebar["SidebarView<br/>(Tables, Columns, Indexes)"]
        Editor["QueryEditorView<br/>(NSTextView & Selection Filter)"]
        Grid["ResultTableView<br/>(Virtual Scrolling Data Grid)"]
    end

    subgraph ViewModel ["State & Orchestration (@Observable)"]
        VM["DBViewModel<br/>(@MainActor, Reactive Tabs, Schema)"]
    end

    subgraph Bridge ["Concurrency & C-ABI Bridge"]
        Client["DBClient<br/>(Thread-Safe NSLock, Task.detached)"]
        FFI["CQianliyan (dbcore.h)<br/>(C-ABI Function Pointers)"]
    end

    subgraph Core ["Zig Core Engine (qianliyan.a)"]
        Context["DbContext / SqliteDriver<br/>(Connection Pooling & Cursor)"]
        Arena["ArenaAllocator<br/>(Per-Batch Memory Lifecycle)"]
        StdGo["stdgo.database.sql<br/>(Transaction & Driver Abstraction)"]
        SQLite["SQLite C Engine<br/>(Single-Connection In-Process DB)"]
    end

    Home -->|"openRecent(item)"| VM
    Editor -->|"executeQuery(sql)"| VM
    Sidebar -->|"select table / DDL"| VM
    Grid -->|"loadMoreRows()"| VM

    VM -->|"async calls"| Client
    Client -->|"Task.detached"| FFI
    FFI -->|"C-ABI"| Context

    Context --> Arena
    Context --> StdGo
    StdGo --> SQLite

    Arena -.->|"Zero-leak batch free"| Context
    Client -.->|"Vectorized UTF-8 decode"| VM
    VM -.->|"@MainActor publish"| UI
```

---

## 2. End-to-End Query Execution Flow

When a user executes a query (via `⌘ + Return` or the **Run** button), the data flows asynchronously through four layers before rendering in the result grid:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Editor as "QueryEditorView"
    participant VM as "DBViewModel (@MainActor)"
    participant Client as "DBClient (Task.detached)"
    participant CBridge as "C-ABI (CQianliyan)"
    participant Zig as "Zig Core (SqliteDriver)"
    participant SQLite as "SQLite Engine"

    User->>Editor: Press Command + Return
    Editor->>Editor: Validate selection (filter empty or lonely semicolon)
    Editor->>VM: executeQuery(targetSql)

    VM->>VM: Set tab.isExecuting = true
    VM->>Client: query(sql, limit: 500)

    Note over Client: Runs on background worker thread
    Client->>CBridge: db_query(handle, sql, limit, &errPtr)
    CBridge->>Zig: driver.query(gpa, sql, limit)
    Zig->>SQLite: sqlite3_prepare_v2 + sqlite3_step
    SQLite-->>Zig: Rows stream (INTEGER, TEXT, BLOB...)

    Note over Zig: Allocates QueryResult in child ArenaAllocator
    Zig-->>CBridge: Return pointer to CDbBatchResult
    CBridge-->>Client: Return C struct pointer
    Note over Client: Vectorized UTF-8 decoding (DbSlice)
    Client->>Client: Decode column names and cells into QueryResultData
    Client->>CBridge: db_free_result(resPtr)
    Note over Zig: ArenaAllocator.deinit() frees all batch memory

    Client-->>VM: Return QueryResultData
    Note over VM: Dispatched back to @MainActor
    VM->>VM: Update tab.results, tab.isExecuting = false
    VM-->>User: ResultTableView re-renders with formatted rows
```

---

## 3. Database Connection & Schema Inspection Flow

Opening a database automatically inspects and caches its table definitions, columns, primary keys, and index metadata:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Home as "HomeView"
    participant VM as "DBViewModel"
    participant Client as "DBClient"
    participant CBridge as "C-ABI (CQianliyan)"
    participant Zig as "Zig Core (getSchema)"

    User->>Home: Double-click database item (or press Return)
    Home->>VM: openRecent(item)
    VM->>Client: open(path)
    Client->>CBridge: db_open(path, &err)
    CBridge->>Zig: SqliteDriver.open()

    VM->>Client: getSchema()
    Client->>CBridge: db_get_schema(handle, &err)
    Zig->>Zig: Query sqlite_master + PRAGMA table_info + PRAGMA index_list
    Zig-->>CBridge: Return pointer to CDbSchemaResult
    Client->>Client: Decode DbTableDef, DbColumnInfo, DbIndexDef
    Client->>CBridge: db_free_schema(schemaPtr)

    Client-->>VM: Return TableInfo list
    VM->>VM: Update schema tree, switch view to WorkspaceView
    VM-->>User: Display SidebarView with table tree & open Default Tab
```

---

## 4. Query Cancellation Flow

Qianliyan supports responsive, thread-safe cancellation without blocking the UI or leaving orphaned connections:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant View as "QueryEditorView / Toolbar"
    participant VM as "DBViewModel"
    participant Client as "DBClient"
    participant CBridge as "C-ABI (CQianliyan)"
    participant SQLite as "SQLite Engine"

    User->>View: Click Cancel button (or press ⌘ + .)
    View->>VM: cancelQuery()
    VM->>Client: interrupt()

    Note over Client: Acquires lock & calls db_interrupt immediately
    Client->>CBridge: db_interrupt(handle)
    CBridge->>SQLite: sqlite3_interrupt(db)

    Note over SQLite: In-flight query terminates with SQLITE_INTERRUPT
    SQLite-->>Client: Background query returns error.QueryInterrupted
    Client-->>VM: Throws 'Query was cancelled by user'
    VM->>VM: Set tab.isExecuting = false, record notice
    VM-->>User: UI updates state immediately
```

---

## 5. Streaming Pagination Flow (`fetchMore`)

To handle large tables with hundreds of thousands of rows efficiently:

```mermaid
sequenceDiagram
    autonumber
    actor User
    participant Grid as "ResultTableView"
    participant VM as "DBViewModel"
    participant Client as "DBClient"
    participant CBridge as "C-ABI (CQianliyan)"
    participant Cursor as "Zig Active Cursor"

    User->>Grid: Scroll near bottom (or click Load More)
    Grid->>VM: loadMoreRows()
    VM->>Client: fetchMore(limit: 500)
    Client->>CBridge: db_fetch_more(handle, limit, &errPtr)
    CBridge->>Cursor: cursor.fetch(gpa, limit)
    Cursor-->>CBridge: Return next batch of rows
    CBridge-->>Client: Return C batch pointer
    Client->>Client: Decode batch rows
    Client->>CBridge: db_free_result(resPtr)
    Client-->>VM: Append new rows to tab.results
    VM-->>User: Grid appends rows smoothly without reload
```

### Pagination Architecture Details:

1. **Initial Query (`LIMIT 500`)**:
   - `SqliteDriver.query` fetches the first 500 rows and peeks 1 row ahead to detect whether more rows exist (`has_more = true`).
   - If more rows exist, the driver retains the active `Cursor` on the pooled connection.
2. **Scroll Trigger (`loadMoreRows`)**:
   - When the user scrolls near the bottom of `ResultTableView`, `VM.loadMoreRows()` triggers.
   - Calls `DBClient.fetchMore(limit: 500)`.
   - C-ABI executes `db_fetch_more(handle, limit, &err)`.
   - The active cursor pulls the next batch from SQLite into an independent `ArenaAllocator`.
   - `DBClient` decodes the batch and appends the new rows to `tab.results.values`.
   - If `has_more == false`, the cursor is automatically closed and freed by the driver.

---

## 6. Key Memory & Performance Guarantees

| Mechanism                         | Description                                                                                                     | Benefit                                                                                                              |
| :-------------------------------- | :-------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------- |
| **`DbSlice` Vectorized Decoding** | Uses `String(decoding: UnsafeRawBufferPointer(start: ptr, count: size), as: UTF8.self)` with exact byte length. | Skips C `strlen()` scans and avoids double allocation.                                                               |
| **Symmetric Arena Lifecycle**     | Each batch returned by `db_query` / `db_fetch_more` / `db_get_schema` owns its own `ArenaAllocator`.            | Calling `db_free_result` / `db_free_schema` bulk-frees all strings and values in $O(1)$ time with zero memory leaks. |
| **Lock-Free Cancellation**        | `db_interrupt` routes directly to `sqlite3_interrupt` across threads.                                           | Unblocks long-running analytical queries instantly without deadlocking connection locks.                             |
| **Main-Thread Decoupling**        | All C-ABI operations execute inside `Task.detached` off the main thread.                                        | UI stays responsive at 120 FPS; window resizing and editor typing never stutter.                                     |
