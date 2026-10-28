# 并发同步原语：Mutex、RwLock、Semaphore 与 Futex

在多纤程（Fiber）与多工作线程共存的并发系统中，传统的操作系统级线程锁（如 `pthread_mutex_t` 或 Win32 CriticalSection）存在致命缺陷：**一旦在纤程内部阻塞在 OS 锁上，将直接冻结整个宿主物理线程，导致同一线程上的其他就绪纤程全部陷入饥饿**。

因此，`std.Io` 内置了专门为异步/纤程协作体系量身定制的**协作型同步原语族**。

---

## 协作互斥锁：`Io.Mutex`

`Io.Mutex` 在争用未发生时以原子指令（CAS）直接极速获取；而在遭遇锁冲突时，**挂起的是当前纤程而非阻塞整个物理操作系统线程**：

```zig
const std = @import("std");
const Io = std.Io;

pub const SharedState = struct {
    mutex: Io.Mutex = .init,
    counter: usize = 0,

    pub fn increment(self: *SharedState, io: Io) !void {
        // 尝试获取锁；若锁被占用，当前纤程挂起，调度器自动切换执行其他任务
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);

        self.counter += 1;
    }

    pub fn tryIncrement(self: *SharedState, io: Io) bool {
        if (self.mutex.tryLock(io)) {
            defer self.mutex.unlock(io);
            self.counter += 1;
            return true;
        }
        return false;
    }
};
```

---

## 读写锁：`Io.RwLock`

在典型的“读多写少”场景（例如路由表缓存、配置参数查找）下，[`Io.RwLock`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/RwLock.zig) 允许多个并发读纤程并行访问，仅在写者更新时排他互斥：

```zig
pub const ConfigCache = struct {
    rwlock: Io.RwLock = .init,
    data: [128]u8 = undefined,

    pub fn readData(self: *ConfigCache, io: Io, out: []u8) !void {
        try self.rwlock.lockShared(io);
        defer self.rwlock.unlockShared(io);

        @memcpy(out, self.data[0..out.len]);
    }

    pub fn updateData(self: *ConfigCache, io: Io, new_data: []const u8) !void {
        try self.rwlock.lock(io);
        defer self.rwlock.unlock(io);

        @memcpy(self.data[0..new_data.len], new_data);
    }
};
```

---

## 信号量与并发度限流：`Io.Semaphore`

当需要对有限的物理资源（如数据库连接池上限、外部 API 请求速率）实施精确并发限制时，使用 [`Io.Semaphore`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io/Semaphore.zig)：

```zig
pub fn throttledWorker(io: Io, sem: *Io.Semaphore, job_id: usize) !void {
    // 消费一个可用许可；若当前无许可，纤程进入等待队列挂起
    try sem.wait(io);
    defer sem.post(io);

    // 真正执行资源受限的工作
    std.debug.print("Job {d} is executing with acquired slot\n", .{job_id});
}
```

---

## 底层同步基石：Futex

在 Linux 等系统上，`std.Io` 的虚表直接暴露了 Futex 原语（见 [`Io.zig#L140-L142`](https://codeberg.org/ziglang/zig/src/tag/0.17.0/lib/std/Io.zig#L140-L142)）：

```zig
// 等待某个 32 位内存地址的值是否发生变化
try io.vtable.futexWait(io.userdata, &atomic_val, expected_val, .unlimited);

// 唤醒指定数量在某个地址上休眠的等待者
io.vtable.futexWake(io.userdata, &atomic_val, 1);
```

通过这套完备的协作同步原语，开发者可以在构建复杂并发拓扑时，享受纯粹的顺序锁编写体验，同时保持整个事件驱动系统极致的 CPU 利用率与零线程停滞。
