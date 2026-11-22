# Qianliyan (千里眼) — Roadmap & TODO

本文档记录 Qianliyan Web / Wasm 端的后续演进规划与优化项。

---

## 一、交互与功能对齐 (UX & Features)

- [ ] **SQL 查询历史记录 (Query History)**
  - 基于浏览器的 `localStorage` 记录最近成功执行的 SQL 语句（语句、执行时间、耗时）。
  - 在 SQL 编辑器上方提供历史记录弹窗/抽屉，支持一键点击回填，对齐 macOS 端 `HistorySheet` 体验。
- [ ] **表头快速排序与即时过滤 (Quick Sort & Filter)**
  - 表头列名支持点击循环切换排序（`默认` $\rightarrow$ `ASC` $\rightarrow$ `DESC`），自动联动生成并执行 `ORDER BY` 语句。
  - 增加可视数据快速搜索栏，支持针对当前视图按关键字即时过滤匹配行。
- [ ] **单元格长文本 / JSON / BLOB 详情查看器 (Cell Detail Modal)**
  - 支持双击单元格或点击查看单行完整字段内容，解决超长文本被截断、不易阅读的问题。
  - 对 JSON 文本自动 `JSON.parse` 缩进格式化高亮显示；对 BLOB 数据提供 Hex Dump（十六进制视图）与一键复制功能。

---

## 二、架构与性能优化 (Architecture & Performance)

- [ ] **Web Worker 线程隔离 (Web Worker Execution)**
  - 将 `@bjorn3/browser_wasi_shim` 与 `qianliyan.wasm` 迁移至独立的 Web Worker 中运行。
  - 主线程 UI 与 Wasm 执行环境完全解耦，大结果集解码与复杂计算不阻塞页面渲染与滚动（保持 120Hz 丝滑体验）。
  - 支持更稳健的长耗时查询取消（通过 Worker 消息触发 `db_interrupt` 或极端情况下 `terminate()`）。
- [ ] **OPFS (Origin Private File System) 持久化与超大库支持**
  - 利用现代浏览器的 OPFS（`FileSystemSyncAccessHandle`），配合 `browser_wasi_shim` 的 `OpenSyncOPFSFile`。
  - 替换现有的全量 `ArrayBuffer` 内存挂载方案，改为基于块级（block-based）按需读取，支持 GB 级超大 SQLite 文件在浏览器内秒级加载。
  - 数据库写入浏览器沙箱后持久保留，刷新页面无需重复选择或拖拽文件。

---

## 三、数据编辑扩展 (Data Mutation)

- [ ] **行级数据修改与删除 (Inline Editing)**
  - 利用现有 `db_get_schema_json` 返回的 `pk` 主键元数据。
  - 支持双击单元格直接就地修改值，按下回车自动生成并执行 `UPDATE "table" SET "col" = ? WHERE "pk" = ?`。
  - 支持行右键菜单快速删除行（生成 `DELETE` 语句执行），从只读查看器跃升为轻量级数据库管理工具。
