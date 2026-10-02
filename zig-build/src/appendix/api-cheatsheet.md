# 常用构建 API 速查表

本速查表汇总了 Zig 0.16.0 中最常用、最核心的构建系统 API 及其使用场景。

---

## 1. `std.Build` 根上下文方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| `b.standardTargetOptions(.{})` | 解析 `-Dtarget` 参数，返回目标平台解析结果 |
| `b.standardOptimizeOption(.{})` | 解析 `-Doptimize` 参数，返回优化模式（Debug / ReleaseFast 等） |
| `b.option(T, name, desc)` | 声明自定义强类型命令行参数（如 `b.option(bool, "enable-tls", ...)`） |
| `b.step(name, desc)` | 注册顶层命名构建目标（如 `zig build <name>`） |
| `b.path(sub_path)` | 基于当前项目根目录创建只读源码 `LazyPath` |
| `b.createModule(.{ ... })` | 创建工程内部私有的 `*std.Build.Module` |
| `b.addModule(name, .{ ... })` | 创建并注册公共暴露的 `*std.Build.Module`，供下游依赖通过 `dep.module()` 消费 |
| `b.addExecutable(.{ ... })` | 创建可执行文件编译步骤（`*Step.Compile`） |
| `b.addLibrary(.{ ... })` | 创建静态库或动态库编译步骤（`*Step.Compile`） |
| `b.addTest(.{ ... })` | 创建单元测试二进制编译步骤（`*Step.Compile`） |
| `b.installArtifact(artifact)` | 将编译产物安装到交付目录（`zig-out/bin/` 或 `zig-out/lib/`） |
| `b.addRunArtifact(artifact)` | 创建执行某个编译产物的 `*Step.Run` 任务 |
| `b.dependency(name, args)` | 实例化 `build.zig.zon` 中声明的第三方包依赖 |
| `b.addTranslateC(.{ ... })` | 创建 C 头文件转译步骤（`*Step.TranslateC`） |
| `b.addConfigHeader(opts, values)` | 创建基于 CMake 风格的配置头文件渲染步骤（`*Step.ConfigHeader`） |
| `b.addWriteFiles()` | 创建动态写出代码或配置文件的任务构建器（`*Step.WriteFile`） |

---

## 2. `std.Build.Module` 核心方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| `mod.addImport(name, other_mod)` | 建立模块命名空间映射，使当前模块可 `@import(name)` |
| `mod.addCSourceFile(.{ ... })` | 挂载单个 C 源文件并指定编译 flags |
| `mod.addCSourceFiles(.{ ... })` | 批量挂载 C/C++ 源文件列表 |
| `mod.addIncludePath(lazy_path)` | 追加头文件包含路径（`-I`） |
| `mod.addSystemIncludePath(lazy_path)`| 追加系统级头文件包含路径（`-isystem`） |
| `mod.linkLibrary(artifact)` | 链接静态库或动态库，并自动继承其导出的头文件包含路径 |

---

## 3. `std.Build.Step.Compile` (Artifact) 方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| `art.installHeadersDirectory(src, dest, opts)` | 将静态公共头文件目录安装到该库关联的包含树中 |
| `art.installConfigHeader(config_h)` | 将动态生成的配置头文件安装到该库的包含树中 |
| `art.getEmittedIncludeTree()` | 提取该产物对外导出的完整包含目录树 `LazyPath` |
| `art.getEmittedBin()` | 获取该产物编译输出的二进制物理路径 `LazyPath` |

---

## 4. `std.Build.Dependency` 依赖方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| `dep.module(name)` | 获取上游依赖通过 `b.addModule(name, ...)` 导出的模块 |
| `dep.artifact(name)` | 获取上游依赖通过 `b.addExecutable` / `b.addLibrary` 导出的编译产物 |
| `dep.path(sub_path)` | 获取指向第三方依赖包目录内部物理文件的 `LazyPath` |
| `dep.namedLazyPath(name)` | 获取上游依赖通过 `b.addNamedLazyPath` 命名的路径 |
