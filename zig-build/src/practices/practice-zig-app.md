# 实战一：标准 Zig CLI 应用与单元测试

本章通过一个纯 Zig 命令行工程模板，展示项目的基础工程目录布局与 `build.zig` 标准骨架。

> 💡 **配套可运行示例**
> 本章对应的完整独立工程代码位于 GitHub：[`examples/01-zig-app`](https://github.com/jiacai2050/x/tree/main/zig-build/examples/01-zig-app)。
> 你可以进入该目录并通过以下命令体验运行与测试：
> ```bash
> cd examples/01-zig-app
> zig build run
> zig build test
> ```

---

## 1. 推荐工程目录结构

一个结构清晰的 Zig 工程通常将应用入口（`main.zig`）与核心库逻辑（`root.zig`）分开：

```text
my-zig-cli/
├── build.zig             # 构建脚本
├── build.zig.zon         # 包元数据与依赖清单
├── src/
│   ├── main.zig          # CLI 命令行入口（参数解析与派发）
│   ├── root.zig          # 核心业务库入口（导出类型与函数）
│   └── calc.zig          # 计算器核心逻辑实现
└── README.md
```

---

## 2. 标准 `build.zig` 完整实现

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // 1. 标准命令行构建选项
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 2. 定义核心业务库模块
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 3. 定义主 CLI 应用程序的可执行文件
    const exe = b.addExecutable(.{
        .name = "my-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // 注入业务库模块，使 main.zig 可以 @import("my_lib")
            .imports = &.{
                .{ .name = "my_lib", .module = lib_mod },
            },
        }),
    });

    // 将应用安装到交付目录 zig-out/bin/my-cli
    b.installArtifact(exe);

    // 4. 支持 "zig build run" 运行命令并透传命令行参数
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 5. 支持 "zig build test" 执行单元测试
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
```

---

## 3. 关键设计说明

1. **库与 CLI 解耦**：通过创建 `lib_mod`，核心业务逻辑可以同时被 `main.zig` 消费，也可以作为库被其他项目依赖；
2. **命令行参数透传（`addPassthruArgs`）**：通过 `run_cmd.addPassthruArgs()`，在 DAG 中记录参数占位符，由 `Maker` 在执行期将命令行 `--` 之后的参数安全透传给被调用的应用程序：
   ```bash
   zig build run -- --version
   zig build run -- process input.txt --output result.json
   ```
   所有在 `--` 之后的参数都会直接传递给目标应用程序的参数迭代器，且不会破坏配置缓存。
