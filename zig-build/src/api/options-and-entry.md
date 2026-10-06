# 标准选项与顶层入口：b.standardTargetOptions 与 b.step

编写 `build.zig` 时，通常需要处理命令行传入的构建选项，并注册可执行的构建目标。

---

## 1. 目标平台与优化级别

Zig 提供了开箱即用的标准选项解析方法：

```zig
pub fn build(b: *std.Build) void {
    // 1. 标准目标平台解析：解析 -Dtarget=...
    const target = b.standardTargetOptions(.{});

    // 2. 标准优化级别解析：解析 -Doptimize=...
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
    // 解析布尔值开关：zig build -Denable-tls=true
    const enable_tls = b.option(bool, "enable-tls", "Enable TLS support") orelse false;

    // 解析字符串选项：zig build -Dapi-endpoint=https://api.example.com
    const endpoint = b.option([]const u8, "api-endpoint", "Custom backend API endpoint");

    // 解析枚举选项
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
    // 1. 创建顶层命令入口
    const run_step = b.step("run", "Run the application");

    // 2. 创建可执行文件与运行步骤
    const exe = b.addExecutable(.{ ... });
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.addPassthruArgs();

    // 3. 绑定依赖："zig build run" 会触发 run_cmd
    run_step.dependOn(&run_cmd.step);

    // 4. 默认目标：直接执行 "zig build" 触发 b.default_step（默认执行 install）
}
```

### 机制说明：
1. **`b.step(name, description)`**：在任务图中注册一个顶层节点（`Step.Tag.top_level`），可通过 `zig build <name>` 调用；
2. **`b.default_step`**：当命令行未指定具体目标、仅执行 `zig build` 时触发，默认负责安装所有已声明的产物；
3. **参数透传（`addPassthruArgs`）**：调用 `run_cmd.addPassthruArgs()` 在构建图中记录占位符，由 `Maker` 调度器在执行期动态将命令行 `--` 后面的参数透传给应用程序，避免在配置期直接读取参数破坏配置缓存；
4. **平台或条件不支持时的延迟报错（`b.addFail`）**：若某个任务在特定平台上不受支持，避免在 `build()` 配置期直接执行 `@panic`（否则无关任务甚至 `zig build --help` 也会中断退出）。可通过 [lib/std/Build.zig:L941](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L941) 的 `b.addFail` 注册延迟报错步骤：
   ```zig
   if (target.result.os.tag == .windows) {
       // 仅当用户显式请求构建该任务时才报错
       const fail_step = b.addFail("Windows platform is not currently supported for this target");
       run_step.dependOn(&fail_step.step);
   }
   ```

### 常用构建控制参数：
- `--fork=[path]` 或 `--fork [path]`：在命令行将依赖树中的指定项目透明重定向到本地开发目录（支持多次指定），无需修改任何 `build.zig.zon`，便于第三方依赖本地修补与多库联合调试；
- `--cache-poison=disallowed`：若构建脚本调用了破坏配置纯函数性的 API（如 `b.findProgram`），直接触发 panic 中断，适合用于确保 CI 环境构建配置的纯净性；
- `--cache-poison=pure`（默认值）：若发生污染则安全降级，本次构建不缓存配置图；
- `--listen=-`：启动官方 Build Server Protocol 服务端，与 IDE/语言服务器进行基于 JSON-RPC 的双向通信；
- `--watch`：进入会话模式，主控进程 `Maker` 持续驻留，监听源码与配置文件变更并自动执行增量重跑。

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
