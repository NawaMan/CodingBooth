// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

func TestTunnelExecCommand(t *testing.T) {
	tests := []struct {
		name     string
		engine   string
		wantArgs []string
	}{
		{"podman", "podman", []string{"podman", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
		{"docker", "docker", []string{"docker", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
		{"apple runs the container binary", "apple", []string{"container", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
		{"unset engine means docker", "", []string{"docker", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := tunnelExecCommand(context.Background(), tt.engine, "mybooth", 8080)
			if !reflect.DeepEqual(cmd.Args, tt.wantArgs) {
				t.Errorf("tunnelExecCommand args = %v, want %v", cmd.Args, tt.wantArgs)
			}
		})
	}
}

func TestTunnelBindAddr(t *testing.T) {
	tests := []struct {
		name   string
		public bool
		want   string
	}{
		{"PublicBoothBindsEveryInterface", true, "0.0.0.0"},
		{"PrivateBoothStaysOnLoopback", false, "localhost"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tunnelBindAddr(tt.public); got != tt.want {
				t.Errorf("tunnelBindAddr(%t) = %q, want %q", tt.public, got, tt.want)
			}
		})
	}
}

// A public tunnel has to be reachable on an address other than loopback —
// that is the whole point of the flag. Dialling the listener over a non-loopback
// local address proves the bind actually took, rather than trusting the string.
func TestStartTunnelPublicIsReachableOffLoopback(t *testing.T) {
	port := freePort(t)

	tunnel, err := startTunnel(context.Background(), "", "no-such-container", 12345, port, "0.0.0.0", false)
	if err != nil {
		t.Fatalf("startTunnel public: %v", err)
	}
	defer func() {
		tunnel.cancel()
		tunnel.listener.Close()
	}()

	addr := tunnel.listener.Addr().String()
	if !strings.HasPrefix(addr, "0.0.0.0:") && !strings.HasPrefix(addr, "[::]:") {
		t.Errorf("listener bound to %q, want every interface", addr)
	}

	host := nonLoopbackIPv4(t)
	conn, err := net.Dial("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		t.Fatalf("public tunnel not reachable on %s: %v", host, err)
	}
	conn.Close()
}

func TestStartTunnelPrivateRefusesOffLoopback(t *testing.T) {
	port := freePort(t)

	tunnel, err := startTunnel(context.Background(), "", "no-such-container", 12345, port, "localhost", false)
	if err != nil {
		t.Fatalf("startTunnel private: %v", err)
	}
	defer func() {
		tunnel.cancel()
		tunnel.listener.Close()
	}()

	host := nonLoopbackIPv4(t)
	conn, err := net.Dial("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err == nil {
		conn.Close()
		t.Errorf("private tunnel accepted a connection on %s; it must stay on loopback", host)
	}
}

// An empty bind address must fall back to loopback, so a caller that forgets to
// pass one cannot accidentally publish a tunnel.
func TestStartTunnelDefaultsToLoopback(t *testing.T) {
	port := freePort(t)

	tunnel, err := startTunnel(context.Background(), "", "no-such-container", 12345, port, "", false)
	if err != nil {
		t.Fatalf("startTunnel default: %v", err)
	}
	defer func() {
		tunnel.cancel()
		tunnel.listener.Close()
	}()

	if addr := tunnel.listener.Addr().String(); !strings.HasPrefix(addr, "127.0.0.1:") && !strings.HasPrefix(addr, "[::1]:") {
		t.Errorf("listener bound to %q, want loopback", addr)
	}
}

func freePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("cannot find a free port: %v", err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	l.Close()
	return port
}

// runTunnelWatcher drives StartTcpTunnelWatcher for one tick against a control
// file requesting the given external port, capturing stderr. Same rationale as
// the "Waiting"/"Opened" fix (open_browser.go's foregroundPrefix): this
// goroutine's prints share the terminal with a concurrently-streamed foreground
// container, unsynchronized, so every one of them must carry the same guard.
func runTunnelWatcher(t *testing.T, foreground bool, externalPort int) string {
	t.Helper()
	return runTunnelWatcherFor(t, foreground, externalPort, 1500*time.Millisecond)
}

// runTunnelWatcherFor is runTunnelWatcher for as long as d: several ticks.
func runTunnelWatcherFor(t *testing.T, foreground bool, externalPort int, d time.Duration) string {
	t.Helper()

	codeDir := t.TempDir()
	tunnelDir := filepath.Join(codeDir, ".booth", ".tmp", "tcp-tunnels")
	if err := os.MkdirAll(tunnelDir, 0755); err != nil {
		t.Fatalf("mkdir tunnelDir: %v", err)
	}
	if err := os.WriteFile(filepath.Join(tunnelDir, "12345"), []byte(strconv.Itoa(externalPort)), 0644); err != nil {
		t.Fatalf("write control file: %v", err)
	}

	builder := &appctx.AppContextBuilder{}
	builder.Config.Code = nillable.NewNillableString(codeDir)
	ctx := builder.Build()

	oldStderr := os.Stderr
	reader, writer, err := os.Pipe()
	if err != nil {
		t.Fatalf("os.Pipe: %v", err)
	}
	os.Stderr = writer

	watchCtx, cancel := context.WithTimeout(context.Background(), d)
	defer cancel()
	StartTcpTunnelWatcher(watchCtx, ctx, "no-such-container", foreground)
	<-watchCtx.Done()

	writer.Close()
	os.Stderr = oldStderr

	var buf bytes.Buffer
	io.Copy(&buf, reader)
	return buf.String()
}

func TestStartTcpTunnelWatcher_ErrorLineGuardedInForeground(t *testing.T) {
	// Pre-occupy the port so the watcher's own bind fails, forcing the "Tunnel
	// error" line rather than "Tunnel opened".
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("cannot occupy a port: %v", err)
	}
	defer busy.Close()
	busyPort := busy.Addr().(*net.TCPAddr).Port

	out := runTunnelWatcher(t, true, busyPort)
	if !strings.Contains(out, "\n  Tunnel error") {
		t.Errorf("foreground=true: expected the error line prefixed with a guard newline, got: %q", out)
	}
}

func TestStartTcpTunnelWatcher_ErrorLineUnguardedOutsideForeground(t *testing.T) {
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("cannot occupy a port: %v", err)
	}
	defer busy.Close()
	busyPort := busy.Addr().(*net.TCPAddr).Port

	out := runTunnelWatcher(t, false, busyPort)
	if !strings.HasPrefix(out, "  Tunnel error") {
		t.Errorf("foreground=false: expected the error line with no leading guard newline, got: %q", out)
	}
}

func TestStartTcpTunnelWatcher_OpenedLineGuardedInForeground(t *testing.T) {
	out := runTunnelWatcher(t, true, freePort(t))
	if !strings.Contains(out, "\n  Tunnel opened") {
		t.Errorf("foreground=true: expected the opened line prefixed with a guard newline, got: %q", out)
	}
}

func TestStartTcpTunnelWatcher_OpenedLineUnguardedOutsideForeground(t *testing.T) {
	out := runTunnelWatcher(t, false, freePort(t))
	if !strings.HasPrefix(out, "  Tunnel opened") {
		t.Errorf("foreground=false: expected the opened line with no leading guard newline, got: %q", out)
	}
}

func nonLoopbackIPv4(t *testing.T) string {
	t.Helper()
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		t.Skipf("cannot list interfaces: %v", err)
	}
	for _, a := range addrs {
		if ipnet, ok := a.(*net.IPNet); ok && !ipnet.IP.IsLoopback() && ipnet.IP.To4() != nil {
			return ipnet.IP.String()
		}
	}
	t.Skip("no non-loopback IPv4 address on this machine")
	return ""
}

func TestStartTcpTunnelWatcher_ErrorPrintedOnceWhileUnchanged(t *testing.T) {
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("cannot occupy a port: %v", err)
	}
	defer busy.Close()
	busyPort := busy.Addr().(*net.TCPAddr).Port

	// About three ticks: the tunnel is retried each one, the error printed once.
	out := runTunnelWatcherFor(t, false, busyPort, 3500*time.Millisecond)
	if n := strings.Count(out, "Tunnel error"); n != 1 {
		t.Errorf("error printed %d times over several ticks, want once:\n%s", n, out)
	}
}

func TestTunnelErrorMessage(t *testing.T) {
	denied := fmt.Errorf("cannot listen on port 80: %w",
		&net.OpError{Op: "listen", Net: "tcp", Err: os.NewSyscallError("bind", syscall.EACCES)})
	inUse := fmt.Errorf("cannot listen on port 80: %w",
		&net.OpError{Op: "listen", Net: "tcp", Err: os.NewSyscallError("bind", syscall.EADDRINUSE)})

	got := tunnelErrorMessage(8080, 80, denied)
	if !strings.Contains(got, "Tunnel error (port 8080)") || !strings.Contains(got, "below 1024 need root") ||
		!strings.Contains(got, "booth--expose 8080 8080") {
		t.Errorf("denied low port: %q, want the error plus a hint suggesting booth--expose 8080 8080", got)
	}
	if got := tunnelErrorMessage(80, 443, denied); !strings.Contains(got, "booth--expose 80 8443") {
		t.Errorf("low container port: %q, want the suggestion 443+8000 = 8443", got)
	}
	if got := tunnelErrorMessage(8080, 80, inUse); strings.Contains(got, "need root") {
		t.Errorf("a port in use is not a permission problem: %q", got)
	}
	if got := tunnelErrorMessage(8080, 2000, denied); strings.Contains(got, "need root") {
		t.Errorf("a port of 1024 or above gets no low-port hint: %q", got)
	}
}
