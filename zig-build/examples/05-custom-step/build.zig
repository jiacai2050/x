const std = @import("std");

pub const ReportStep = struct {
    step: std.Build.Step,
    report_text: []const u8,

    pub fn create(b: *std.Build, text: []const u8) *ReportStep {
        const self = b.allocator.create(ReportStep) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "custom-report",
                .owner = b,
                .makeFn = make,
            }),
            .report_text = text,
        };
        return self;
    }

    fn make(step: *std.Build.Step, options: std.Build.Step.MakeOptions) anyerror!void {
        _ = options;
        const self: *ReportStep = @fieldParentPtr("step", step);
        std.debug.print("=== Custom Step Executed: {s} ===\n", .{self.report_text});
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "custom_step_demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const report_step = ReportStep.create(b, "Build validation successful!");
    report_step.step.dependOn(&exe.step);

    const validate_step = b.step("validate", "Run custom validation step");
    validate_step.dependOn(&report_step.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run demo app");
    run_step.dependOn(&run_cmd.step);
}
