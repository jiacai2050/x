# socks2http

[English](README.md) | [中文](README_zh.md)

基于 Go 语言实现的轻量级、高性能 SOCKS5 转 HTTP 代理服务。

`socks2http` 能够将上游的 SOCKS5 代理转换为标准的 HTTP 代理，使仅支持 HTTP/HTTPS 代理协议的工具、客户端和开发环境（如 `curl`、`git`、包管理器、各类 SDK 和浏览器等）可以无缝借由 SOCKS5 代理访问网络。

## 功能特性

- **HTTPS CONNECT 隧道**：完整支持 HTTP `CONNECT` 方法（基于 `http.Hijacker`），支持 HTTPS 和任意 TCP 流量透明转发，具备双向流拷贝及 TCP 半关闭（`CloseWrite`）正确处理能力。
- **标准 HTTP 转发**：符合 RFC 7230 规范的普通 HTTP 请求转发，支持绝对 URI 校验，自动过滤 Hop-by-Hop 逐跳请求头与响应头。
- **上游 SOCKS5 认证**：支持无缝连接上游 SOCKS5 代理，并可选提供用户名/密码鉴权（`proxy.Auth`）。
- **HTTP 代理认证保护**：可选开启代理自身的 Basic 认证（`Proxy-Authorization: Basic ...`），内部采用恒定时间比对（`crypto/subtle`）防范时序攻击。
- **Nginx 风格 Access Log**：支持输出标准 Nginx Combined 格式的访问日志（`$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"`），支持输出到 stdout、stderr、文件或禁用。
- **轻量无冗余依赖**：基于 Go 标准库和官方子仓库 `golang.org/x/net/proxy` 构建，内置连接池与 Context 超时控制，资源占用极低。

## 工作原理

```mermaid
%% Workflow of socks2http proxy
graph LR
    %% Subgraphs definition
    subgraph ClientZone [客户端区域]
        Client["客户端应用<br/>(curl / git / 浏览器等)"]
    end
    style ClientZone fill:#f9f9f9,stroke:#cccccc,stroke-width:2px

    subgraph ProxyCore [socks2http 核心]
        AuthCheck["代理认证检查<br/>(恒定时间比对)"]
        Router{"请求方法分发器"}
        ConnectTunnel["CONNECT 隧道处理<br/>(TCP 劫持与流转发)"]
        HttpForward["普通 HTTP 转发<br/>(过滤逐跳头)"]

        AuthCheck -- "认证通过" --> Router
        Router -- "CONNECT (HTTPS)" --> ConnectTunnel
        Router -- "普通 HTTP 请求" --> HttpForward
    end
    style ProxyCore fill:#e6f3ff,stroke:#0066cc,stroke-width:2px

    subgraph UpstreamZone [上游网络区域]
        SocksDialer["SOCKS5 上游拨号器"]
        SocksServer["SOCKS5 代理服务器"]
        TargetServer["目标服务器"]

        SocksDialer -- "SOCKS5 协议" --> SocksServer
        SocksServer -- "TCP 连接" --> TargetServer
    end
    style UpstreamZone fill:#fff0e6,stroke:#ff9900,stroke-width:2px

    %% Flow connections
    Client -- "HTTP / HTTPS 代理请求" --> AuthCheck
    ConnectTunnel -- "双向流数据转发" --> SocksDialer
    HttpForward -- "RoundTrip 请求转发" --> SocksDialer

    %% Class definitions
    classDef clientStyle fill:#f8f9fa,stroke:#495057,stroke-width:2px
    classDef coreStyle fill:#cce5ff,stroke:#0066cc,stroke-width:2px
    classDef upstreamStyle fill:#fff0e6,stroke:#ff9900,stroke-width:2px

    class Client clientStyle
    class AuthCheck,Router,ConnectTunnel,HttpForward coreStyle
    class SocksDialer,SocksServer,TargetServer upstreamStyle
```

## 安装与编译

### 前置条件

- [Go](https://go.dev/dl/) 1.20+（已在 Go 1.26 测试）

### 源码编译

```bash
# 进入 socks2http 目录
cd socks2http

# 编译可执行文件
make build
# 或: go build -o socks2http .
```

## 快速上手

### 1. 基础用法

监听本地 `127.0.0.1:8888`，将流量转发至上游 SOCKS5 代理 `127.0.0.1:1080`：

```bash
./socks2http -listen 127.0.0.1:8888 -socks 127.0.0.1:1080
```

### 2. 上游 SOCKS5 代理需要认证

若上游 SOCKS5 服务设置了用户名和密码：

```bash
./socks2http -listen 127.0.0.1:8888 -socks 10.0.0.1:1080 -socks-user myuser -socks-pass mypassword
```

### 3. 为 HTTP 代理开启认证保护

为本地 HTTP 代理服务配置 Basic 认证凭据：

```bash
./socks2http -listen 0.0.0.0:8888 -socks 127.0.0.1:1080 -auth admin:secret123
```

## 命令行参数

| 参数项        | 默认值           | 说明                                                       |
| :------------ | :--------------- | :--------------------------------------------------------- |
| `-listen`     | `127.0.0.1:8888` | HTTP 代理服务的监听地址及端口                              |
| `-socks`      | `127.0.0.1:1080` | 上游 SOCKS5 代理服务地址                                   |
| `-socks-user` | `""`             | 上游 SOCKS5 认证用户名（可选）                             |
| `-socks-pass` | `""`             | 上游 SOCKS5 认证密码（可选）                               |
| `-auth`       | `""`             | HTTP 代理自身的 Basic 认证，格式为 `user:pass`（可选）     |
| `-access-log` | `stdout`         | 访问日志输出目标：`stdout`、`stderr`、`off` 或指定文件路径 |

## 客户端配置与使用示例

### 使用 `curl` 验证

```bash
# 普通 HTTP 请求
curl -x http://127.0.0.1:8888 http://example.com

# HTTPS 请求（自动建立 CONNECT 隧道）
curl -x http://127.0.0.1:8888 https://httpbin.org/ip

# 带 HTTP 代理认证
curl -x http://admin:secret123@127.0.0.1:8888 https://httpbin.org/ip
```

### 终端环境变量配置

在终端中设置代理环境变量，供常用命令行工具使用：

```bash
export http_proxy="http://127.0.0.1:8888"
export https_proxy="http://127.0.0.1:8888"
export all_proxy="http://127.0.0.1:8888"

# 若开启了代理 Basic 认证
export http_proxy="http://admin:secret123@127.0.0.1:8888"
export https_proxy="http://admin:secret123@127.0.0.1:8888"
```

### Git 配置

配置 Git 走 HTTP 代理进行代码拉取与推送：

```bash
# 全局设置
git config --global http.proxy http://127.0.0.1:8888
git config --global https.proxy http://127.0.0.1:8888

# 取消设置
git config --global --unset http.proxy
git config --global --unset https.proxy
```
