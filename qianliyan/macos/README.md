# Qianliyan macOS Client

The native macOS desktop frontend for Qianliyan, built with **SwiftUI** and **AppKit**, communicating with the **Zig Core Engine** via an in-process C-ABI (`CQianliyan`).

---

## Prerequisites

- macOS 14.0+ (Sonoma or later)
- Xcode 15+ / Swift 5.9+ Command Line Tools
- Zig 0.17.0+ (for building the core engine)

---

## Building and Running

### 1. Build the Zig Core Library
The macOS app statically links against `libqianliyan.a`. Build it from the repository root:

```bash
# In repository root:
zig build
```

This generates `zig-out/lib/libqianliyan.a` and exposes C headers at `include/dbcore.h`.

### 2. Build via Swift Package Manager (CLI)

```bash
cd macos
swift build
swift run
```

### 3. Open in Xcode

You can open `Package.swift` directly in Xcode:

```bash
cd macos
open Package.swift
```

Select the `Qianliyan` scheme and press `⌘ + R` to build and run.

---

## Architecture & Design Docs

For detailed data flow diagrams, thread decoupling, and C-ABI bridge specifications, see:
- [macOS Architecture & Data Flow](../docs/macos-architecture.md)
