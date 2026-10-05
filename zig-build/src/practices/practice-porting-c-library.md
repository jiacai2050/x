# 实战三：复杂第三方 C 库的完整移植实践（以 MariaDB Connector 为例）

移植单文件 C 代码通常较为直接，但主流 C 库（如 MariaDB Connector/C、SQLite、OpenSSL 等）通常包含较多源码文件、CMake 配置探测、平台条件编译分支以及第三方依赖。

本章以开源项目 [zig-mariadb-connector](https://github.com/jiacai2050/zig-mariadb-connector) 为例，梳理移植成熟 C 库到 Zig 构建系统的实践流程。关于社区常用 C 库的封装案例，也可以参考 [All Your Codebase](https://github.com/allyourcodebase/)。

> 💡 **配套可运行示例**
> 本章除了以真实开源库 [zig-mariadb-connector](https://github.com/jiacai2050/zig-mariadb-connector) 展开架构分析外，还在配套代码中提供了一个自包含、免外部网络依赖的 C 静态库封装与测试工程：[`examples/04-c-library-port`](https://github.com/jiacai2050/x/tree/main/zig-build/examples/04-c-library-port)。
> 你可以进入该目录运行测试：
> ```bash
> cd examples/04-c-library-port
> zig build test
> ```

---

## 1. 移植面临的核心挑战

大型 C 库的构建通常需要处理以下常见问题：

```mermaid
graph TD
    subgraph S_Challenge ["C 库移植常见问题"]
        C_Cfg["1. 平台检测配置头<br/>(config.h.in / 宏探测)"]
        C_Src["2. 条件编译源文件裁剪<br/>(POSIX vs Windows 平台分支)"]
        C_Tls["3. 第三方系统库链接<br/>(OpenSSL / Schannel / 平台依赖)"]
        C_Exp["4. 头文件树与产物规范导出<br/>(供下游纯 Zig / C 顺畅消费)"]
    end

    classDef default stroke:#495057;
    style S_Challenge stroke:#ff9900,stroke-width:2px;
    style C_Cfg stroke:#0066cc,stroke-width:2px;
    style C_Src stroke:#0066cc,stroke-width:2px;
    style C_Tls stroke:#0066cc,stroke-width:2px;
    style C_Exp stroke:#009900,stroke-width:2px;
```

---

## 2. 移植核心步骤拆解

### 第一步：零侵入管理 Upstream 源码
推荐保持上游代码仓库的纯净，通过 `b.dependency("upstream", ...)` 或特定子目录引入，不修改上游任何源码文件。

### 第二步：使用 `addConfigHeader` 替代 CMake 探测
MariaDB Connector 依赖 `include/config.h.in`。在 Zig 构建中，我们通过 `b.addConfigHeader` 并结合目标平台信息直接计算宏值：

```zig
const target_is_windows = target.result.os.tag == .windows;

const config_h = b.addConfigHeader(
    .{
        .style = .{ .cmake = upstream.path("include/config.h.in") },
        .include_path = "config.h",
    },
    .{
        .HAVE_STDDEF_H = true,
        .HAVE_STDINT_H = true,
        .HAVE_SYS_TYPES_H = true,
        .HAVE_UNISTD_H = !target_is_windows,
        .HAVE_PTHREAD = !target_is_windows,
        .SIZEOF_SIZE_T = @as(i64, target.result.ptrBitWidth() / 8),
        .DEFAULT_CHARSET = "utf8mb4",
        .MARIADB_PORT = 3306,
        .MARIADB_UNIX_ADDR = "/tmp/mysql.sock",
    },
);
```

### 第三步：按目标操作系统分拣源文件
根据操作系统分支，精准组织需要参与编译的 `.c` 源文件列表：

```zig
const common_sources = &.{
    "libmariadb/ma_client_plugin.c",
    "libmariadb/mariadb_charset.c",
    "libmariadb/mariadb_lib.c",
    "libmariadb/ma_time.c",
    "libmariadb/ma_default.c",
    "libmariadb/ma_errmsg.c",
};

const posix_sources = &.{
    "libmariadb/secure/openssl.c",
};

const windows_sources = &.{
    "libmariadb/secure/schannel.c",
};

// 根据操作系统差异添加源文件
c_module.addCSourceFiles(.{
    .root = upstream.path(""),
    .files = common_sources,
    .flags = c_flags,
});

if (target_is_windows) {
    c_module.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = windows_sources,
        .flags = c_flags,
    });
} else {
    c_module.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = posix_sources,
        .flags = c_flags,
    });
}
```

### 第四步：静态库构建与公共头文件树导出
上游导出的静态库必须同时提供完整的头文件树：

```zig
const lib = b.addLibrary(.{
    .name = "mariadb",
    .linkage = .static,
    .root_module = c_module,
});

// 1. 导出上游静态公共头文件目录
lib.installHeadersDirectory(upstream.path("include"), "mariadb", .{});

// 2. 导出动态生成的配置头文件
lib.installConfigHeader(config_h);

// 3. 安装暴露库产物
b.installArtifact(lib);
```

### 第五步：编写集成测试套件验证交付
在工程下建立独立的 `test/` 子工程，通过 `b.dependency("zig-mariadb-connector", ...)` 引入刚才构建的库产物，执行真实的 MySQL/MariaDB 握手与句柄初始化测试，确保跨平台符号与 ABI 完全兼容。

---

## 3. 移植要点与维护权衡

### 3.1 平台系统库链接

移植 C 库时，不同操作系统通常需要链接不同的底层系统库：
- **Windows 系统库**：涉及网络和加密时，通常需要链接 Winsock 与安全子系统：
  ```zig
  if (target_is_windows) {
      lib.linkSystemLibrary("ws2_32");
      lib.linkSystemLibrary("advapi32");
      lib.linkSystemLibrary("crypt32");
  }
  ```
- **POSIX 系统库**：在部分 Linux/BSD 环境下可能需要链接 `libpthread` 或 `libdl`。若通过 Zig 交叉编译，这些基础 libc 符号由内嵌环境统一管理。

### 3.2 上游变更的维护成本

用 `build.zig` 替代 CMake 虽然减少了对外部工具链的依赖，但也需要承担后续的同步成本：
- **缺乏自动化转写工具**：目前没有通用工具能够直接将复杂的 `CMakeLists.txt` 转换为 `build.zig`，源文件整理与宏配置主要依靠人工梳理；
- **上游版本同步成本**：当上游发布新版本并修改了源文件列表、宏名称或编译选项时，维护者需要比对上游 CMake 的变更并手动同步到 `build.zig`。对于频繁更新的大型项目，需要考虑这部分维护开销。
