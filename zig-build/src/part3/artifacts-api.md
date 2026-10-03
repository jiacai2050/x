# 产物构建：Executable、Library 与 Test

在 Zig 构建系统中，生成最终二进制产物（可执行文件、静态库/动态库、测试程序）的任务由 `Step.Compile` 负责。

> 💡 **配套可运行示例**
> 关于标准应用程序产物与单元测试构建的完整代码工程，可参考 GitHub 示例：[`examples/01-zig-app`](https://github.com/jiacai2050/x/tree/main/zig-build/examples/01-zig-app)，以及后续实战章节 [实战一：标准 Zig CLI 应用与单元测试](../part5/practice-zig-app.md)。

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
```

### 关键配置：
- **`root_module`**：挂载主程序的编译上下文与依赖；
- **产物安装**：通过 `b.installArtifact(exe)` 将生成的可执行文件输出到 `zig-out/bin/my_app`（在 Windows 平台会自动追加 `.exe` 后缀）。

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

## 3. 运行与单元测试：`b.addTest` 与 `b.addRunArtifact`

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

### 将编译与运行拆分的用途：
- **支持交叉编译下的测试验证**：若指定目标为其他平台架构（如在 macOS 上交叉编译 Linux aarch64 产物），测试程序可以在宿主机缺少仿真环境时，仅执行编译验证；
- **配置执行环境**：`run_unit_tests` 允许定制工作目录、环境变量，以及断言进程退出码：
  ```zig
  run_unit_tests.expectExitCode(0);
  run_unit_tests.setEnvironmentVariable("LOG_LEVEL", "DEBUG");
  ```
