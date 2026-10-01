# socks2http Context

这是一个极简、高性能的 SOCKS5 转 HTTP/HTTPS 代理工具。

## 项目愿景

核心目标是提供一个轻量级代理转换层：

- [x] **透明代理**: 将 SOCKS5 代理无缝转为 HTTP 代理，便于仅支持 HTTP 代理的工具（curl、git、包管理器等）使用。
- [x] **CONNECT 隧道**: 完整支持 HTTP CONNECT 隧道代理 HTTPS 与任意 TCP 流。
- [x] **标准 HTTP 转发**: 支持普通 HTTP 绝对 URI 代理并规范过滤逐跳头（Hop-by-Hop headers）。
- [x] **安全认证**: 支持上游 SOCKS5 账号密码认证及下游 HTTP 代理 Basic 认证（恒定时间防时序攻击）。
- [x] **轻量无依赖**: 仅依赖 Go 标准库与 `golang.org/x/net/proxy`。

## 架构概览

- **入口与参数**: `main.go` 中通过标准库 `flag` 解析 `-listen`、`-socks`、`-socks-user`、`-socks-pass`、`-auth`。
- **SOCKS5 Dialer**: 通过 `proxy.SOCKS5` 创建上游拨号器，若未实现 `proxy.ContextDialer` 则通过 `ctxDialerAdapter` 提供 Context 超时支持。
- **CONNECT 隧道**: 基于 `http.Hijacker` 劫持底层 TCP 连接，返回 `200 Connection Established` 后在两个 Goroutine 间双向 `io.Copy`，并对支持半关闭的连接调用 `CloseWrite`。
- **HTTP 转发**: 基于 `http.Transport`（配置上游 `DialContext`）进行 `RoundTrip`，进出均调用 `removeHopHeaders` 清理逐跳头。
- **认证逻辑**: 通过 `crypto/subtle.ConstantTimeCompare` 校验客户端 `Proxy-Authorization` 标头。
- **Access Log**: 仿 Nginx Combined 格式输出访问日志，通过 `responseObserver` 劫持 `WriteHeader`/`Write` 记录 HTTP 响应状态码及传输字节数，针对 CONNECT 隧道记录双向拷贝字节数与隧道状态。

## 运行配置

- **运行**: `go run . [flags]`
- **编译**: `go build -o socks2http .`
- **主要参数**:
  - `-listen`: 本地监听地址（默认 `127.0.0.1:8888`）
  - `-socks`: 上游 SOCKS5 地址（默认 `127.0.0.1:1080`）
  - `-socks-user` / `-socks-pass`: 上游 SOCKS5 认证凭据
  - `-auth`: HTTP 代理 Basic 认证（`user:pass` 格式）
  - `-access-log`: 访问日志输出目标（`stdout`、`stderr`、`off` 或文件路径，默认 `stdout`）
