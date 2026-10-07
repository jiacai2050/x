# 常用构建 API 速查表

本速查表汇总了 Zig 构建系统中最常用、最核心的构建系统 API 及其使用场景。

---

## 1. `std.Build` 根上下文方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| [`b.standardTargetOptions(.{})`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1231) | 解析 `-Dtarget` 参数，返回目标平台解析结果 |
| [`b.standardOptimizeOption(.{})`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1193) | 解析 `-Doptimize` 参数，返回优化模式（Debug / ReleaseFast 等） |
| [`b.option(T, name, desc)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L966) | 声明自定义强类型命令行参数（如 `b.option(bool, "enable-tls", ...)`） |
| [`b.step(name, desc)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1168) | 注册顶层命名构建目标（如 `zig build <name>`） |
| [`b.path(sub_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1538) | 基于当前项目根目录创建只读源码 `LazyPath` |
| [`b.createModule(.{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L722) | 创建工程内部私有的 `*std.Build.Module` |
| [`b.addModule(name, .{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L704) | 创建并注册公共暴露的 `*std.Build.Module`，供下游依赖通过 `dep.module()` 消费 |
| [`b.addExecutable(.{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L579) | 创建可执行文件编译步骤（`*Step.Compile`） |
| [`b.addLibrary(.{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L637) | 创建静态库或动态库编译步骤（`*Step.Compile`） |
| [`b.addTest(.{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L676) | 创建单元测试二进制编译步骤（`*Step.Compile`） |
| [`b.installArtifact(artifact)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1459) | 将编译产物安装到交付目录（`zig-out/bin/` 或 `zig-out/lib/`） |
| [`b.installDirectory(options)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1478) | 将整个目录树（如静态资源 assets）安装到交付目录 |
| [`b.addInstallFile(source, dest)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1497) | 将任意生成物 `LazyPath` 安装到 `zig-out` 前缀相对路径 |
| [`b.addRunArtifact(artifact)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L762) | 创建执行某个编译产物的 `*Step.Run` 任务 |
| [`b.findProgramLazy(opts)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1597) | 推迟外部程序查找到执行期，返回 `LazyPath`，避免污染配置缓存 |
| [`b.dependOnFileContents(path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L2599) | 显式声明配置期依赖该文件的内容哈希，纳入配置缓存凭据 |
| [`b.dependOnDirectoryContents(p)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L2653) | 显式声明配置期依赖目录条目（新增/删除/重命名） |
| [`b.dependency(name, args)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L2018) | 实例化 `build.zig.zon` 中声明的第三方包依赖 |
| [`b.dependencyLazy(name, args)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1962) | 惰性按需实例化依赖，未就绪时返回 `error.LazyDependencyNeeded` 供主进程拉取重试 |
| [`b.addTranslateC(.{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L949) | 创建 C 头文件转译步骤（`*Step.TranslateC`） |
| [`b.addConfigHeader(opts, values)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L827) | 创建基于 CMake 风格的配置头文件渲染步骤（`*Step.ConfigHeader`） |
| [`b.addOptions()`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L555) | 创建强类型的编译期配置常量生成器（`*Step.Options`） |
| [`b.addWriteFiles()`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L923) | 创建动态写出代码或配置文件的任务构建器（`*Step.WriteFile`） |
| [`b.addNamedWriteFiles(name)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L862) | 创建并向外部跨包公开导出的命名 WriteFiles 步骤 |
| [`b.addNamedLazyPath(name, lp)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L879) | 向外部跨包公开暴露命名的生成路径或文件 |
| [`b.addUpdateSourceFiles()`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L937) | 创建将生成物安全回写同步至 `src/` 源码树（Git 仓库）的专用步骤 |
| [`b.systemIntegrationOption(name, .{})`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L2552) | 声明发行版系统包集成选项，支持源码 vendored 与系统动态库模式按需切换 |
| [`b.addObjCopy(source, opts)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1492) | 从 ELF 产物中提取裸机固件镜像（`.bin` / `.hex`）或剥离符号 |
| [`b.addFail(error_msg)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L941) | 创建条件构建下的防御性延迟报错步骤（`*Step.Fail`） |

---

## 2. `std.Build.Step.Run` 核心方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| [`run.addPassthruArgs()`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Run.zig#L593) | 注册参数透传占位符，由 `Maker` 在执行期将命令行 `--` 后的参数传入 |
| [`run.addFileArg(lazy_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Run.zig#L355) | 传入输入文件参数并自动向当前运行步骤建立依赖边 |
| [`run.addOutputFileArg2(name, opts)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Run.zig#L323) | 声明子进程在该参数指定位置生成文件，返回对应的 `LazyPath`（推荐，替代已弃用的 `addOutputFileArg`） |
| [`run.captureStdOut(.{})`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Run.zig#L780) | 捕获子进程的标准输出流，返回对应的 `LazyPath` 供下游作为文件输入 |
| [`run.expectExitCode(code)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Run.zig#L724) | 断言进程退出状态码（默认断言 0） |
| [`run.expectStdOutMatch(pat)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Run.zig#L718) | 断言子进程标准输出匹配特定字符串模式 |
| [`run.setEnvironmentVariable(k, v)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Run.zig#L675) | 为子进程注入指定环境变量 |

---

## 3. `std.Build.Module` 核心方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| [`mod.addImport(name, other_mod)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L306) | 建立模块命名空间映射，使当前模块可 `@import(name)` |
| [`mod.addOptions(name, options)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L321) | 将 `Step.Options` 注入为当前模块直接可导入的强类型常量模块 |
| [`mod.addCMacro(name, value)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L530) | 直接注入 C 预处理宏定义（`-DNAME=VALUE`） |
| [`mod.addCSourceFile(.{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L415) | 挂载单个 C 源文件并指定编译 flags |
| [`mod.addCSourceFiles(.{ ... })`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L391) | 批量挂载 C/C++ 源文件列表 |
| [`mod.addAssemblyFile(lazy_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L442) | 挂载独立的手写汇编源文件（`.s` / `.S`） |
| [`mod.addWin32ResourceFile(rc)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L429) | 编译并嵌入 Windows 平台专属的 `.rc` 资源文件（图标、版本清单） |
| [`mod.linkFramework(name, opts)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L374) | 链接 macOS / iOS 原生系统 Framework（如 Metal、Cocoa） |
| [`mod.addIncludePath(lazy_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L476) | 追加头文件包含路径（`-I`） |
| [`mod.addSystemIncludePath(lazy_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L470) | 追加系统级头文件包含路径（`-isystem`） |
| [`mod.linkLibrary(artifact)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L459) | 链接静态库或动态库，并自动继承其导出的头文件包含路径 |
| [`mod.link_libcpp = true`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Module.zig#L213) | 启用 C++ 混编支持，自动链接内嵌的目标系统 C++ 标准库（如 libc++） |

---

## 4. `std.Build.Step.Compile` (Artifact) 方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| [`art.installHeadersDirectory(src, dest, opts)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L491) | 将静态公共头文件目录安装到该库关联的包含树中 |
| [`art.installConfigHeader(config_h)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L512) | 将动态生成的配置头文件安装到该库的包含树中 |
| [`art.getEmittedIncludeTree()`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L545) | 提取该产物对外导出的完整包含目录树 `LazyPath` |
| [`art.getEmittedBin()`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L696) | 获取该产物编译输出的二进制物理路径 `LazyPath` |
| [`art.getEmittedDocs()`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L723) | 获取该产物编译生成的 HTML API 文档目录树 `LazyPath` |
| [`art.setLinkerScript(lazy_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L571) | 为裸机/内核目标指定自定义链接脚本（`linker.ld`） |
| [`art.setVersionScript(lazy_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L577) | 为 Linux 动态库指定符号导出控制脚本（Version Script） |

---

## 5. `std.Build.Dependency` 依赖方法

| API 签名 | 描述与用途 |
| :--- | :--- |
| [`dep.module(name)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1874) | 获取上游依赖通过 `b.addModule(name, ...)` 导出的模块 |
| [`dep.artifact(name)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1856) | 获取上游依赖通过 `b.addExecutable` / `b.addLibrary` 导出的编译产物 |
| [`dep.path(sub_path)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1892) | 获取指向第三方依赖包目录内部物理文件的 `LazyPath` |
| [`dep.namedWriteFiles(name)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1880) | 获取上游依赖通过 `b.addNamedWriteFiles` 导出的命名文件写入集合 |
| [`dep.namedLazyPath(name)`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1886) | 获取上游依赖通过 `b.addNamedLazyPath` 命名的路径 |

---

## 6. 常用构建控制命令行选项与标准 Step

| 命令 / 参数 | 描述与用途 |
| :--- | :--- |
| `zig build check` | IDE 语法与类型诊断（约定步骤，需在 `build.zig` 中显式注册） |
| `zig build docs` | 生成 HTML 格式的 API 文档（约定步骤，需在 `build.zig` 中显式注册） |
| `zig build --fork=[path]` | 通过包名与指纹将依赖重定向至本地源码目录，免改 `build.zig.zon` |
| `zig build --watch` | 进入会话监听模式，源文件变动时由 `Maker` 进程自动增量重跑 |
| `zig build --listen=-` | 启动官方 Build Server Protocol (BSP) 服务端，与 IDE 通信 |
| `zig build --cache-poison=disallowed` | 强制要求构建逻辑保持纯函数性，发生环境污染时立刻 panic（用于 CI 门禁检查） |
| `zig build --fetch=[needed\|all]` | 控制依赖树拉取的激进程度（默认 `needed` 按需下载） |
| `zig build -fsys=[name]` | 针对指定依赖包启用系统集成（优先链接系统已安装的库） |
| `zig build --system` | Linux 发行版全局系统包模式：禁用网络拉取并启用所有系统集成 |
| `zig cache-cat <digest>` | 反序列化并打印紧凑二进制 Manifest 记录，诊断缓存未命中原因 |
