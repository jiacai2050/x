# 两阶段生命周期：配置期与执行期

编写 `build.zig` 时，需要区分配置期（Configuration Phase）与执行期（Execution Phase）。

如果混淆这两个阶段，容易在 `build()` 中尝试直接读取尚未生成的文件而导致文件不存在报错。

---

## 1. 生命周期的两个阶段

执行 `zig build` 时，构建系统依次经历以下两个阶段：

```mermaid
graph TD
    subgraph Phase1 ["阶段一：配置期 (Configuration / Graph Evaluation)"]
        B_Code["执行 build.zig 中的 build(b) 入口"]
        B_Graph["在内存中实例化 Step 节点"]
        B_Option["解析命令行选项 (-Dtarget, -Doptimize 等)"]
        B_Edge["建立节点间依赖关系 (dependOn / LazyPath)"]
        B_Code --> B_Option
        B_Option --> B_Graph
        B_Graph --> B_Edge
    end

    subgraph Phase2 ["阶段二：执行期 (Execution / Graph Execution)"]
        E_Topo["拓扑排序并截取目标子图 (如 install / run)"]
        E_Pool["工作线程池并发调度就绪任务"]
        E_Cache{"Cache.Manifest<br/>内容哈希比对"}
        E_Skip["命中缓存：跳过执行 (Cache Hit)"]
        E_Worker["未命中：调用 Step.make() 编译或生成文件"]
        E_Topo --> E_Pool
        E_Pool --> E_Cache
        E_Cache -- "是" --> E_Skip
        E_Cache -- "否" --> E_Worker
    end

    Phase1 -- "构建图定型，移交调度器" --> Phase2

    classDef default stroke:#495057;
    style Phase1 stroke:#ff9900,stroke-width:2px;
    style Phase2 stroke:#009900,stroke-width:2px;
    style B_Code stroke:#495057,stroke-width:2px;
    style B_Option stroke:#495057,stroke-width:2px;
    style B_Graph stroke:#0066cc,stroke-width:2px;
    style B_Edge stroke:#0066cc,stroke-width:2px;
    style E_Topo stroke:#0066cc,stroke-width:2px;
    style E_Pool stroke:#009900,stroke-width:2px;
    style E_Cache stroke:#ffc107,stroke-width:2px;
    style E_Skip stroke:#198754,stroke-width:2px;
    style E_Worker stroke:#0066cc,stroke-width:2px;
```

---

## 2. 阶段一：配置期（Graph Evaluation）

配置期由构建运行器调用 `build.zig` 中的公开入口：

```zig
pub fn build(b: *std.Build) void {
    // Configuration logic executed here
}
```

### 核心特征：
1. **内存中构建任务图**：
   在 `build(b)` 函数中调用的 `b.addExecutable`、`b.addLibrary` 或 `b.addConfigHeader` 等 API，不会立即启动编译器，也不会向磁盘输出生成文件。这些 API 负责在堆内存中分配 `std.Build.Step` 节点，记录编译配置并连接依赖边。
2. **执行轻量**：
   由于不涉及编译与重度 I/O，配置阶段通常在几毫秒至几十毫秒内完成。
3. **不能直接读取生成物**：
   不要在 `build()` 中通过同步文件系统 API 读取由前序步骤生成的文件：
   ```zig
   // 错误示例：在配置期读取尚未生成的文件
   const config_h = b.addConfigHeader(...);
   // 此时磁盘上尚未生成 config.h，直接打开会抛出 FileNotFound 异常
   const file = try std.fs.cwd().openFile("config.h", .{});
   ```
   传递生成物路径时，应使用后续章节介绍的 `LazyPath`。

---

## 3. 阶段二：执行期（Graph Execution）

当 `build(b)` 函数返回后，内存中的计算图（DAG）定型，控制权移交给任务调度器。

### 执行流程：
1. **确定目标子图**：
   根据命令行指定的顶层任务（如默认的 `install`，或 `test`/`run`），调度器从目标节点开始反向遍历，截取所需的依赖子图并完成拓扑排序；
2. **多线程并发调度**：
   调度器启动工作线程池，将入度为 0（无前置依赖或前置依赖已就绪）的任务放入待执行队列；
3. **哈希缓存比对**：
   每个 Step 在执行前，会根据输入文件、配置选项和环境信息计算 Manifest Hash。如果 `.zig-cache/` 中已有该哈希的有效记录，则直接跳过（Cache Hit）；
4. **调用 `Step.make()`**：
   未命中缓存时，线程池调用该 Step 的 `makeFn` 函数，执行编译器调用、文件写入或测试运行。

---

## 4. 两阶段对比

| 维度 | 配置期（Configuration Phase） | 执行期（Execution Phase） |
| :--- | :--- | :--- |
| **入口** | `pub fn build(b: *std.Build) void` | `step.makeFn(step, options)` |
| **主要工作** | 声明构建图、解析参数、建立依赖边 | 检查缓存、执行真实编译、产物落盘 |
| **执行方式** | 单线程主流程 | 多线程任务池并发 |
| **文件访问** | 读取只读静态源码与已有配置文件 | 在 `.zig-cache` 与 `zig-out` 中读写中间产物 |

---

## 5. 设计特点与常见踩坑

### 5.1 意图声明与并发执行解耦

两阶段设计将构建逻辑明确分为“声明”与“执行”两个步骤：
- **按需裁剪（Sub-tree Pruning）**：用户指定 `zig build test` 时，调度器仅从 `test` 节点反向遍历依赖边，主程序编译或安装相关的节点不会被执行，避免不必要的编译；
- **并发调度**：在 `build.zig` 中只需声明依赖关系（通过 `dependOn` 或 `LazyPath`），执行期由调度器自动将就绪节点分派给线程池并行执行，无需手动处理线程同步。

### 5.2 阶段越界问题

编写构建脚本时，需要避免将本应在执行期发生的操作写在配置期：

1. **在配置期读取尚未生成的文件**
   ```zig
   // 错误做法：在配置期直接读取生成文件
   const config_h = b.addConfigHeader(...);
   const file = try std.fs.cwd().openFile("zig-out/include/config.h", .{}); // 此时文件尚未生成，抛出 FileNotFound
   ```
   **说明**：`b.addConfigHeader` 只在内存中创建了 Step 节点。直到配置期结束、执行期调度器调用该 Step 的 `make` 方法时，文件才会真正写入磁盘。
2. **在配置期同步派生外部进程**
   ```zig
   // 不推荐：在 build() 中同步运行系统命令
   var child = std.process.Child.init(&.{ "git", "rev-parse", "HEAD" }, b.allocator);
   const output = try child.spawnAndWait();
   ```
   **问题**：这会导致执行任何 `zig build` 命令（包括 `zig build --help`）时都必须等待该外部命令执行完成，而且**无法享受增量缓存**。
   **建议做法**：使用 `b.addSystemCommand(&.{ "git", "rev-parse", "HEAD" })` 将其声明为 `Step.Run` 任务，交由 DAG 调度并参与缓存判定。
