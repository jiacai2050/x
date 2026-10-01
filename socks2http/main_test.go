package main

import (
	"bytes"
	"encoding/base64"
	"log"
	"net/http"
	"net/http/httptest"
	"regexp"
	"strconv"
	"testing"
)

// Regex matching standard Nginx combined log format:
// $remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent "$http_referer" "$http_user_agent"
var nginxCombinedRegex = regexp.MustCompile(`^(\S+) - (\S+) \[(\d{2}/\w{3}/\d{4}:\d{2}:\d{2}:\d{2} [+-]\d{4})\] "([^"]+)" (\d{3}) (\d+) "([^"]*)" "([^"]*)"\n$`)

func TestAccessLoggerFormat(t *testing.T) {
	var buf bytes.Buffer
	logger := &accessLogger{logger: log.New(&buf, "", 0)}

	req := httptest.NewRequest(http.MethodGet, "http://example.com/api/v1?foo=bar", nil)
	req.RemoteAddr = "192.168.1.100:54321"
	req.Header.Set("User-Agent", "curl/8.7.1")
	req.Header.Set("Referer", "https://news.ycombinator.com/")
	req.Header.Set("Proxy-Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte("alice:secret")))

	logger.Log(req, http.StatusOK, 1024)

	output := buf.String()
	matches := nginxCombinedRegex.FindStringSubmatch(output)
	if matches == nil {
		t.Fatalf("Log output does not match Nginx combined format: %q", output)
	}

	remoteAddr := matches[1]
	remoteUser := matches[2]
	timeLocal := matches[3]
	requestLine := matches[4]
	statusStr := matches[5]
	bytesSentStr := matches[6]
	referer := matches[7]
	userAgent := matches[8]

	if remoteAddr != "192.168.1.100" {
		t.Errorf("expected remoteAddr 192.168.1.100, got %q", remoteAddr)
	}
	if remoteUser != "alice" {
		t.Errorf("expected remoteUser alice, got %q", remoteUser)
	}
	if timeLocal == "" {
		t.Errorf("expected non-empty timeLocal")
	}
	if requestLine != "GET http://example.com/api/v1?foo=bar HTTP/1.1" {
		t.Errorf("expected requestLine 'GET http://example.com/api/v1?foo=bar HTTP/1.1', got %q", requestLine)
	}
	if statusStr != "200" {
		t.Errorf("expected status 200, got %q", statusStr)
	}
	if bytesSentStr != "1024" {
		t.Errorf("expected bytesSent 1024, got %q", bytesSentStr)
	}
	if referer != "https://news.ycombinator.com/" {
		t.Errorf("expected referer 'https://news.ycombinator.com/', got %q", referer)
	}
	if userAgent != "curl/8.7.1" {
		t.Errorf("expected userAgent 'curl/8.7.1', got %q", userAgent)
	}
}

func TestAccessLoggerDefaults(t *testing.T) {
	var buf bytes.Buffer
	logger := &accessLogger{logger: log.New(&buf, "", 0)}

	req := httptest.NewRequest(http.MethodConnect, "http://api.github.com:443", nil)
	req.RemoteAddr = "10.0.0.1:12345"

	logger.Log(req, http.StatusOK, 0)

	output := buf.String()
	matches := nginxCombinedRegex.FindStringSubmatch(output)
	if matches == nil {
		t.Fatalf("Log output does not match Nginx combined format: %q", output)
	}

	if matches[1] != "10.0.0.1" {
		t.Errorf("expected remoteAddr 10.0.0.1, got %q", matches[1])
	}
	if matches[2] != "-" {
		t.Errorf("expected remoteUser '-', got %q", matches[2])
	}
	if matches[5] != "200" {
		t.Errorf("expected status 200, got %q", matches[5])
	}
	if matches[6] != "0" {
		t.Errorf("expected bytesSent 0, got %q", matches[6])
	}
	if matches[7] != "-" {
		t.Errorf("expected referer '-', got %q", matches[7])
	}
	if matches[8] != "-" {
		t.Errorf("expected userAgent '-', got %q", matches[8])
	}
}

func TestGetAuthUser(t *testing.T) {
	tests := []struct {
		name     string
		header   string
		value    string
		expected string
	}{
		{
			name:     "no auth header",
			header:   "",
			value:    "",
			expected: "-",
		},
		{
			name:     "valid proxy authorization",
			header:   "Proxy-Authorization",
			value:    "Basic " + base64.StdEncoding.EncodeToString([]byte("bob:password")),
			expected: "bob",
		},
		{
			name:     "valid standard authorization fallback",
			header:   "Authorization",
			value:    "Basic " + base64.StdEncoding.EncodeToString([]byte("carol:secret")),
			expected: "carol",
		},
		{
			name:     "bearer token ignored",
			header:   "Authorization",
			value:    "Bearer eyJhbGciOi...",
			expected: "-",
		},
		{
			name:     "invalid base64",
			header:   "Proxy-Authorization",
			value:    "Basic !@#$%^&*",
			expected: "-",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "http://example.com/", nil)
			if tc.header != "" {
				req.Header.Set(tc.header, tc.value)
			}
			got := getAuthUser(req)
			if got != tc.expected {
				t.Errorf("expected auth user %q, got %q", tc.expected, got)
			}
		})
	}
}

