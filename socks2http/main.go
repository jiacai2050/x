// socks2http: converts upstream SOCKS5 proxy to HTTP proxy (supports CONNECT tunnel and standard HTTP requests)
//
// Usage:
//
//	go run . -listen 127.0.0.1:8080 -socks 127.0.0.1:1080
//	go run . -listen :8080 -socks 10.0.0.1:1080 -socks-user u -socks-pass p -auth user:pass
package main

import (
	"bufio"
	"context"
	"crypto/subtle"
	"encoding/base64"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/proxy"
)

// Hop-by-hop headers to be removed when forwarding requests and responses
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

// accessLogger writes Nginx combined-format access logs using standard library log.Logger
type accessLogger struct {
	logger *log.Logger
	closer io.Closer
}

func newAccessLogger(target string) (*accessLogger, error) {
	target = strings.TrimSpace(target)
	switch strings.ToLower(target) {
	case "", "off", "none", "false":
		return nil, nil
	case "stdout":
		return &accessLogger{logger: log.New(os.Stdout, "", 0)}, nil
	case "stderr":
		return &accessLogger{logger: log.New(os.Stderr, "", 0)}, nil
	default:
		f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
		if err != nil {
			return nil, err
		}
		return &accessLogger{logger: log.New(f, "", 0), closer: f}, nil
	}
}

func (l *accessLogger) Close() error {
	if l == nil || l.closer == nil {
		return nil
	}
	return l.closer.Close()
}

func (l *accessLogger) Log(r *http.Request, status int, bytesSent int64) {
	if l == nil || l.logger == nil {
		return
	}

	clientIP := getClientIP(r)
	authUser := getAuthUser(r)
	timeLocal := time.Now().Format("02/Jan/2006:15:04:05 -0700")

	reqURI := r.RequestURI
	if reqURI == "" {
		if r.URL != nil {
			reqURI = r.URL.RequestURI()
			if reqURI == "" {
				reqURI = r.URL.String()
			}
		}
		if reqURI == "" {
			reqURI = r.Host
		}
	}
	proto := r.Proto
	if proto == "" {
		proto = "HTTP/1.1"
	}
	requestLine := fmt.Sprintf("%s %s %s", r.Method, reqURI, proto)

	referer := r.Referer()
	if referer == "" {
		referer = "-"
	}

	userAgent := r.UserAgent()
	if userAgent == "" {
		userAgent = "-"
	}

	// Format matching Nginx combined log format:
	// $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"
	l.logger.Printf("%s - %s [%s] %q %d %d %q %q",
		clientIP, authUser, timeLocal, requestLine, status, bytesSent, referer, userAgent)
}

func getClientIP(r *http.Request) string {
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func getAuthUser(r *http.Request) string {
	auth := r.Header.Get("Proxy-Authorization")
	if auth == "" {
		auth = r.Header.Get("Authorization")
	}
	if strings.HasPrefix(strings.ToLower(auth), "basic ") {
		payload, err := base64.StdEncoding.DecodeString(strings.TrimSpace(auth[6:]))
		if err == nil {
			if u, _, ok := strings.Cut(string(payload), ":"); ok && u != "" {
				return u
			}
		}
	}
	return "-"
}

// responseObserver captures HTTP status code and body bytes sent
type responseObserver struct {
	http.ResponseWriter
	status    int
	bytesSent int64
}

func (ro *responseObserver) WriteHeader(code int) {
	if ro.status == 0 {
		ro.status = code
		ro.ResponseWriter.WriteHeader(code)
	}
}

func (ro *responseObserver) Write(b []byte) (int, error) {
	if ro.status == 0 {
		ro.status = http.StatusOK
	}
	n, err := ro.ResponseWriter.Write(b)
	ro.bytesSent += int64(n)
	return n, err
}

func (ro *responseObserver) Hijack() (net.Conn, *bufio.ReadWriter, error) {
	if hj, ok := ro.ResponseWriter.(http.Hijacker); ok {
		return hj.Hijack()
	}
	return nil, nil, http.ErrNotSupported
}

func (ro *responseObserver) Flush() {
	if f, ok := ro.ResponseWriter.(http.Flusher); ok {
		f.Flush()
	}
}

func (ro *responseObserver) Unwrap() http.ResponseWriter {
	return ro.ResponseWriter
}

type server struct {
	dialer    proxy.ContextDialer
	transport *http.Transport
	authToken string // Expected "Basic xxx", empty means no auth required
	logger    *accessLogger
}

// ctxDialerAdapter provides fallback context support if upstream dialer lacks DialContext
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

func newServer(socksAddr, socksUser, socksPass, httpAuth string, logger *accessLogger) (*server, error) {
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
			Proxy:                 nil, // Do not use environment proxy
			DialContext:           cd.DialContext,
			MaxIdleConns:          100,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: time.Second,
		},
		logger: logger,
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
	ro := &responseObserver{ResponseWriter: w}
	defer func() {
		status := ro.status
		if status == 0 {
			status = http.StatusOK
		}
		if s.logger != nil {
			s.logger.Log(r, status, ro.bytesSent)
		}
	}()

	if !s.checkAuth(r) {
		ro.Header().Set("Proxy-Authenticate", `Basic realm="socks2http"`)
		http.Error(ro, "Proxy Authentication Required", http.StatusProxyAuthRequired)
		return
	}
	if r.Method == http.MethodConnect {
		s.handleConnect(ro, r)
		return
	}
	s.handleHTTP(ro, r)
}

// handleConnect handles HTTPS and arbitrary TCP streams via HTTP CONNECT tunneling
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
		if ro, ok := w.(*responseObserver); ok {
			ro.status = http.StatusInternalServerError
		}
		return
	}
	defer client.Close()

	if _, err := client.Write([]byte("HTTP/1.1 200 Connection Established\r\n\r\n")); err != nil {
		if ro, ok := w.(*responseObserver); ok {
			ro.status = http.StatusOK
		}
		return
	}
	if ro, ok := w.(*responseObserver); ok {
		ro.status = http.StatusOK
	}

	var bytesSent int64
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		// Use bufrw.Reader to avoid losing data buffered prior to hijack
		io.Copy(remote, bufrw.Reader)
		closeWrite(remote)
	}()
	go func() {
		defer wg.Done()
		n, _ := io.Copy(client, remote)
		bytesSent = n
		closeWrite(client)
	}()
	wg.Wait()

	if ro, ok := w.(*responseObserver); ok {
		ro.bytesSent = bytesSent
	}
}

func closeWrite(c net.Conn) {
	if cw, ok := c.(interface{ CloseWrite() error }); ok {
		cw.CloseWrite()
	} else {
		c.Close()
	}
}

// handleHTTP handles plain HTTP proxy requests (requires absolute URI)
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
	// Remove custom hop-by-hop headers specified in the Connection header first
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
	socksAddr := flag.String("socks", "127.0.0.1:1080", "上游 SOCKS5 代理地址")
	socksUser := flag.String("socks-user", "", "上游 SOCKS5 用户名（可选）")
	socksPass := flag.String("socks-pass", "", "上游 SOCKS5 密码（可选）")
	httpAuth := flag.String("auth", "", "HTTP 代理 Basic 认证，格式 user:pass（可选）")
	accessLog := flag.String("access-log", "stdout", "Access log 输出目标：stdout、stderr、off 或文件路径")
	flag.Parse()

	logger, err := newAccessLogger(*accessLog)
	if err != nil {
		log.Fatalf("access log init: %v", err)
	}
	if logger != nil {
		defer logger.Close()
	}

	s, err := newServer(*socksAddr, *socksUser, *socksPass, *httpAuth, logger)
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
