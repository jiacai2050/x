# 实战四：跨平台交叉编译与 Makefile/CI 自动化

Zig 内置了跨平台工具链与目标平台 libc 符号支持，使交叉编译与持续集成（CI）配置变得相对简单。

---

## 1. 跨平台交叉编译：无需外部工具链

在任何开发机（无论 macOS、Linux 还是 Windows）上，只需给 `zig build` 传递 `-Dtarget` 参数，即可为不同系统架构编译二进制：

```bash
# Cross-compile for Windows x86_64
zig build -Dtarget=x86_64-windows

# Cross-compile for Windows aarch64 (ARM64)
zig build -Dtarget=aarch64-windows

# Cross-compile for Linux musl (fully statically linked)
zig build -Dtarget=x86_64-linux-musl
```

由于 Zig 内部集成了目标平台的 libc 符号与 Clang/LLD，上述命令即使包含 C 源码，通常也无需在宿主机安装 MinGW 或交叉 GCC 工具链。

---

## 2. 工程化工作流：结合 Makefile 统一常用指令

在工程实践中，推荐在根目录编写一个简洁的 `Makefile`，为开发者与 CI 提供一致的命令入口：

```makefile
ZIG ?= zig

.DEFAULT_GOAL := all

.PHONY: all build test fmt fmt-check cross-compile cross-x86_64-windows cross-aarch64-windows clean

all: build test

build:
	$(ZIG) build

test:
	cd test && $(ZIG) build run

fmt:
	$(ZIG) fmt . test/

fmt-check:
	$(ZIG) fmt --check . test/

cross-x86_64-windows:
	$(ZIG) build -Dtarget=x86_64-windows

cross-aarch64-windows:
	$(ZIG) build -Dtarget=aarch64-windows

cross-compile: cross-x86_64-windows cross-aarch64-windows

clean:
	rm -rf zig-out .zig-cache test/zig-out test/.zig-cache
```

---

## 3. GitHub Actions CI 流水线实践

结合 `Makefile`，GitHub Actions 工作流配置示例如下：

```yaml
name: CI

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]

jobs:
  native-build-test:
    name: Native Build & Test (${{ matrix.name }})
    runs-on: ${{ matrix.os }}
    defaults:
      run:
        shell: bash
    strategy:
      fail-fast: false
      matrix:
        include:
          - os: ubuntu-latest
            name: Linux x86_64
          - os: macos-latest
            name: macOS Apple Silicon
          - os: windows-latest
            name: Windows x86_64

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Zig
        uses: mlugg/setup-zig@v2
        with:
          version: 0.16.0

      - name: Install Make (Windows)
        if: runner.os == 'Windows'
        run: choco install make --no-progress

      - name: Build & Test
        run: make

  cross-compile:
    name: Cross-Compilation Checks
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Setup Zig
        uses: mlugg/setup-zig@v2
        with:
          version: 0.16.0

      - name: Run Cross-Compilation Matrix
        run: make cross-compile
```

### 配置说明：
1. **本地与 CI 行为保持一致**：开发者在本地执行 `make` 和 `make cross-compile`，与 CI 中的执行命令相同，便于在本地复现和排查问题；
2. **多平台编译验证**：在单个 Linux Runner 上即可完成 Windows、Linux 等多目标架构的交叉编译验证。
