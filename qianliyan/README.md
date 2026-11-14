# Qianliyan (千里眼)

<p align="center">
  <b>基于 Zig 核心引擎与 macOS 原生 GUI 的现代化数据库客户端</b>
</p>

---

## 📖 寓意 (Name Meaning)

**千里眼（Qianliyan）**，中国古代神话传说中能眼观千里、明察秋毫的神祇。

在浩瀚如烟海的数据库世界中，本项目取名 **Qianliyan**，寓意“**洞悉海量数据，结构秋毫毕现**”——用极速、安全、轻量的系统级内核，赋予用户洞察数据的千里之目。

---

## 🏛 核心架构哲学 (Architecture)

Qianliyan 采用 **“Zig Core 核心引擎 + 平台原生 GUI 宿主”** 的解耦架构：

```
┌────────────────────────────────────────────────────────┐
│               GUI 表现层 (macOS 原生 Swift/SwiftUI)       │
│  ┌──────────────────┐  ┌────────────────────────────┐  │
│  │   Sidebar View   │  │    Table / Results View    │  │
│  │  (Schema / Tree) │  │   (双向滚动、交替斑马纹)      │  │
│  └────────▲─────────┘  └─────────────▲──────────────┘  │
│           │                          │                 │
│           └──────────┬───────────────┘                 │
│                      │ Swift @Observable ViewModel     │
│                      │ (@MainActor UI Thread)          │
└──────────────────────┼─────────────────────────────────┘
                       │ C-ABI 模块桥接 (CQianliyan / dbcore.h)
┌──────────────────────▼─────────────────────────────────┐
│                 C-ABI 跨语言接口契约层                  │
│  db_open() / db_close() / db_query() / db_interrupt()  │
└──────────────────────┬─────────────────────────────────┘
                       │ 线程与内存边界
┌──────────────────────▼─────────────────────────────────┐
│                 Zig Core (通用跨平台核心)               │
│                                                        │
│  ┌───────────────────────────┐  ┌───────────────────┐  │
│  │    Async Worker Pool      │  │  Paging & Batch   │  │
│  │ (Worker Thread + Channel) │  │  Row Allocator    │  │
│  └─────────────┬─────────────┘  └───────────────────┘  │
│                │                                       │
│  ┌─────────────▼─────────────┐                         │
│  │    zig-sqlite (C API)     │                         │
│  │ (sqlite3_step / interrupt)│                         │
│  └───────────────────────────┘                         │
└────────────────────────────────────────────────────────┘
```

1. **Zig is Core**：
   - 数据库连接与驱动抽象（第一步完整支持 SQLite，后续无缝接入 PostgreSQL、MySQL 等）；
   - 动态列提取与全类型解析（`NULL`, `INTEGER`, `REAL`, `TEXT`, `BLOB`）；
   - 专属 `ArenaAllocator` 管理查询批次与结果集，通过 Zig 0.17 `SafeAllocator` 严苛测试，保证**零内存泄漏**；
   - 异步查询调度与底层长查询即时中断（`sqlite3_interrupt`）。
2. **Native Shell**：
   - macOS 端采用 Swift 6 + SwiftUI 原生渲染，极致轻量，自带原生暗黑模式、Liquid 材质与快捷键体验；
   - 核心层暴露纯 C-ABI，未来支持向 Windows (WinUI/DirectX) 与 Linux (GTK) 扩展。

---

## ✨ 当前特性 (Features)

