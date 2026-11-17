# Qianliyan (千里眼)

A lightweight, blazing-fast native database client for macOS, powered by a **Zig** core engine and **SwiftUI**.

---

## Features

- **Native & Lightweight**: Pure SwiftUI on macOS. Sub-second startup, low memory usage, native dark mode, and zero Electron bloat. [Download .dmg](https://github.com/jiacai2050/x/releases?q=qianliyan).
- **Multi-Tab SQL Editor**: Multiple query tabs with execution history and thread-safe cancellation (`⌘.`).
- **Schema & Index Inspector**: Hierarchical browser for tables, columns, primary keys, indexes, and raw `CREATE TABLE` DDL.
- **Data Grid & Export**: Fast two-way scrollable table with adaptive column widths, cell/row copying, and CSV/JSON export.
- **WebAssembly Version**: 100% client-side Web viewer powered directly by Qianliyan's **Zig Core** in WebAssembly. Zero server uploads, runs privately in your browser. [Try Online](https://jiacai2050.github.io/x/qianliyan/web/).
- **Recent Databases**: Quick-open dashboard with custom aliases, Finder integration, and connection import/export.

---

## Architecture

Qianliyan decouples presentation from core database execution:

```
macOS GUI (SwiftUI) ──[C-ABI]─┐
                              ├──> Zig Core (stdgo.database.sql) ────> SQLite Engine
Web Browser (HTML/JS) ─[Wasm]─┘
```

- **Zig Core**: Manages connection pooling, query execution, type parsing, and query interruption with zero memory leaks.
- **Dual Presentation**: Native macOS SwiftUI desktop application + WebAssembly in-browser viewer, powered by the exact same Zig core codebase.

---

## Quick Start

### Prerequisites

- macOS 14.0+
- Zig 0.17.0+
- Swift 5.9+ / Xcode Command Line Tools

### Build & Run

```bash
make test    # Run core Zig tests
make macos   # Build macOS application
make run     # Launch GUI application
make web     # Serve Web client locally (http://localhost:8000)
make dist    # Package release DMG (dist/Qianliyan.dmg)
```

> **Gatekeeper Note**: If macOS blocks the downloaded DMG or prevents dragging to Applications, remove the quarantine attribute:
>
> ```bash
> xattr -d com.apple.quarantine ~/Downloads/Qianliyan.dmg
> ```

---

## License

MIT License.
