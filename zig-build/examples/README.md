# Zig 构建系统实战示例项目

本目录包含了《Zig 构建系统权威指南》书中介绍的全部可独立编译、运行与测试的示例工程。

## 示例清单

| 目录 | 说明 | 运行与测试指令 |
| :--- | :--- | :--- |
| [`01-zig-app`](./01-zig-app/) | 标准纯 Zig CLI 应用程序与测试套件 | `zig build run` / `zig build test` |
| [`02-mixed-c-zig`](./02-mixed-c-zig/) | Zig 与 C 语言源码混合编译与 `addTranslateC` | `zig build run` |
| [`03-code-generation`](./03-code-generation/) | `addConfigHeader` 模板渲染与 `addWriteFiles` 动态生成代码 | `zig build run` |
| [`04-c-library-port`](./04-c-library-port/) | 复杂 C 静态库封装与下游子工程集成测试 | `zig build test` |
| [`05-custom-step`](./05-custom-step/) | 实现自定义发行包归档 Step（tar.gz 打包）并接入构建 DAG | `zig build pack` / `zig build run` |

## 一键运行全部示例

在项目根目录下执行：

```bash
make test-examples
```
