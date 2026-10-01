// socks2http: 将上游 SOCKS5 代理转换为 HTTP 代理（支持 CONNECT 隧道 / 普通 HTTP 请求）
//
// 用法:
//
//	go run . -listen 127.0.0.1:8080 -socks 127.0.0.1:1080
//	go run . -listen :8080 -socks 10.0.0.1:1080 -socks-user u -socks-pass p -auth user:pass
package main

import (
	"context"
	"crypto/subtle"
	"encoding/base64"
	"flag"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/proxy"
)

// 逐跳头，转发时需要移除
var hopHeaders = []string{
	"Connection",
	"Proxy-Connection",
	"Keep-Alive",
	"Proxy-Authenticate",
	"Proxy-Authorization",
	"Te",
	"Trailer",
	"Transfer-Encoding",
	"Upgrade",
}

type server struct {
	dialer    proxy.ContextDialer
	transport *http.Transport
	authToken string // 期望的 "Basic xxx"，为空表示不开启认证
}

// ctxDialerAdapter 用于上游 Dialer 不支持 DialContext 时的兜底
type ctxDialerAdapter struct{ proxy.Dialer }

func (a ctxDialerAdapter) DialContext(ctx context.Context, network, addr string) (net.Conn, error) {
	type result struct {
		c   net.Conn
		err error
	}
	ch := make(chan result, 1)
	go func() {
		c, err := a.Dial(network, addr)
		ch <- result{c, err}
	}()
	select {
	case <-ctx.Done():
		go func() {
			if r := <-ch; r.c != nil {
				r.c.Close()
			}
		}()
		return nil, ctx.Err()
	case r := <-ch:
		return r.c, r.err
	}
}

func newServer(socksAddr, socksUser, socksPass, httpAuth string) (*server, error) {
	var auth *proxy.Auth
	if socksUser != "" {
		auth = &proxy.Auth{User: socksUser, Password: socksPass}
	}
	d, err := proxy.SOCKS5("tcp", socksAddr, auth, &net.Dialer{Timeout: 10 * time.Second})
	if err != nil {
		return nil, err
	}
	cd, ok := d.(proxy.ContextDialer)
	if !ok {
		cd = ctxDialerAdapter{d}
	}

	s := &server{
		dialer: cd,
		transport: &http.Transport{
			Proxy:                 nil, // 不再走环境变量代理
			DialContext:           cd.DialContext,
			MaxIdleConns:          100,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: time.Second,
		},
	}
	if httpAuth != "" {
		s.authToken = "Basic " + base64.StdEncoding.EncodeToString([]byte(httpAuth))
	}
	return s, nil
}

func (s *server) checkAuth(r *http.Request) bool {
	if s.authToken == "" {
		return true
	}
	got := r.Header.Get("Proxy-Authorization")
	return subtle.ConstantTimeCompare([]byte(got), []byte(s.authToken)) == 1
}

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if !s.checkAuth(r) {
		w.Header().Set("Proxy-Authenticate", `Basic realm="socks2http"`)
		http.Error(w, "Proxy Authentication Required", http.StatusProxyAuthRequired)
		return
	}
	if r.Method == http.MethodConnect {
		s.handleConnect(w, r)
		return
	}
	s.handleHTTP(w, r)
}

// handleConnect 处理 HTTPS 等 CONNECT 隧道
func (s *server) handleConnect(w http.ResponseWriter, r *http.Request) {
	host := r.Host
	if _, _, err := net.SplitHostPort(host); err != nil {
		host = net.JoinHostPort(host, "443")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	remote, err := s.dialer.DialContext(ctx, "tcp", host)
	if err != nil {
		log.Printf("CONNECT %s: dial via socks failed: %v", host, err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer remote.Close()

	hj, ok := w.(http.Hijacker)
	if !ok {
		http.Error(w, "hijacking not supported", http.StatusInternalServerError)
		return
	}
	client, bufrw, err := hj.Hijack()
	if err != nil {
		log.Printf("CONNECT %s: hijack failed: %v", host, err)
		return
	}
	defer client.Close()

	if _, err := client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); err != nil {
		return
	}

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		// 使用 bufrw.Reader，避免丢失 Hijack 前已缓冲的数据
		io.Copy(remote, bufrw.Reader)
		closeWrite(remote)
	}()
	go func() {
		defer wg.Done()
		io.Copy(client, remote)
		closeWrite(client)
	}()
	wg.Wait()
}

func closeWrite(c net.Conn) {
	if cw, ok := c.(interface{ CloseWrite() error }); ok {
		cw.CloseWrite()
	} else {
		c.Close()
	}
}

// handleHTTP 处理普通 HTTP 代理请求（请求行为绝对 URI）
func (s *server) handleHTTP(w http.ResponseWriter, r *http.Request) {
	if !r.URL.IsAbs() || r.URL.Host == "" {
		http.Error(w, "This is a proxy server. Absolute URI required.", http.StatusBadRequest)
		return
	}

	out := r.Clone(r.Context())
	out.RequestURI = ""
	removeHopHeaders(out.Header)

	resp, err := s.transport.RoundTrip(out)
	if err != nil {
		log.Printf("%s %s: %v", r.Method, r.URL, err)
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()

	removeHopHeaders(resp.Header)
	for k, vv := range resp.Header {
		for _, v := range vv {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

func removeHopHeaders(h http.Header) {
	// 先移除 Connection 头里列出的自定义逐跳头
	for _, v := range h.Values("Connection") {
		for _, name := range strings.Split(v, ",") {
			if name = strings.TrimSpace(name); name != "" {
				h.Del(name)
			}
		}
	}
	for _, name := range hopHeaders {
		h.Del(name)
	}
}

func main() {
	listen := flag.String("listen", "127.0.0.1:8888", "HTTP 代理监听地址")
	socksAddr := flag.String("socks", "127.0.0.1:13659", "上游 SOCKS5 代理地址")
	socksUser := flag.String("socks-user", "", "上游 SOCKS5 用户名（可选）")
	socksPass := flag.String("socks-pass", "", "上游 SOCKS5 密码（可选）")
	httpAuth := flag.String("auth", "", "HTTP 代理 Basic 认证，格式 user:pass（可选）")
	flag.Parse()

	s, err := newServer(*socksAddr, *socksUser, *socksPass, *httpAuth)
	if err != nil {
		log.Fatalf("init: %v", err)
	}

	srv := &http.Server{
		Addr:              *listen,
		Handler:           s,
		ReadHeaderTimeout: 15 * time.Second,
	}
	log.Printf("HTTP proxy listening on %s -> SOCKS5 %s", *listen, *socksAddr)
	log.Fatal(srv.ListenAndServe())
}
