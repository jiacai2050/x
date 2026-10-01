# socks2http

[English](README.md) | [中文](README_zh.md)

A lightweight, high-performance SOCKS5-to-HTTP proxy server written in Go.

`socks2http` converts an upstream SOCKS5 proxy into a standard HTTP proxy, allowing applications, CLI tools, and development environments that only support HTTP/HTTPS proxies (such as `curl`, `git`, package managers, SDKs, and web browsers) to seamlessly route traffic through your SOCKS5 proxy.

## Features

- **HTTPS CONNECT Tunneling**: Full support for the HTTP `CONNECT` method (`http.Hijacker`) for tunneling HTTPS and arbitrary TCP connections, with bi-directional streaming and TCP half-close (`CloseWrite`) handling.
- **Standard HTTP Proxying**: RFC 7230 compliant plain HTTP request forwarding with absolute URI validation and automatic hop-by-hop headers removal.
- **Upstream SOCKS5 Support**: Seamless upstream SOCKS5 integration, including optional username/password authentication (`proxy.Auth`).
- **HTTP Proxy Authentication**: Optional Basic Authentication protection (`Proxy-Authorization: Basic ...`) evaluated using constant-time comparison (`crypto/subtle`) against timing attacks.
- **Lightweight & Efficient**: Built on the Go standard library and `golang.org/x/net/proxy` with context-aware timeouts, connection pooling, and minimal resource usage.

## How It Works

```mermaid
%% Workflow of socks2http proxy
graph LR
    %% Subgraphs definition
    subgraph ClientZone [Client Area]
        Client["Client Application<br/>(curl / git / browser)"]
    end
    style ClientZone fill:#f9f9f9,stroke:#cccccc,stroke-width:2px

    subgraph ProxyCore [socks2http Service]
        AuthCheck["Proxy Auth Check<br/>(Constant-Time)"]
        Router{"Method Dispatcher"}
        ConnectTunnel["CONNECT Handler<br/>(TCP Tunneling & Hijack)"]
        HttpForward["HTTP Handler<br/>(Hop Headers Removal)"]

        AuthCheck -- "Authorized" --> Router
        Router -- "CONNECT (HTTPS)" --> ConnectTunnel
        Router -- "Plain HTTP" --> HttpForward
    end
    style ProxyCore fill:#e6f3ff,stroke:#0066cc,stroke-width:2px

    subgraph UpstreamZone [Upstream Network]
        SocksDialer["SOCKS5 Context Dialer"]
        SocksServer["SOCKS5 Server"]
        TargetServer["Remote Target Server"]

        SocksDialer -- "SOCKS5 Protocol" --> SocksServer
        SocksServer -- "TCP Connection" --> TargetServer
    end
    style UpstreamZone fill:#fff0e6,stroke:#ff9900,stroke-width:2px

    %% Flow connections
    Client -- "HTTP / HTTPS Request" --> AuthCheck
    ConnectTunnel -- "Bi-directional Stream" --> SocksDialer
    HttpForward -- "RoundTrip (DialContext)" --> SocksDialer

    %% Class definitions
    classDef clientStyle fill:#f8f9fa,stroke:#495057,stroke-width:2px
    classDef coreStyle fill:#cce5ff,stroke:#0066cc,stroke-width:2px
    classDef upstreamStyle fill:#fff0e6,stroke:#ff9900,stroke-width:2px

    class Client clientStyle
    class AuthCheck,Router,ConnectTunnel,HttpForward coreStyle
    class SocksDialer,SocksServer,TargetServer upstreamStyle
```

## Installation & Build

### Prerequisites

- [Go](https://go.dev/dl/) 1.20+ (tested on Go 1.26)

### Build from source

```bash
# Clone the repository and navigate to socks2http
cd socks2http

# Build the executable
go build -o socks2http .
```

## Quick Start

### 1. Basic Usage

Start the HTTP proxy listening on `127.0.0.1:8888`, forwarding traffic to an upstream SOCKS5 proxy at `127.0.0.1:1080`:

```bash
./socks2http -listen 127.0.0.1:8888 -socks 127.0.0.1:1080
```

### 2. With Upstream SOCKS5 Authentication

If your upstream SOCKS5 server requires authentication:

```bash
./socks2http -listen 127.0.0.1:8888 -socks 10.0.0.1:1080 -socks-user myuser -socks-pass mypassword
```

### 3. With HTTP Proxy Authentication

Protect your HTTP proxy endpoint with Basic Authentication:

```bash
./socks2http -listen 0.0.0.0:8888 -socks 127.0.0.1:1080 -auth admin:secret123
```

## Command Line Options

| Flag          | Default           | Description                                                      |
| :------------ | :---------------- | :--------------------------------------------------------------- |
| `-listen`     | `127.0.0.1:8888`  | Address and port for the HTTP proxy server to listen on          |
| `-socks`      | `127.0.0.1:13659` | Upstream SOCKS5 proxy server address                             |
| `-socks-user` | `""`              | Username for upstream SOCKS5 authentication (optional)           |
| `-socks-pass` | `""`              | Password for upstream SOCKS5 authentication (optional)           |
| `-auth`       | `""`              | HTTP Proxy Basic authentication in `user:pass` format (optional) |

## Client Configuration & Examples

### Using `curl`

```bash
# Standard HTTP request
curl -x http://127.0.0.1:8888 http://example.com

# HTTPS request (uses HTTP CONNECT tunnel)
curl -x http://127.0.0.1:8888 https://httpbin.org/ip

# With HTTP proxy authentication
curl -x http://admin:secret123@127.0.0.1:8888 https://httpbin.org/ip
```

### Environment Variables

Set environment variables in your terminal for applications that respect proxy settings:

```bash
export http_proxy="http://127.0.0.1:8888"
export https_proxy="http://127.0.0.1:8888"
export all_proxy="http://127.0.0.1:8888"

# If proxy authentication is enabled
export http_proxy="http://admin:secret123@127.0.0.1:8888"
export https_proxy="http://admin:secret123@127.0.0.1:8888"
```

### Git

Configure Git to route HTTP/HTTPS traffic through the proxy:

```bash
# Global configuration
git config --global http.proxy http://127.0.0.1:8888
git config --global https.proxy http://127.0.0.1:8888

# Unset when no longer needed
git config --global --unset http.proxy
git config --global --unset https.proxy
```
