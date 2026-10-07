# 实战四：跨平台交叉编译与 Makefile/CI 自动化

Zig 内置了跨平台工具链与目标平台 libc 符号支持，使交叉编译与持续集成（CI）配置变得相对简单。

---

## 1. 跨平台交叉编译：无需外部工具链

在任何开发机（无论 macOS、Linux 还是 Windows）上，只需给 `zig build` 传递 `-Dtarget` 参数，即可为不同系统架构编译二进制：

```bash
# 1. 交叉编译至 Windows x86_64
zig build -Dtarget=x86_64-windows

# 2. 交叉编译至 Windows aarch64 (ARM64)
zig build -Dtarget=aarch64-windows

# 3. 交叉编译至 Linux musl (纯静态链接，适合 Docker 极简容器)
zig build -Dtarget=x86_64-linux-musl

# 4. 指定 glibc 最低兼容版本 (避免生产环境报 GLIBC_2.XX not found)
zig build -Dtarget=x86_64-linux-gnu.2.28
```

### 注意事项与使用要点：
1. **指定旧版 glibc 提高兼容性**：
   在 Linux 生产环境中，若开发机 glibc 版本较新，构建出的动态链接二进制部署到旧版系统时容易报 `GLIBC_2.34 not found`。通过在目标三元组中追加版本号（如 `.2.28`），Zig 内置的 libc 符号表会将符号链接到 2.28 版本的导出，从而兼容旧版系统；
2. **构建期工具的 Host vs Target 分工**：
   若构建流程包含“先编译本地命令行工具、再用该工具生成代码”的步骤，该工具需要使用当前主机的配置构建（`b.graph.host`），而不是交叉编译的目标平台（`target`），否则在当前机器上运行该工具会报 `Exec format error`；
3. **异构架构测试执行**：
   交叉编译主要保证产物在目标架构上完成编译与链接。若要在本地开发机上直接运行不同架构的测试程序（例如在 x86_64 macOS 上执行 Linux aarch64 测试），需要通过 `qemu-user` 等仿真器配合执行。

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
          version: <zig-version> # 指定项目目标版本

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
          version: <zig-version> # 指定项目目标版本

      - name: Run Cross-Compilation Matrix
        run: make cross-compile
```

### 配置说明：
1. **本地与 CI 行为保持一致**：开发者在本地执行 `make` 和 `make cross-compile`，与 CI 中的执行命令相同，便于在本地复现和排查问题；
2. **多平台编译验证**：在单个 Linux Runner 上即可完成 Windows、Linux 等多目标架构的交叉编译验证；
3. **CI 纯净构建验证（`--cache-poison=disallowed`）**：在生产级 CI 中，建议在构建参数中追加 `--cache-poison=disallowed`。这样如果脚本在配置期误调用了扫描外部不可控环境变量的 API，CI 会立即报错中断，确保工程构建配置保持纯函数性与确定性。