func TestGetClientIP(t *testing.T) {
	tests := []struct {
		remoteAddr string
		expected   string
	}{
		{"127.0.0.1:8888", "127.0.0.1"},
		{"[::1]:54321", "::1"},
		{"192.168.1.1", "192.168.1.1"},
	}

	for _, tc := range tests {
		req := &http.Request{RemoteAddr: tc.remoteAddr}
		got := getClientIP(req)
		if got != tc.expected {
			t.Errorf("for %q, expected IP %q, got %q", tc.remoteAddr, tc.expected, got)
		}
	}
}

func TestResponseObserver(t *testing.T) {
	rec := httptest.NewRecorder()
	ro := &responseObserver{ResponseWriter: rec}

	ro.WriteHeader(http.StatusTeapot)
	if ro.status != http.StatusTeapot {
		t.Errorf("expected status %d, got %d", http.StatusTeapot, ro.status)
	}

	// Secondary call to WriteHeader should be a no-op
	ro.WriteHeader(http.StatusOK)
	if ro.status != http.StatusTeapot {
		t.Errorf("expected status %d after duplicate WriteHeader, got %d", http.StatusTeapot, ro.status)
	}

	n, err := ro.Write([]byte("short and stout"))
	if err != nil {
		t.Fatalf("unexpected write error: %v", err)
	}
	if n != 15 {
		t.Errorf("expected 15 bytes written, got %d", n)
	}
	if ro.bytesSent != 15 {
		t.Errorf("expected ro.bytesSent 15, got %d", ro.bytesSent)
	}
}

func TestServerAuthAccessLog(t *testing.T) {
	var buf bytes.Buffer
	logger := &accessLogger{logger: log.New(&buf, "", 0)}

	s := &server{
		authToken: "Basic " + base64.StdEncoding.EncodeToString([]byte("user:pass")),
		logger:    logger,
	}

	req := httptest.NewRequest(http.MethodGet, "http://example.com/secret", nil)
	req.RemoteAddr = "127.0.0.1:12345"
	rec := httptest.NewRecorder()

	s.ServeHTTP(rec, req)

	if rec.Code != http.StatusProxyAuthRequired {
		t.Errorf("expected status %d, got %d", http.StatusProxyAuthRequired, rec.Code)
	}

	output := buf.String()
	matches := nginxCombinedRegex.FindStringSubmatch(output)
	if matches == nil {
		t.Fatalf("Log output does not match Nginx combined format: %q", output)
	}

	status, _ := strconv.Atoi(matches[5])
	if status != http.StatusProxyAuthRequired {
		t.Errorf("expected logged status %d, got %d", http.StatusProxyAuthRequired, status)
	}
}

func TestNewAccessLoggerDestinations(t *testing.T) {
	lStdout, err := newAccessLogger("stdout")
	if err != nil || lStdout == nil || lStdout.logger == nil {
		t.Errorf("failed to create stdout logger: %v", err)
	}

	lStderr, err := newAccessLogger("stderr")
	if err != nil || lStderr == nil || lStderr.logger == nil {
		t.Errorf("failed to create stderr logger: %v", err)
	}

	lOff, err := newAccessLogger("off")
	if err != nil || lOff != nil {
		t.Errorf("expected nil logger for 'off', got %v (err: %v)", lOff, err)
	}
}
