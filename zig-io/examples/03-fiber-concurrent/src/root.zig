const std = @import("std");
const Io = std.Io;

/// 任务执行上下文
pub const TaskContext = struct {
    counter: std.atomic.Value(usize) = .{ .raw = 0 },

    /// 任务函数：必须返回 Cancelable!void
    pub fn worker(ctx: *TaskContext, steps: usize) Io.Cancelable!void {
        var i: usize = 0;
        while (i < steps) : (i += 1) {
            _ = ctx.counter.fetchAdd(1, .monotonic);
        }
    }
};

/// 运行结构化任务组
pub fn runConcurrentBatch(io: Io, ctx: *TaskContext, worker_count: usize, steps_per_worker: usize) !void {
    var group: Io.Group = .init;

    var i: usize = 0;
    while (i < worker_count) : (i += 1) {
        // 向任务组中追加并行计算任务
        try group.concurrent(io, TaskContext.worker, .{ ctx, steps_per_worker });
    }

    // 结构化收敛：等待组内所有任务彻底完成
    try group.await(io);
}

test "Io.Group 结构化并发累加测试" {
    const io = std.testing.io;

    var ctx = TaskContext{};
    const worker_count = 4;
    const steps_per_worker = 250;

    try runConcurrentBatch(io, &ctx, worker_count, steps_per_worker);

    // 验证所有 worker 是否全部完整收敛执行完毕
    const final_val = ctx.counter.load(.acquire);
    try std.testing.expectEqual(worker_count * steps_per_worker, final_val);
}
