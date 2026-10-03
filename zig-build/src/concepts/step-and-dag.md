# 计算图抽象：Step 与有向无环图 (DAG)

在 Zig 构建系统中，构建任务被组织为一张有向无环图（DAG），图中的每个任务节点对应一个 `std.Build.Step`。

---

## 1. 什么是 Step？

在 Zig 源码中，[lib/std/Build/Step.zig](https://codeberg.org/ziglang/zig/src/tag/0.16.0/lib/std/Build/Step.zig) 定义了任务节点的通用结构：

```zig
// lib/std/Build/Step.zig
pub const Step = struct {
    pub const Id = enum {
        top_level,
        compile,
        install_artifact,
        install_file,
        install_dir,
        run,
        check_file,
        write_file,
        config_header,
        translate_c,
        options,
        custom,
    };

    pub const MakeFn = *const fn (step: *Step, options: MakeOptions) anyerror!void;

    id: Id,
    name: []const u8,
    owner: *Build,
    makeFn: MakeFn,

    dependencies: std.array_list.Managed(*Step),
    dependants: ArrayList(*Step),
    // ...
};
```

### 核心属性：
1. **任务执行函数（`makeFn`）**：
   函数签名为 `*const fn (step: *Step, options: MakeOptions) anyerror!void`。无论是调用编译器、运行测试、写文件还是转译 C 头文件，只要实现该签名，即可作为构建节点接入任务图。
2. **依赖关系列表（`dependencies` 与 `dependants`）**：
   记录当前节点依赖的前置任务（`dependencies`），以及依赖当前节点的后续任务（`dependants`）。
3. **所属上下文（`owner`）**：
   指向创建该 Step 的 `*std.Build` 实例。

---

## 2. 常见内置 Step 类型

Zig 标准库内置了多种特化的 Step 实现：

| Step 类型 (Id) | 对应结构体 | 职责与常见场景 |
| :--- | :--- | :--- |
| `top_level` | `Step` | 命令行调用的顶层入口（如 `b.step("test", ...)` 或 `b.default_step`） |
| `compile` | `Step.Compile` | 编译与链接任务，生成可执行文件、静态库或动态库 |
| `install_artifact` | `Step.InstallArtifact` | 将产物从缓存目录安装到输出目录（`zig-out/`） |
| `run` | `Step.Run` | 运行生成的可执行文件或外部命令（常用于执行单元测试） |
| `write_file` | `Step.WriteFile` | 在缓存目录动态创建并写入文件 |
| `config_header` | `Step.ConfigHeader` | 解析 `.h.in` 模板并渲染生成配置头文件 |
| `translate_c` | `Step.TranslateC` | 调用编译器将 C 头文件转译为 Zig AST 与 Module |

---

## 3. Step 依赖拓扑图示例

典型的 Zig 项目构建图结构如下：

```mermaid
graph TD
    subgraph S_Top ["顶层命令行入口 (Top Level Steps)"]
        TL_Install["b.default_step (默认 zig build)"]
        TL_Test["b.step('test', ...) (zig build test)"]
    end

    subgraph S_Install ["产物安装管线"]
        S_Art["Step: InstallArtifact<br/>安装到 zig-out/bin/"]
    end

    subgraph S_Compile ["核心编译与链接"]
        S_CompExe["Step.Compile (addExecutable)<br/>主程序二进制构建"]
        S_CompTest["Step.Compile (addTest)<br/>单元测试二进制构建"]
    end

    subgraph S_Prebuild ["前置代码与配置生成"]
        S_Cfg["Step.ConfigHeader<br/>生成 config.h"]
        S_Gen["Step.WriteFile<br/>动态生成 version.zig"]
    end

    subgraph S_Run ["执行管线"]
        S_RunTest["Step.Run<br/>执行测试进程并校验输出"]
    end

    TL_Install -- "dependOn" --> S_Art
    S_Art -- "dependOn" --> S_CompExe
    S_CompExe -- "dependOn" --> S_Cfg
    S_CompExe -- "dependOn" --> S_Gen

    TL_Test -- "dependOn" --> S_RunTest
    S_RunTest -- "dependOn" --> S_CompTest
    S_CompTest -- "dependOn" --> S_Cfg

    classDef default stroke:#495057;
    style S_Top stroke:#ff9900,stroke-width:2px;
    style S_Install stroke:#495057,stroke-width:2px;
    style S_Compile stroke:#0066cc,stroke-width:2px;
    style S_Prebuild stroke:#009900,stroke-width:2px;
    style S_Run stroke:#ffc107,stroke-width:2px;
    style TL_Install stroke:#ff9900,stroke-width:2px;
    style TL_Test stroke:#ff9900,stroke-width:2px;
    style S_Art stroke:#495057,stroke-width:2px;
    style S_CompExe stroke:#0066cc,stroke-width:2px;
    style S_CompTest stroke:#0066cc,stroke-width:2px;
    style S_Cfg stroke:#009900,stroke-width:2px;
    style S_Gen stroke:#009900,stroke-width:2px;
    style S_RunTest stroke:#ffc107,stroke-width:2px;
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

执行 `zig build test` 时，调度器定位到 `test_step`，沿依赖边发现其需要 `run_unit_tests`，而 `run_unit_tests` 依赖 `unit_tests` 产出二进制，从而按拓扑序依次执行。

---

## 4. 多态设计与现实局限

### 4.1 基于 `@fieldParentPtr` 的多态实现

Zig 语言没有类继承和虚函数表，但 `Step` 通过函数指针与字段指针推导实现了组合式多态：
- **统一函数签名**：所有内置与第三方 Step 均向调度器暴露相同的签名：
  `fn make(step: *Step, options: MakeOptions) anyerror!void`；
- **反向指针推导**：在 `make` 函数内部，通过内建函数 `@fieldParentPtr`，可以从通用的 `*Step` 指针还原出具体的宿主结构体指针（如 `*Step.Compile` 或自定义的 `*PackReleaseStep`）；
- **统一调度**：自定义任务与内置的核心编译步骤在调度机制上完全一致，同样由调度器管理并发与缓存判定。

### 4.2 局限与不足

1. **循环依赖排查**：
   若依赖配置错误导致 `dependOn` 出现环路（Cycle），调度器虽能检测到有向环，但报错信息主要展示内部节点 ID，在大型工程中定位具体成环代码仍需逐层梳理；
2. **多产物分发较为繁琐**：
   `Step` 的抽象主要面向单一主产物模型（如单个编译二进制或一个输出目录）。当一个自定义代码生成步骤同时产出彼此独立的多个源文件、头文件和资源时，需要为每个文件单独维护一个 `GeneratedFile` 实例，向下游不同模块分发时存在较多胶水代码。
