# 从 0.16 迁移到 0.17 构建指南

在 Zig 0.17.0 中，构建系统进行了较大调整。本文整理从 0.16 迁移至 0.17 构建系统时的破坏性变更、API 对应关系与调整步骤。

---

## 1. 快速对照表

| 0.16 写法 | 0.17 写法 | 变动原因与说明 |
| :--- | :--- | :--- |
| `if (b.args) \|args\| run_cmd.addArgs(args);` | `run_cmd.addPassthruArgs();` | 配置期不再观察参数，避免改动命令行参数触发配置重新编译 |
| `b.build_root` (`Directory`) | `b.root` (`Path` / `LazyPath`) | 统一路径抽象类型 |
| `b.findProgram(&.{ ... }, .{})` | `b.findProgramLazy(&.{ ... }, .{})` | 延迟到执行期解析路径，避免污染配置缓存 |
| `options.addOptionPath("key", lp)` (目录) | `options.addOptionPathDirectory("key", lp)` | 显式区分单个文件与目录的依赖追踪 |
| `header.include_guard_override = ...` | `header.include_guard = ...` | 字段精简重命名 |
| `lazy_path.basename` | *已移除* | 执行前文件名可能未知，需通过 `LazyPath` 延迟流转 |
| `lazy_path.getDisplayName(...)` | `b.fmt("{f}", .{lazy_path})` | 统一采用标准格式化输出 |
| `b.addFmt(.{ .paths = &.{ "src" } })` | `b.addFmt(.{ .paths = b.pathList(&.{ "src" }) })` | 路径统一为 `LazyPath` 列表 |
| `--override-build-runner` | *已移除* | 架构拆分为 Maker 与 Configurer，外部工具改用 `--listen=-` (BSP) |

---

## 2. 核心代码改造

### 2.1 命令行参数透传（Run Step）

0.16 及早期版本通常在配置期读取 `b.args` 并传递给子进程，这会导致每次修改运行参数时，构建脚本都需要重新执行配置阶段。

0.17 改用 `addPassthruArgs()` 声明占位符，由调度器在执行期动态注入：

```zig
// 0.16 写法
if (b.args) |args| {
    run_cmd.addArgs(args);
}

// 0.17 写法
run_cmd.addPassthruArgs();
```

---

### 2.2 宿主程序查找：`findProgram` vs `findProgramLazy`

在 0.17 中，`build.zig` 函数体属于短命配置进程。直接在配置期查找外部程序会污染配置缓存：

```zig
// 0.16 写法：立即查找
const git_exe = b.findProgram(&.{"git"}, .{}) catch null;

// 0.17 推荐写法：惰性查找（返回 LazyPath，不污染配置缓存）
const git_exe = b.findProgramLazy(&.{"git"}, .{});
run_cmd.step.dependOn(&b.addRunArtifact(exe).step);
run_cmd.addFileArg(git_exe);

// 0.17 仅当配置逻辑自身需要根据程序是否存在做分支时，才使用立即查找：
const git_path = try b.findProgram(&.{"git"}, .{}); // 会将配置标记为缓存污染
```

---

### 2.3 强类型选项（`Step.Options`）路径声明

向模块注入路径常量时，0.17 细化了依赖追踪的语义：

```zig
const options = b.addOptions();

// 1. 注入单个文件（自动追踪文件修改）
options.addOptionPath("config_file", b.path("config.json"));

// 2. 注入目录（自动追踪目录内文件增删）
options.addOptionPathDirectory("assets_dir", b.path("assets/"));

// 3. 不追踪依赖的纯路径字符串
options.addOptionPathUntracked("external_path", b.path("/tmp/test"));
```

---

### 2.4 惰性依赖获取（`dependencyLazy`）

0.17 增加了对惰性依赖的返回错误支持，使调用处可以使用 `try` 语法：

```zig
// 0.17 新增支持
const dep = b.dependencyLazy("optional_pkg", .{
    .target = target,
    .optimize = optimize,
}) catch |err| switch (err) {
    error.LazyDependencyNeeded => return, // 告知调度器触发拉取后重新配置
    else => return err,
};
```

---

### 2.5 根路径引用

`b.build_root` 字段在 0.17 中调整为 `b.root`：

```zig
// 0.16
const root_dir = b.build_root.path;

// 0.17
const root_path = b.path(""); // 推荐：直接获取工程根目录 LazyPath
// 或读取 b.root
```

---

## 3. 运行模型与排错调试

### 3.1 物理双进程模型（Maker 与 Configurer）
0.17 将构建系统拆分为两个独立进程：
- **`Maker`**：常驻调度引擎，以 `-O ReleaseSafe` 编译，负责包管理、依赖拉取、DAG 多线程执行；
- **`Configurer`**：临时子进程，负责执行 `build.zig` 并将计算图序列化为紧凑二进制。

如果需要调试构建系统本身，可设置环境变量：
```bash
export ZIG_DEBUG_CMD=1
```

### 3.2 诊断配置缓存未命中
0.17 的缓存索引采用了二进制格式。如果需要查看某个缓存包的详细信息或诊断未命中原因，可以使用新内置命令：
```bash
zig cache-cat <cache-hash>
```

### 3.3 CI 环境下的纯净性防御
如果在 `build.zig` 中使用了破坏配置确定性的操作（如直接检测未声明的文件或外部命令），在 CI 构建时可以传入：
```bash
zig build --cache-poison=disallowed
```
当构建脚本发生非预期的缓存污染时，该参数会使构建直接中断退出，避免脏配置被提交。

### 3.4 依赖本地调试（`--fork`）
在 0.16 中，若需临时调试第三方依赖包，通常需要修改 `build.zig.zon` 中的 URL 或路径。0.17 引入了命令行分叉参数：
```bash
zig build --fork=/path/to/local/dep_repo
```
构建系统会比对包指纹（fingerprint）自动重定向，无需修改 `build.zig.zon`。