- 🏠 **数据库连接首页（Recent Databases Home）**：启动即展示最近打开过的所有数据库卡片与访问时间，本地持久化记录，支持一键切换、Finder 定位与快速新建。
- ⚡ **原生极致流畅**：无 Electron 冗余开销，秒级启动，极低内存占用。
- 📑 **多标签页查询（Multi-Tab SQL Editor）**：支持打开多个 Query Tab，保护用户正在编写的复杂 SQL 不被覆盖。
- 🔍 **结构与 DDL/索引透视（Schema & DDL Inspector）**：左侧树状展示数据表，点击右侧 `(i)` 即可一键查看原生建表 DDL 与索引列表（INDEX）。
- 📊 **动态双向滚动数据表与自适应列宽**：吸顶表头、行号、NULL 倾斜标识，根据内容动态自适应列宽。
- 📋 **单元格与整行右键复制**：右键菜单直接复制单元格内容，或将整行一键复制为格式化 JSON / CSV。
- 💾 **一键数据导出（Export）**：支持将当前查询结果直接导出保存为 `.csv` 或 `.json` 文件。
- 📄 **分页控制（Pagination）**：支持上一页/下一页无缝翻页与每页条数（50 / 100 / 200 / 500）实时切换。
- 🕒 **查询历史（Query History）**：自动记录每次成功执行的 SQL、耗时与影响行数，支持一键载入或重放。
- 🛑 **长查询安全中断（Interrupt）**：耗时查询一键 Cancel，底层安全调用 `sqlite3_interrupt`。
- 🚀 **连接与配置管理**：支持快速打开已有 `.sqlite` / `.db` 数据库或创建新库，支持配置自定义别名并一键导入/导出连接配置。

---

## 🚀 快速开始 (Quick Start)

### 前置要求
- **macOS**：macOS 14.0+
- **Zig**：0.17.0+
- **Swift / Xcode**：Swift 5.9+ / Xcode Command Line Tools

### 编译与运行

在项目根目录下通过 `make` 即可完成全套构建：

```bash
# 1. 运行核心单元测试
make test

# 2. 编译 Zig 静态库与 Swift macOS 客户端
make macos

# 3. 启动 GUI 窗口
make run

# 4. 一键打包发布文件 (.app / .dmg / .zip)
make dist
```

打包完成后，产物位于 `dist/` 目录：
- `dist/Qianliyan.app`：标准已签名的 macOS 应用程序包
- `dist/Qianliyan.dmg`：带 `/Applications` 软链接的磁盘安装镜像（< 2MB）
- `dist/Qianliyan-macos-arm64.zip`：便携压缩包，适合上传 GitHub Releases

> **首次打开提示**：若未付费签名在非本机运行时收到系统“无法验证开发者”提示，请按住 `Control` 键右键点击应用图标并选择「打开」即可。

亦可直接在 `macos/` 目录下通过纯 Swift 命令操作：

```bash
cd macos
swift run
```

---

## 📂 项目结构 (Project Structure)

```
qianliyan/
├── Makefile                       # 统一构建入口 (make test, make macos, make run)
├── build.zig                      # Zig 构建配置 (生成 libqianliyan.a 静态库)
├── build.zig.zon                  # Zig 依赖管理 (锁定 zig-sqlite)
├── include/
│   └── dbcore.h                   # C-ABI 全局唯一头文件
├── src/
│   ├── types.zig                  # 通用数据库类型定义
│   ├── sqlite_driver.zig          # SQLite 动态驱动封装与纳秒计时器
│   ├── ffi.zig                    # C 导出层 (db_open, db_query, db_interrupt)
│   ├── root.zig                   # 核心库导出与集成测试
│   └── main.zig                   # Zig 命令行入口
└── macos/                         # Swift macOS 客户端工程
    ├── Package.swift              # SPM 清单
    └── Sources/
        ├── CQianliyan/            # Clang Module 桥接
        └── Qianliyan/             # SwiftUI 界面源码
            ├── App.swift          # 应用主入口
            ├── CoreBridge/        # Swift 异步 FFI 封装
            ├── ViewModels/        # 响应式状态管理 (@Observable)
            └── Views/             # 侧边栏、SQL 编辑器、结果集数据表
```

---

## 🗺 路线图 (Roadmap)

- [x] Zig Core 核心基础设施与 SQLite 动态驱动
- [x] C-ABI 导出与 Swift SPM 原生 GUI 双向打通
- [x] 查询结果集双向平滑滚动与实时性能耗时统计
- [x] 长查询中断支持 (`sqlite3_interrupt`)
- [x] 多标签页（Multi-tab）SQL 编辑器
- [x] 单元格与行右键复制（JSON / CSV）
- [x] 结果集导出（CSV / JSON）
- [x] 表格无缝分页与每页大小调节 (Pagination)
- [x] 查询历史记录面板 (Query History)
- [x] 原生查看建表 DDL 与索引列表透视
- [ ] 扩展支持 PostgreSQL、MySQL 核心驱动
- [ ] 跨平台前端探索（Windows / Linux）

---

## 📄 开源许可 (License)

MIT License.
