# 动态生成与模板配置：addConfigHeader 与 addWriteFiles

移植 C/C++ 库或构建复杂工程时，通常需要处理平台相关的配置文件（如 CMake 生成的 `config.h`），或者在构建期动态生成版本信息文件。Zig 标准库提供了对应的支持。

---

## 1. 配置头文件生成：`b.addConfigHeader`

在 C/C++ 项目中，常使用 CMake 的 `configure_file(config.h.in config.h)` 根据环境替换宏定义。在 Zig 中可以通过 `b.addConfigHeader` 实现类似功能：

### 示例用法：

```zig
// 1. 声明 ConfigHeader 步骤
const config_h = b.addConfigHeader(
    .{
        .style = .{ .cmake = b.path("include/config.h.in") },
        .include_path = "config.h",
    },
    .{
        // 布尔值：生成 #define HAVE_UNISTD_H 1 或 /* #undef HAVE_UNISTD_H */
        .HAVE_UNISTD_H = target.result.os.tag != .windows,
        .HAVE_PTHREAD = true,

        // 数值类型
        .SIZEOF_SIZE_T = @as(i64, target.result.ptrBitWidth() / 8),

        // 字符串：生成 #define DEFAULT_CHARSET "utf8mb4"
        .DEFAULT_CHARSET = "utf8mb4",
    },
);

// 2. 安装到库产物中，或作为包含路径传递给下游模块
lib.installConfigHeader(config_h);
```

### 核心特性：
- **支持 CMake 模板语法**：`.cmake` 样式支持解析 `#cmakedefine VAR`、`#cmakedefine01 VAR` 和 `@VAR@`，并替换为对应的 C 宏定义；
- **类型校验**：键值对通过匿名结构体传入，编译器在配置阶段进行类型检查。

---

## 2. 动态写入文件：`b.addWriteFiles`

当构建过程中需要生成源代码、聚合头文件或版本信息时，可以使用 `b.addWriteFiles`。

### 场景一：生成构建期版本与元数据
```zig
const write_files = b.addWriteFiles();

const version_zig = write_files.add("version.zig", b.fmt(
    \\pub const app_name = "CodegenDemo";
    \\pub const version = "{s}";
    \\pub const build_mode = "{s}";
    ,
    .{ "1.0.0", @tagName(optimize) },
));

// 作为内部模块提供给主程序使用
const version_mod = b.createModule(.{
    .root_source_file = version_zig,
});
exe.root_module.addImport("version", version_mod);
```

### 场景二：为 `addTranslateC` 聚合多个分散头文件
当第三方库有多个分散的头文件需要集中转译时，可动态生成一个入口头文件：

```zig
const bundle_h = b.addWriteFiles().add("bundle.h",
    \\#include <foo.h>
    \\#include <foo_error.h>
);

const translate_c = b.addTranslateC(.{
    .root_source_file = bundle_h,
    .target = target,
    .optimize = optimize,
});
```

---

## 3. 使用 `LazyPath` 生成文件的优势

使用 `b.addWriteFiles` 和 `b.addConfigHeader` 生成的文件路径均为 `LazyPath`：
1. **支持增量缓存**：仅当输入模板内容或键值发生变动时，才会在执行期重新生成文件；
2. **时序安全**：生成物存放在 `.zig-cache/` 的哈希隔离目录下，不污染源码工作区，并能通过数据流自动向消费步骤传递依赖关系。
