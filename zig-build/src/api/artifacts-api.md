# 产物构建与测试：Executable、Library、Test 与 ObjCopy

在 Zig 构建系统中，生成最终二进制产物（可执行文件、静态库/动态库、测试程序）的任务由 `Step.Compile` 负责，并通过 `Step.Run`、`Step.InstallArtifact` 以及 `Step.ObjCopy` 进行执行验证、安装交付与固件提取。

> 💡 **配套可运行示例**
> 关于标准应用程序产物与单元测试构建的完整代码工程，可参考 GitHub 示例：[`examples/01-zig-app`](https://github.com/jiacai2050/x/tree/main/zig-build/examples/01-zig-app)，以及后续实战章节 [实战一：标准 Zig CLI 应用与单元测试](../practices/practice-zig-app.md)。

---

## 1. 构建可执行程序：`b.addExecutable`

```zig
const exe = b.addExecutable(.{
    .name = "my_app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }),
});

// 将产物安装到 zig-out/bin/ 目录下
b.installArtifact(exe);

// 注册运行命令并支持命令行参数透传
const run_cmd = b.addRunArtifact(exe);
run_cmd.step.dependOn(b.getInstallStep());
run_cmd.addPassthruArgs(); // 记录 .passthru 占位符，执行期由调度器动态注入

const run_step = b.step("run", "Run the application");
run_step.dependOn(&run_cmd.step);
```

### 1.1 关键配置：
- **`root_module`**：挂载主程序的编译上下文与依赖；
- **产物安装**：通过 `b.installArtifact(exe)` 将生成的可执行文件输出到 `zig-out/bin/my_app`（在 Windows 平台会自动追加 `.exe` 后缀）；
- **参数透传（`addPassthruArgs`）**：通过 `addPassthruArgs()` 在计算图中注册占位符，由调度器在执行期动态注入命令行参数，避免在配置期读取参数导致配置缓存失效。

### 1.2 裸机固件与格式转换：`b.addObjCopy`

在嵌入式开发、操作系统内核或微控制器（MCU）固件构建中，编译器输出的标准可执行文件为 ELF 格式，包含头部信息、段符号表与重定位表，无法直接烧录到 Flash 中执行。

通过 [lib/std/Build.zig:L1492-L1505](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1492-L1505) 的 `addObjCopy` 步骤，可以从 ELF 编译产物中直接剥离出纯平铺二进制（`.bin`）或 Intel 十六进制镜像（`.hex`）：

```zig
// 1. 编译目标为嵌入式无操作系统裸机（如 ARM Cortex-M4）
const kernel_elf = b.addExecutable(.{
    .name = "kernel.elf",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/kernel.zig"),
        .target = b.resolveTargetQuery(.{
            .cpu_arch = .thumb,
            .os_tag = .freestanding,
            .abi = .none,
        }),
        .optimize = .ReleaseSmall,
    }),
});

// 2. 从 ELF 产物中剥离并提取纯二进制 .bin 固件
const bin_step = b.addObjCopy(kernel_elf.getEmittedBin(), .{
    .format = .bin,
});

// 3. 安装裸固件至交付目录：zig-out/firmware.bin
const install_bin = b.addInstallRaw(bin_step.getOutput(), "firmware.bin", .{});
b.getInstallStep().dependOn(&install_bin.step);
```

### 1.3 链接脚本与符号导出控制：`setLinkerScript` 与 `setVersionScript`

在系统级与嵌入式编程中，控制内存布局与导出符号至关重要：
- **指定链接脚本（`setLinkerScript`）**：在无操作系统（Freestanding）裸机开发中，通过 [lib/std/Build/Step/Compile.zig:L571](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L571) 指定自定义的 `linker.ld`，精确规划 Flash、RAM 区域及中断向量表的物理地址：
  ```zig
  kernel_elf.setLinkerScript(b.path("src/linker.ld"));
  ```
- **版本符号控制脚本（`setVersionScript`）**：在构建 Linux 动态共享库时，通过 [lib/std/Build/Step/Compile.zig:L577](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L577) 传入 GNU 链接器版本脚本（Version Script / Symbol Map），精确控制对外公开的导出符号，隐藏内部符号：
  ```zig
  shared_lib.setVersionScript(b.path("src/exports.map"));
  ```

---

## 2. 构建库文件：`b.addLibrary`

静态库（`.a` / `.lib`）与动态库（`.so` / `.dylib` / `.dll`）统一通过 `b.addLibrary` 声明，通过 `.linkage` 枚举区分：

```zig
// 1. 静态库
const static_lib = b.addLibrary(.{
    .name = "my_lib",
    .linkage = .static,
    .root_module = my_module,
});
b.installArtifact(static_lib);

// 2. 动态共享库
const shared_lib = b.addLibrary(.{
    .name = "my_lib",
    .linkage = .dynamic,
    .version = .{ .major = 1, .minor = 2, .patch = 0 },
    .root_module = my_module,
});
b.installArtifact(shared_lib);
```

### 动态库版本控制：
构建动态库时，通过设置 `.version`（`std.SemanticVersion`），Zig 会为目标系统生成带有主次版本号的产物与对应的软链接（例如在 Linux 上输出 `libmy_lib.so.1.2.0` 并创建 `libmy_lib.so.1` 软链接）。

---

## 3. 运行与测试管线：`b.addTest` 与 `b.addRunArtifact`

构建脚本中运行单元测试分为两步：
1. 编译单元测试可执行文件（`addTest`）；
2. 执行该测试二进制进程（`addRunArtifact`）。

```zig
// 1. 声明测试编译步骤
const unit_tests = b.addTest(.{
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    }),
});

// 2. 声明测试运行步骤
const run_unit_tests = b.addRunArtifact(unit_tests);

// 3. 绑定到 "zig build test" 入口
const test_step = b.step("test", "Run all unit tests");
test_step.dependOn(&run_unit_tests.step);
```

### 3.1 编译与运行拆分的必要性
- **支持交叉编译下的测试验证**：若指定目标为其他平台架构（如在 macOS 上交叉编译 Linux aarch64 产物），测试程序可以在宿主机缺少仿真环境时，仅执行编译验证；
- **配置执行环境**：`run_unit_tests` 允许定制工作目录、环境变量，以及断言进程退出码：
  ```zig
  run_unit_tests.expectExitCode(0);
  run_unit_tests.setEnvironmentVariable("LOG_LEVEL", "DEBUG");
  ```

### 3.2 命令行工具集成测试断言与流控

除了源码级单元测试（`addTest`），命令行应用程序更需要端到端黑盒测试（E2E Integration Testing）。Zig 的 `Step.Run` 提供了丰富的流捕获与断言校验能力：

```zig
// 1. 获取已构建的主程序产物
const run_app = b.addRunArtifact(exe);

// 2. 传入测试命令行参数
run_app.addArgs(&.{ "--config", "test.json", "--verbose" });

// 3. 捕获并断言标准输出 (Stdout)
run_app.captureStdOut();
run_app.expectStdOutMatch("Operation completed successfully");

// 4. 断言异常退出状态码（如错误输入应返回退出码 1）
run_app.expectExitCode(1);

// 5. 注入测试隔离环境变量
run_app.setEnvironmentVariable("APP_ENV", "integration-test");

// 6. 绑定到 test 步骤联动调度
test_step.dependOn(&run_app.step);
```

> 💡 **提示**：
> 当使用 `captureStdOut()` 时，进程的标准输出会被管道拦截并在构建引擎内部进行比对。如果输出不匹配，构建过程会以高亮 Diff 报错，非常适合用于 CLI 程序的端到端自动化回归测试。

### 3.3 IDE 极速诊断模式：`check` 步骤

在日常开发与 IDE 编码中，ZLS（Zig Language Server）每次保存文件都需要触发构建系统获取语法和类型检查报错。如果每次都执行全量编译、链接与落盘，会带来显著延迟。

社区与官方标准做法是在 `build.zig` 中配置轻量级 `check` 步骤：

```zig
// 为 IDE/语言服务器准备的语义检查步骤（不产生任何最终磁盘二进制）
const exe_check = b.addExecutable(.{
    .name = "check",
    .root_module = exe.root_module, // 复用主应用程序的核心编译配置
});

// 注册专用的顶层 check 命令："zig build check"
const check_step = b.step("check", "Check syntax and type safety without linking or installing");
check_step.dependOn(&exe_check.step);
```

ZLS 默认会调用 `zig build check`，仅触发编译器前端语义分析（Sema），跳过后端的机器码优化、代码生成与链接，使编辑器保存时的错误提示缩短至毫秒级。

---

## 4. 辅助产物与静态资源交付：文档生成与 `installDirectory`

在工业级项目中，最终交付的产物不仅包含二进制可执行文件，往往还包括 API 参考文档与静态资源文件（如 Web 前端资源、着色器、配置文件等）。

### 4.1 自动化 HTML API 文档生成：`compile.getEmittedDocs()`

Zig 编译器内置了自动化文档生成系统，能够直接从源码注释（`//!` 与 `///`）中提取并渲染生成现代化的单页 HTML API 参考文档。

通过 [lib/std/Build/Step/Compile.zig:L723](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build/Step/Compile.zig#L723) 的 `getEmittedDocs()` 获取文档输出的 `LazyPath`，并接入安装步骤：

```zig
// 1. 从编译产物中提取 HTML 文档树 (LazyPath)
const docs = exe.getEmittedDocs();

// 2. 声明文档安装步骤：将生成的 HTML 文档输出到交付目录 zig-out/docs/
const install_docs = b.addInstallDirectory(.{
    .source_dir = docs,
    .install_dir = .prefix,
    .install_subdir = "docs",
});

// 3. 注册顶层命令："zig build docs"
const docs_step = b.step("docs", "Generate and install HTML API documentation");
docs_step.dependOn(&install_docs.step);
```

开发者在终端执行 `zig build docs` 即可在 `zig-out/docs/` 下生成完整的静态文档网站。

### 4.2 静态资源目录打包交付：`b.installDirectory`

当应用程序需要打包随行资源（例如游戏中的纹理模型、GUI 客户端中的图标着色器、Web 服务的静态前端 HTML/JS 资源）时，使用 [lib/std/Build.zig:L1478](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Build.zig#L1478) 的 `installDirectory` 将整个物理目录复制到交付目录：

```zig
b.installDirectory(.{
    .source_dir = b.path("assets"),
    .install_dir = .prefix,
    .install_subdir = "share/my_app/assets",
});
```

构建执行后，`assets/` 目录下的所有文件会完整保留层级结构投影至 `zig-out/share/my_app/assets/` 中。

---

## 5. 跨平台测试执行器配置与产物清理局限

### 4.1 仿真器配置（QEMU Runner）

在 x86_64 开发机上交叉编译 ARM64 或 RISC-V 测试程序时，可以通过 `run_unit_tests.setExecCmd` 指定仿真器：

```zig
if (target.result.cpu.arch != builtin.target.cpu.arch) {
    run_unit_tests.setExecCmd(&.{ "qemu-aarch64", "-L", "/usr/aarch64-linux-gnu" });
}
```

在缺少运行环境或仿真器的 CI 机器上，可以仅调度 `&unit_tests.step`（只编译测试二进制），提前发现目标平台的语法和类型错误。

### 4.2 局限与不足

1. **缺少内置的 `clean` 目标**：
   Zig 官方未提供 `zig build clean` 命令。当需要释放磁盘空间或清理缓存时，开发者需要通过外部命令手动删除 `.zig-cache` 和 `zig-out`；
2. **交付目录缺少失效产物清理**：
   若在 `build.zig` 中重命名或删除了某个产物，重新构建时旧的二进制文件仍会留在 `zig-out/bin/` 目录中，系统不会自动清理当前构建图未声明的残留文件。
