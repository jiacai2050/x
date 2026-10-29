const std = @import("std");
const Io = std.Io;
const concurrent_tasks = @import("concurrent_tasks");

pub fn main() !void {
    const allocator = std.heap.smp_allocator;

    var threaded = Io.Threaded.init(allocator, .{
        .stack_size = 64 * 1024,
    });
    defer threaded.deinit();

    const io = threaded.io();

    var ctx = concurrent_tasks.TaskContext{};
    const workers = 8;
    const steps = 1000;

    std.debug.print("启动 {d} 个并发任务，每个执行 {d} 步累加...\n", .{ workers, steps });
    try concurrent_tasks.runConcurrentBatch(io, &ctx, workers, steps);

    const total = ctx.counter.load(.acquire);
    std.debug.print("所有并发任务收敛完成，最终计数值: {d}\n", .{total});
}
