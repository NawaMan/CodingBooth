// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"context"
	"net"
	"reflect"
	"strconv"
	"strings"
	"testing"
)

func TestTunnelExecCommand(t *testing.T) {
	tests := []struct {
		name     string
		engine   string
		wantArgs []string
	}{
		{"podman", "podman", []string{"podman", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
		{"docker", "docker", []string{"docker", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
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
