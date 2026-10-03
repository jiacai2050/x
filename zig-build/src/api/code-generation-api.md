# 动态生成与模板配置：addConfigHeader 与 addWriteFiles

移植 C/C++ 库或构建复杂工程时，通常需要处理平台相关的配置文件（如 CMake 生成的 `config.h`），或者在构建期动态生成版本信息文件。Zig 标准库提供了对应的支持。

> 💡 **配套可运行示例**
> 本章中关于 `addConfigHeader`（CMake 模板渲染）和 `addWriteFiles`（动态源码生成）的完整可运行代码位于 GitHub：[`examples/03-code-generation`](https://github.com/jiacai2050/x/tree/main/zig-build/examples/03-code-generation)。
> 你可以进入该目录验证构建期代码生成：
> ```bash
> cd examples/03-code-generation
> zig build run
> ```

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

---

## 4. 内置生成机制与局限

### 4.1 减少外部运行时依赖

在传统 C/C++ 工程中，生成配置文件通常需要宿主机安装 Python 或 CMake。Zig 通过内置组件降低了对外部工具的依赖：
- **内置模板解析**：`addConfigHeader` 直接解析 `.h.in` 语法并完成宏替换，无需在宿主机安装 CMake；
- **工作区隔离**：动态生成的文件保存在 `.zig-cache/` 目录下，不会污染源码工作区。

### 4.2 局限与不足

1. **模板语法支持有限**：
   目前 `addConfigHeader` 主要支持常见的 CMake 宏模式（`#cmakedefine`、`#cmakedefine01`、`@VAR@`）。若第三方 C 库使用 Autotools 风格的 `config.h.in`（依赖 `#undef VAR` 替换等语法），通常需要先手动将其调整为兼容的模板格式；
2. **生成代码的报错定位问题**：
   使用 `b.addWriteFiles` 动态生成的 `.zig` 源码若存在语法或类型错误，编译器报错指向的是 `.zig-cache/o/<hash>/` 中的临时文件，无法直接跳转回 `build.zig` 中拼接该代码的具体行号，排查生成代码错误时不够直观。
