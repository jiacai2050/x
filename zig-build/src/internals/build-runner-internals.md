# 构建自举：Build Runner 的动态编译与调度

执行 `zig build` 时，Zig 既没有内置解释器来动态解释 `build.zig`，也没有将构建逻辑固化在编译器二进制中，而是采用自举动态编译（Bootstrap Dynamic Compilation）机制：先将 `build.zig` 编译为独立的构建运行器程序，再启动运行。

---

## 1. 架构总览：从命令路由到独立运行器

从执行 `zig build` 到构建图调度执行，主要分为四个阶段：

```mermaid
graph TD
    subgraph S_CLI ["阶段一：CLI 命令分发"]
        C_Cmd["终端执行 zig build"]
        C_Route["src/main.zig: cmdBuild()"]
        C_Cmd --> C_Route
    end

    subgraph S_CompileRunner ["阶段二：Build Runner 动态编译"]
        R_Entry["编译器内部模版: lib/compiler/build_runner.zig"]
        R_User["用户项目脚本: build.zig (作为 @build 模块)"]
        R_Bin["编译生成临时独立程序:<br/>.zig-cache/o/.../build"]
        R_Entry --> R_Bin
        R_User --> R_Bin
    end

    subgraph S_Spawn ["阶段三：派生子进程运行"]
        P_Spawn["std.process.spawn 启动该 build 二进制程序"]
        P_Args["转发 CLI 参数 (-Dtarget, -Doptimize, top-level step 等)"]
        P_Spawn --> P_Args
    end

    subgraph S_Exec ["阶段四：图构建与多线程调度"]
        E_Build["调用 @build.build(b) 在堆中构建 DAG"]
        E_Topo["拓扑排序并提取依赖子图"]
        E_Pool["工作线程池并发拉取 Step 执行 make()"]
        E_Build --> E_Topo
        E_Topo --> E_Pool
    end

    C_Route --> R_Bin
    R_Bin --> P_Spawn
    P_Args --> E_Build

    classDef default stroke:#495057;
    style S_CLI stroke:#ff9900,stroke-width:2px;
    style S_CompileRunner stroke:#0066cc,stroke-width:2px;
    style S_Spawn stroke:#ffc107,stroke-width:2px;
    style S_Exec stroke:#009900,stroke-width:2px;
    style C_Cmd stroke:#495057,stroke-width:2px;
    style C_Route stroke:#ff9900,stroke-width:2px;
    style R_Entry stroke:#0066cc,stroke-width:2px;
    style R_User stroke:#0066cc,stroke-width:2px;
    style R_Bin stroke:#0066cc,stroke-width:2px;
    style P_Spawn stroke:#ffc107,stroke-width:2px;
    style P_Args stroke:#ffc107,stroke-width:2px;
    style E_Build stroke:#009900,stroke-width:2px;
    style E_Topo stroke:#009900,stroke-width:2px;
    style E_Pool stroke:#009900,stroke-width:2px;
```

---

## 2. 源码级机制：运行器的动态组装

