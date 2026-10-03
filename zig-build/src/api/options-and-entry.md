# 标准选项与顶层入口：b.standardTargetOptions 与 b.step

编写 `build.zig` 时，通常需要处理命令行传入的构建选项，并注册可执行的构建目标。

---

## 1. 目标平台与优化级别

Zig 提供了开箱即用的标准选项解析方法：

```zig
pub fn build(b: *std.Build) void {
    // 1. 标准目标选项：解析 -Dtarget=...
    const target = b.standardTargetOptions(.{});

    // 2. 标准优化选项：解析 -Doptimize=Debug/ReleaseFast/ReleaseSafe/ReleaseSmall
    const optimize = b.standardOptimizeOption(.{});
}
```

### 1.1 `b.standardTargetOptions`
- **默认行为**：若命令行未指定 `-Dtarget`，默认使用当前主机的 Native 架构与操作系统；
- **交叉编译**：传入 `-Dtarget=x86_64-windows` 或 `-Dtarget=aarch64-linux-musl` 时，Zig 会自动解析并设置目标架构、OS 及 ABI。

### 1.2 `b.standardOptimizeOption`
- **默认模式**：默认为 `Debug` 模式（保留运行时安全检查，不开启重度优化）；
- **四种模式**：
  - `Debug`：编译速度快，包含安全断言，不优化；
  - `ReleaseSafe`：开启中重度优化，同时保留数组越界、整数溢出等运行时安全校验；
  - `ReleaseFast`：注重运行性能优化（相当于 `-O3`），关闭安全校验；
  - `ReleaseSmall`：注重减小产物体积（相当于 `-Os` / `-Oz`）。

---

## 2. 自定义命令行参数：`b.option`

当工程需要特定的构建开关（例如是否启用 TLS、指定服务端口等）时，可以使用 `b.option`：

```zig
pub fn build(b: *std.Build) void {
    // 解析布尔值：zig build -Denable-tls=true
    const enable_tls = b.option(bool, "enable-tls", "Enable TLS support") orelse false;

    // 解析字符串：zig build -Dapi-endpoint=https://api.example.com
    const endpoint = b.option([]const u8, "api-endpoint", "Custom backend API endpoint");

    // 解析枚举类型
    const Backend = enum { sqlite, postgres, mysql };
    const backend = b.option(Backend, "backend", "Database backend driver") orelse .sqlite;
}
```

### 核心特性：
- **强类型解析**：`b.option` 支持 Zig 基础类型（`bool`、`usize`、`[]const u8`）和 `enum`，传入非法值时会在终端提示类型不匹配；
- **帮助信息展示**：通过 `b.option` 声明的选项会自动显示在 `zig build --help` 列表中。

---

## 3. 注册顶层命令入口：`b.step` 与 `b.default_step`

用户执行 `zig build <step_name>` 时，调度引擎根据注册的顶层 Step 确定依赖执行链路：

```zig
pub fn build(b: *std.Build) void {
    // 1. 创建顶层 Step
    const run_step = b.step("run", "Run the application");

    // 2. 创建可执行文件及运行任务
    const exe = b.addExecutable(.{ ... });
    const run_cmd = b.addRunArtifact(exe);

    // 3. 绑定依赖：运行 "zig build run" 时执行 run_cmd
    run_step.dependOn(&run_cmd.step);

    // 4. 默认目标：直接运行 "zig build" 时执行 b.default_step（默认对应 install）
}
```

### 机制说明：
1. **`b.step(name, description)`**：在任务图中注册一个顶层节点（`Step.Id.top_level`），可通过 `zig build <name>` 调用；
2. **`b.default_step`**：当命令行未指定具体目标、仅执行 `zig build` 时触发，默认负责安装所有已声明的产物；
3. **参数透传**：调用 `run_cmd.addArgs(b.args orelse &.{})` 时，可将命令行 `--` 后面的参数透传给被调用的应用程序。

---

## 4. 目标三元组的精度与选项系统局限

### 4.1 细粒度的 Target 表达能力

Zig 的 `standardTargetOptions` 支持较为细致的目标平台定义：
- **指定微架构（CPU Features）**：不仅支持架构名，还支持按微架构层级编译（如 `-Dtarget=x86_64_v3-linux-gnu`）或指定指令集开关（如 `+avx512f`、`-sse4.1`）；
- **指定 glibc 最低兼容版本**：例如传入 `-Dtarget=x86_64-linux-gnu.2.28`，Zig 内置的 libc 符号表会将符号绑定至 2.28 版本的导出，有助于解决高版本开发机编译出的程序在旧版 Linux 服务器上报 `GLIBC_2.34 not found` 的兼容性问题。

### 4.2 局限与不足

1. **扁平的选项命名空间**：
   通过 `b.option` 定义的参数均在全局作用域中解析。若第三方库也声明了同名参数（例如 `-Denable-tls`），命令行传入的值会同时传给两者，目前尚无原生的选项命名空间隔离机制；
2. **缺少对复合类型选项的支持**：
   `b.option` 主要支持基础标量（`bool`、`usize`、`[]const u8`）和简单 `enum`，不支持从命令行直接反序列化数组或嵌套结构体，传递复杂配置时通常需要手动分割字符串。
