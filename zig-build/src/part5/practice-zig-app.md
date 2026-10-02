# 实战一：标准 Zig CLI 应用与单元测试

本章通过一个规范的纯 Zig 命令行工程模板，展示现代 Zig（0.16.0）项目的基础工程目录布局与 `build.zig` 标准骨架。

---

## 1. 推荐工程目录结构

一个结构清晰的 Zig 工程通常将应用入口（`main.zig`）与核心库逻辑（`root.zig`）分开：

```text
my-zig-cli/
├── build.zig             # 构建脚本
├── build.zig.zon         # 包元数据与依赖清单
├── src/
│   ├── main.zig          # CLI 命令行入口（包含参数解析、命令分发）
│   ├── root.zig          # 核心业务库入口（导出类型与函数）
│   └── calc.zig          # 具体计算逻辑模块
└── README.md
```

---

## 2. 标准 `build.zig` 完整实现

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // 1. Standard options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 2. Define the core library module
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 3. Define the main CLI application executable
    const exe = b.addExecutable(.{
        .name = "my-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // Inject lib_mod so main.zig can @import("my_lib")
            .imports = &.{
                .{ .name = "my_lib", .module = lib_mod },
            },
        }),
    });

    // Install application to zig-out/bin/my-cli
    b.installArtifact(exe);

    // 4. "zig build run" support
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // 5. "zig build test" support
    const exe_unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
```

---

## 3. 关键设计说明

1. **库与 CLI 解耦**：通过创建 `lib_mod`，核心业务逻辑可以同时被 `main.zig` 消费，也可以作为库被其他项目依赖；
2. **命令行参数转发**：通过 `if (b.args) |args| run_cmd.addArgs(args);`，终端用户可以直接运行：
   ```bash
   zig build run -- --version
   zig build run -- process input.txt --output result.json
   ```
   所有在 `--` 之后的参数都会直接传递给目标应用程序的 `main` 函数。
