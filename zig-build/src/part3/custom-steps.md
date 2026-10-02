# 编写自定义 Step：扩展构建管线

当内置的 Step（如编译、运行、代码生成等）无法满足特定任务（如打包归档、校验签名、格式化非代码文件等）时，可以通过实现 `std.Build.Step.makeFn` 编写自定义 Step。

---

## 1. Step 的基本结构

实现自定义 Step 需满足两个条件：
1. 结构体中包含一个 `std.Build.Step` 字段；
2. 提供符合签名的执行函数：
   ```zig
   fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void
   ```

---

## 2. 示例：编写打包归档 Step

以下示例演示如何在产物安装后，将 `zig-out/` 目录打包为 `release.tar.gz`：

```zig
const std = @import("std");

pub const PackReleaseStep = struct {
    step: std.Build.Step,
    output_path: []const u8,

    pub fn create(b: *std.Build, output_name: []const u8) *PackReleaseStep {
        const self = b.allocator.create(PackReleaseStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "pack-release",
                .owner = b,
                .makeFn = make,
            }),
            .output_path = output_name,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        const self: *PackReleaseStep = @fieldParentPtr("step", step);
        const b = step.owner;

        std.debug.print("Packaging release archive to {s}...\n", .{self.output_path});

        var child = std.process.Child.init(&.{
            "tar", "-czf", self.output_path, "-C", "zig-out", ".",
        }, b.allocator);
        _ = try child.spawnAndWait();
    }
};
```

---

## 3. 在 `build.zig` 中使用自定义 Step

定义后，可在 `build(b)` 函数中创建并设置依赖边：

```zig
pub fn build(b: *std.Build) void {
    // 1. 构建主程序
    const exe = b.addExecutable(.{ ... });
    const install_exe = b.addInstallArtifact(exe, .{});

    // 2. 实例化自定义打包步骤
    const pack_step = PackReleaseStep.create(b, "dist/app.tar.gz");

    // 3. 声明依赖：必须在产物安装完毕后再执行打包
    pack_step.step.dependOn(&install_exe.step);

    // 4. 注册顶层命令："zig build pack"
    const top_pack = b.step("pack", "Package distribution archive");
    top_pack.dependOn(&pack_step.step);
}
```

### 特点说明：
- **统一的任务调度**：自定义 Step 与内置的 `Compile`、`Run` 一样参与拓扑排序和多线程调度；
- **执行期隔离**：子进程派生和文件读写集中在 `make` 执行期完成，保持配置期轻量。
