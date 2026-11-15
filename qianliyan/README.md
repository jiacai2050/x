# Qianliyan (千里眼)

A lightweight, blazing-fast native database client for macOS, powered by a **Zig** core engine and **SwiftUI**.

---

## Features

- **Native & Lightweight**: Pure SwiftUI on macOS. Sub-second startup, low memory usage, native dark mode, and zero Electron bloat.
- **Multi-Tab SQL Editor**: Multiple query tabs with execution history and thread-safe cancellation (`⌘.`).
- **Schema & Index Inspector**: Hierarchical browser for tables, columns, primary keys, indexes, and raw `CREATE TABLE` DDL.
- **Data Grid & Export**: Fast two-way scrollable table with adaptive column widths, cell/row copying, and CSV/JSON export.
- **Recent Databases**: Quick-open dashboard with custom aliases, Finder integration, and connection import/export.

---

## Architecture

Qianliyan decouples platform-native presentation from core database execution:

```
macOS GUI (SwiftUI) ──[C-ABI]──> Zig Core (stdgo.database.sql) ────> Database Drivers (SQLite, ...)
```

- **Zig Core**: Manages connection pooling, query execution, type parsing, and out-of-band query interruption with zero memory leaks.
- **SwiftUI Host**: Native macOS presentation, async concurrency, and responsive UI.

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
make dist    # Package release DMG (dist/Qianliyan.dmg)
```

> **Gatekeeper Note**: If macOS blocks the downloaded DMG or prevents dragging to Applications, remove the quarantine attribute:
> ```bash
> xattr -d com.apple.quarantine ~/Downloads/Qianliyan.dmg
> ```

---

## License

MIT License.
