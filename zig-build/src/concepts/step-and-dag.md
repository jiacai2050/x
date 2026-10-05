# 计算图抽象：Step 与有向无环图 (DAG)

在 Zig 构建系统中，构建任务被组织为一张有向无环图（DAG），图中的每个任务节点对应一个 `std.Build.Step`。

---

## 1. Step 核心抽象与结构

查看标准库源码 [lib/std/Build/Step.zig:L8-L38](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step.zig#L8-L38)，`Step` 核心结构体定义如下：

```zig
// 摘自 lib/std/Build/Step.zig:L8-L38
pub const Step = struct {
    tag: Configuration.Step.Tag,
    name: []const u8,
    owner: *Build,

    dependencies: std.ArrayList(*Step),

    /// 声明任务内存占用上限（0 表示无限制）
    max_rss: u64,

    debug_stack_trace: std.debug.StackTrace,
};
```

### 核心设计与属性：
1. **无函数指针设计（序列化友好）**：
   由于 `build.zig` 运行在短命的 `configurer` 子进程中，所有节点必须序列化为二进制流跨进程传送给 `Maker` 调度器，因此 `Step` 节点完全由结构化数据组成，不包含任何内存函数指针；
2. **基于 Tag 的类型矩阵（`Configuration.Step.Tag`）**：
   所有节点类型由确定性的 `tag` 枚举标识，`Maker` 进程接收到配置流后，通过内部的 `Extended` union 统一分发执行；
3. **内存上限声明（`max_rss`）**：
   `max_rss` 字段允许为高内存开销任务（如巨型测试套件或重度代码生成）声明内存占用上限。`Maker` 调度器会根据系统总内存动态限制并发数，避免多任务并发时触发系统 OOM Crash；
4. **依赖边列表（`dependencies`）**：
   记录当前节点依赖的前置任务集合。

---

## 2. 常见内置 Step 类型

标准库内置了 16 种特化的 Step 实现：

| Step 类型 (Tag) | 对应结构体 | 职责与常见场景 |
| :--- | :--- | :--- |
| `top_level` | `Step.TopLevel` | 命令行调用的顶层入口（如 `b.step("test", ...)` 或默认 `install`） |
| `compile` | `Step.Compile` | 编译与链接任务，生成可执行文件、静态库或动态库 |
| `install_artifact` | `Step.InstallArtifact` | 将编译产物从缓存目录安装到输出目录（`zig-out/`） |
| `install_file` | `Step.InstallFile` | 将任意 `LazyPath` 安装到输出目录（如 `zig-out/bin/` 或 `zig-out/` 根目录） |
| `install_dir` | `Step.InstallDir` | 将整个目录树安装到输出目录 |
| `run` | `Step.Run` | 运行编译产物或外部命令（运行测试、执行 Host 辅助构建工具） |
| `write_file` | `Step.WriteFile` | 在缓存目录动态创建并写入文件或目录 |
| `config_header` | `Step.ConfigHeader` | 解析 `.h.in` 模板并渲染生成配置头文件 |
| `translate_c` | `Step.TranslateC` | 调用编译器将 C 头文件转译为 Zig AST 与 Module |
| `check_file` | `Step.CheckFile` | 校验生成产物是否包含或匹配指定字符串特征 |
| `obj_copy` | `Step.ObjCopy` | 从编译产物中提取节区、转换二进制格式（如生成 `.hex` / `.bin`） |

---

## 3. Step 依赖拓扑图示例

典型的项目构建图拓扑如下：

```mermaid
flowchart TD
    subgraph S_Top ["顶层命令行入口 (Top Level Steps)"]
        TL_Install["b.default_step (默认 zig build)"]
        TL_Test["b.step('test', ...) (zig build test)"]
        TL_Pack["b.step('pack', ...) (zig build pack)"]
    end

    subgraph S_Install ["产物安装管线 (Install Steps)"]
        S_Art["Step.InstallArtifact<br/>安装到 zig-out/bin/"]
        S_InstFile["Step.InstallFile<br/>安装到 zig-out/bundle.tar.gz"]
    end

    subgraph S_Compile ["核心编译与链接 (Step.Compile)"]
        S_CompExe["主程序二进制构建 (addExecutable)"]
        S_CompTest["单元测试二进制构建 (addTest)"]
        S_ToolExe["Host 辅助打包工具 (addExecutable)"]
    end

    subgraph S_Prebuild ["前置代码与配置生成"]
        S_Cfg["Step.ConfigHeader<br/>生成 config.h"]
        S_Gen["Step.WriteFile<br/>动态生成 version.zig"]
    end

    subgraph S_Run ["执行管线 (Step.Run)"]
        S_RunTest["执行测试进程并校验输出"]
        S_RunPack["执行 pack_tool 打包产物"]
    end

    TL_Install -- "dependOn" --> S_Art
    S_Art -- "dependOn" --> S_CompExe
    S_CompExe -- "dependOn" --> S_Cfg
    S_CompExe -- "dependOn" --> S_Gen

    TL_Test -- "dependOn" --> S_RunTest
    S_RunTest -- "dependOn" --> S_CompTest
    S_CompTest -- "dependOn" --> S_Cfg

    TL_Pack -- "dependOn" --> S_InstFile
    S_InstFile -- "dependOn" --> S_RunPack
    S_RunPack -- "dependOn" --> S_ToolExe
    S_RunPack -- "dependOn" --> S_CompExe

    style S_Top stroke:#ff9900,stroke-width:2px;
    style S_Install stroke:#495057,stroke-width:2px;
    style S_Compile stroke:#0066cc,stroke-width:2px;
    style S_Prebuild stroke:#009900,stroke-width:2px;
    style S_Run stroke:#ffc107,stroke-width:2px;
    style TL_Install stroke:#ff9900,stroke-width:2px;
    style TL_Test stroke:#ff9900,stroke-width:2px;
    style TL_Pack stroke:#ff9900,stroke-width:2px;
    style S_Art stroke:#495057,stroke-width:2px;
    style S_InstFile stroke:#495057,stroke-width:2px;
    style S_CompExe stroke:#0066cc,stroke-width:2px;
    style S_CompTest stroke:#0066cc,stroke-width:2px;
    style S_ToolExe stroke:#0066cc,stroke-width:2px;
    style S_Cfg stroke:#009900,stroke-width:2px;
    style S_Gen stroke:#009900,stroke-width:2px;
    style S_RunTest stroke:#ffc107,stroke-width:2px;
    style S_RunPack stroke:#ffc107,stroke-width:2px;
```

### 建立依赖：`dependOn`

在代码中通过 `step_a.dependOn(step_b)` 指定先后顺序：

```zig
// 1. 创建顶层命令入口："zig build test"
const test_step = b.step("test", "Run library unit tests");

// 2. 创建单元测试编译步骤
const unit_tests = b.addTest(.{
    .root_module = my_module,
});

// 3. 创建测试执行步骤
const run_unit_tests = b.addRunArtifact(unit_tests);

// 4. 建立依赖边：test_step 依赖 run_unit_tests
test_step.dependOn(&run_unit_tests.step);
```

执行 `zig build test` 时，`Maker` 调度器定位到 `test_step`，沿依赖边发现其需要 `run_unit_tests`，而 `run_unit_tests` 依赖 `unit_tests` 编译出的测试二进制，从而按拓扑顺序调度执行。

---

## 4. 自定义构建任务：Host Tool + Run Step 模式

在需要执行自定义构建逻辑（如文件打包、资源编译、协议代码生成等）时，标准的最佳实践是编写独立的辅助工具代码（如 `tools/pack.zig`），并结合 `Step.Run` 接入计算图。

### 为什么采用 Host Tool 模式？
在 Maker 与 Configurer 物理双进程架构下：
- `build.zig` 仅在临时配置进程中运行，负责纯声明式地构造依赖图拓扑；
- 若允许在配置脚本中内联执行任务逻辑，主控调度器 `Maker` 就必须在执行期重新把构建脚本编译为动态库或以 Debug 模式加载，破坏调度性能；
- 主控调度器 `Maker` 自身以 `-O ReleaseSafe` 编译，调度独立的 Host 工具能够兼顾构建纯净性与任务执行效率。

### 标准实现范式
实现独立的 Host 工具并通过 `b.addRunArtifact` 接入构建图：

```zig
// 1. 编译专用于宿主机的辅助构建工具
const pack_tool = b.addExecutable(.{
    .name = "pack_tool",
    .root_module = b.createModule(.{
        .root_source_file = b.path("tools/pack.zig"),
        .target = b.graph.host, // 针对宿主机环境编译
        .optimize = .ReleaseSafe,
    }),
});

// 2. 声明运行步骤，连接输入输出依赖
const pack_cmd = b.addRunArtifact(pack_tool);
pack_cmd.addFileArg(exe.getEmittedBin()); // 输入 LazyPath
const tar_output = pack_cmd.addOutputFileArg("bundle.tar.gz"); // 输出 LazyPath

// 3. 将输出文件安装到目标交付目录
const install_tar = b.addInstallFile(tar_output, "bundle.tar.gz");
top_pack_step.dependOn(&install_tar.step);
```

### 这种模式的优势：
1. **完全解耦与纯净性**：`build.zig` 保持只声明依赖图，不混杂具体的任务实现代码，天然保持纯函数性，有利于配置缓存命中；
2. **更高性能**：辅助工具可独立以 `-O ReleaseSafe` 甚至 `-O ReleaseFast` 编译，在处理大型归档或复杂代码生成时显著快于内联在 `build.zig` 里的 Debug 模式执行；
3. **独立可测试**：辅助工具本身是一个标准的可执行程序，具备清晰的命令行参数与标准输入输出，可以单独编写单元测试与调试。