1. **命令路由**：
   在 Zig 编译器入口 [src/main.zig](https://codeberg.org/ziglang/zig/src/tag/0.16.0/src/main.zig) 中，命令行解析器识别到子命令 `build`，路由进入 `cmdBuild` 函数。
2. **装载 `build_runner.zig`**：
   Zig 内置了一个运行器模版文件 `lib/compiler/build_runner.zig`。编译器创建一个编译单元：
   - 将 `build_runner.zig` 作为根源文件；
   - 将用户工作区中的 `build.zig` 映射为一个特殊的模块名称 `@build`。
3. **编译为独立临时程序**：
   Zig 使用 Native Debug 后端快速将其编译为一个独立的可执行文件，落盘存放在：
   `.zig-cache/o/<hash>/build`
4. **子进程执行**：
   `cmdBuild` 随后调用操作系统的 `spawn` 接口，启动该 `build` 二进制程序，并将终端接收到的所有参数原封不动地转发过去。

---

## 3. 调度引擎：拓扑排序与多线程工作池

在编译好的 `build` 程序内部：

1. **执行 `@build.build(b)`**：
   在单线程中初始化 `std.Build` 上下文，调用用户的构建函数，生成内存 DAG。
2. **提取执行子图与拓扑排序**：
   如果用户指定了构建目标（例如 `zig build test`），运行器遍历图结构，裁剪出所有未执行的前置依赖节点。
3. **并发任务队列推进**：
   运行器内置了工作线程池（Worker Pool）。调度器循环扫描入度（In-degree）为 0 的节点：
   - 首先通过 `Cache.Manifest` 比对输入指纹，若完全一致则标记为已完成（Cache Hit）；
   - 若未命中，则派发到空闲的工作线程执行 `step.make()`；
   - 当某个节点执行完成，其依赖者的入度减 1；一旦入度降为 0，立即激活并推入并发执行队列。

这一机制确保了依赖图中的各个节点能够在无竞态的前提下全核并发执行。

---

## 4. 运行器自举机制与代价

### 4.1 机器码执行与环境一致性

Zig 构建运行器采用自举编译，直接生成原生可执行文件：
- **执行效率高**：运行器本身是原生二进制程序，图构建与 Manifest 序列化直接以机器码执行，无额外解释器或虚拟机开销；
- **环境一致**：编译 `build.zig` 的编译器与构建项目的编译器是同一套程序，无需依赖宿主机的外部脚本运行时。

### 4.2 局限与代价

1. **冷启动编译开销**：
   在干净环境或修改 `build.zig` 后，执行 `zig build` 时需要先完成运行器的编译与子进程启动，相比直接解析静态配置（如 Cargo.toml）存在短暂的冷启动耗时；
2. **错误堆栈混杂运行器代码**：
   若 `build.zig` 出现运行时 panic，报错堆栈中会包含 `lib/compiler/build_runner.zig` 的内部调度代码，初次排查时需要注意区分用户脚本逻辑与运行器调度代码。

---

## 5. 惰性依赖的重试机制

在 `build.zig.zon` 中标记为 `.lazy = true` 的依赖，在构建初始阶段不会预先拉取。运行器子进程与 `zig` 主进程通过退出码 3 的通信约定，实现了惰性依赖的按需探测与重新触发。

### 5.1 架构设计：为什么运行器自身不直接执行网络下载？

`build_runner` 是由 Zig 编译器动态编译生成的原生子进程，具有常规的用户态权限。构建系统没有让它直接联网下载依赖，主要出于两点考虑：

1. **包管理职责集中在主进程**：
   网络下载、镜像回退、代理配置、Multihash 校验，以及全局缓存（`~/.cache/zig/p/<hash>`）的文件锁与原子解压，都由 `zig` 主进程统一负责。如果让每个项目的临时 `build` 程序都链接 HTTP/TLS 和 Git 客户端，会明显增加运行器的编译开销与二进制体积。
2. **支持批量并发拉取**：
   如果每次在 `lazyDependency` 处同步下载，多个条件依赖就会串行阻塞（下载 A -> 继续执行 -> 发现缺少 B -> 下载 B）。把配置期作为无网络阻塞的探测阶段，可以让运行器一次性收集齐本次构建所需的全部缺失依赖，交由主进程并发拉取。

### 5.2 源码级交互机制与时序

父子进程的协作流程如下：

```mermaid
graph TD
    subgraph S_Parent ["1. Zig 编译前端主进程 (zig build)"]
        P_Start["启动 zig build 命令"]
        P_Compile["编译 build_runner 程序<br/>(缺失依赖注入 available = false)"]
        P_Spawn["启动运行器子进程<br/>(传入 -Z<nonce> 等参数)"]
        P_Wait["等待子进程退出并检查退出码"]
        P_Fetch["读取 .zig-cache/tmp/<nonce><br/>并发网络拉取缺失依赖至 ~/.cache/zig/p/"]
        P_Recompile["重新编译 build_runner<br/>(依赖就绪，available = true)"]
    end

    subgraph S_Child ["2. 运行器子进程 (build_runner)"]
        C_Run["执行 build.zig 中的 build(b)"]
        C_Lazy["调用 b.lazyDependency(name, args)"]
        C_Check{"检查依赖是否已在全局缓存<br/>(available)"}
        C_Mark["调用 markNeededLazyDep<br/>记录 pkg_hash 并返回 null"]
        C_Ret["返回 *Dependency 实例"]
        C_Exit3["写出缺失清单至 .zig-cache/tmp/<nonce><br/>调用 process.exit(3) 退出"]
        C_DAG["构建 DAG 完成<br/>进入 Make 执行阶段"]
    end

    P_Start --> P_Compile
    P_Compile --> P_Spawn
    P_Spawn --> C_Run
    C_Run --> C_Lazy
    C_Lazy --> C_Check
    C_Check -- "未下载 (available=false)" --> C_Mark
    C_Check -- "已缓存 (available=true)" --> C_Ret
    C_Ret --> C_DAG
    C_Mark -- "配置期结束且缺失清单非空" --> C_Exit3
    C_Exit3 -- "子进程退出 (退出码 3)" --> P_Wait
    P_Wait -- "捕获 exit(3)" --> P_Fetch
    P_Fetch -- "全部解压就绪" --> P_Recompile
    P_Recompile -- "二次启动运行器" --> P_Spawn

    classDef default stroke:#495057;
    style S_Parent stroke:#ff9900,stroke-width:2px;
    style S_Child stroke:#0066cc,stroke-width:2px;
    style P_Start stroke:#495057,stroke-width:2px;
    style P_Compile stroke:#ff9900,stroke-width:2px;
    style P_Spawn stroke:#ffc107,stroke-width:2px;
    style P_Wait stroke:#ffc107,stroke-width:2px;
    style P_Fetch stroke:#0066cc,stroke-width:2px;
    style P_Recompile stroke:#198754,stroke-width:2px;
    style C_Run stroke:#495057,stroke-width:2px;
    style C_Lazy stroke:#0066cc,stroke-width:2px;
    style C_Check stroke:#ffc107,stroke-width:2px;
    style C_Mark stroke:#dc3545,stroke-width:2px;
    style C_Ret stroke:#198754,stroke-width:2px;
    style C_Exit3 stroke:#dc3545,stroke-width:2px;
    style C_DAG stroke:#198754,stroke-width:2px;
```

#### 流程分步说明：

1. **传递临时通信标识（`-Z<nonce>`）**：
   在 `src/main.zig` 中，主进程启动 `build_runner` 时会传入一个 16 字节随机标识 `-Z<nonce>`（即源码中的 `output_tmp_nonce`），作为本次通信的临时文件名。
2. **检查可用性并记录缺失哈希**：
   在 `lib/std/Build.zig` 的 `lazyDependency` 源码中：
   ```zig
   const pkg = @field(deps.packages, decl.name);
   const available = !@hasDecl(pkg, "available") or pkg.available;
   if (!available) {
       markNeededLazyDep(b, pkg_hash);
       return null;
   }
   ```
   如果依赖未下载（全局缓存中不存在），代码生成阶段会把该包的 `available` 设为 `false`。`lazyDependency` 将其哈希加入 `graph.needed_lazy_dependencies`，并返回 `null`。
3. **写出缺失清单并以状态码 3 退出**：
   用户 `build(b)` 函数返回后，`lib/compiler/build_runner.zig` 会检查收集到的依赖：
   ```zig
   if (graph.needed_lazy_dependencies.entries.len != 0) {
       // 将缺失的 pkg_hash 写入 .zig-cache/tmp/<nonce> 文件
       ...
       process.exit(3);
   }
   ```
   只要探测到缺失的惰性依赖，运行器就会把哈希列表写入 `.zig-cache/tmp/<nonce>`，随后调用 `process.exit(3)` 退出，不会进入后续的 Make 编译阶段。
4. **主进程并发拉取并重新运行**：
   主进程捕获到子进程退出码为 3，读取临时文件中的哈希列表，通过网络并发下载这些依赖包，校验 Multihash 并解压至全局缓存目录；随后重新生成元数据、重新编译 `build_runner` 并再次执行。第二轮运行时，依赖的 `available` 已变为 `true`，`b.lazyDependency` 就能正常返回 `*Dependency` 实例。

---

### 5.3 库作者注意事项：提前注册对外模块

运行器的两阶段重试机制对公共库的设计提出了一个明确要求：

> ⚠️ 对外暴露的模块（`b.addModule`）必须在任何因 `lazyDependency == null` 提前返回的代码之前完成注册。

当公共库被下游项目引用时：
- 下游项目的 `build.zig` 通常会先调用 `const dep = b.dependency("your_lib", .{});`，随后通过 `dep.module("your_module")` 获取导出的模块；
- 在第一轮探测阶段，若上游库因为 `b.lazyDependency(...)` 返回 `null` 而直接 `return`，且此时还没有调用 `b.addModule("your_module", ...)`，下游项目在调用 `dep.module` 时就会直接 panic（`unable to find module 'your_module'`）；
- 这个 panic 会导致构建进程非正常退出（退出码不是 3），主进程也就无法进入依赖下载与重新运行流程。

编写包含惰性依赖的公共库时，应优先调用 `b.addModule` 注册对外暴露的模块骨架，然后再处理内部依赖的探测与装配：

```zig
// 推荐写法：先注册对外模块，再处理惰性依赖
pub fn build(b: *std.Build) void {
    const module = b.addModule("my_lib", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const upstream = b.lazyDependency("upstream", .{}) orelse return;
    module.linkLibrary(upstream.artifact("c_lib"));
}
```
这样即使上游依赖尚未就绪、构建脚本在首轮提前退出，下游也能拿到有效的模块引用，让主进程顺利完成两阶段的依赖补全。
