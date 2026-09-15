// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"net"
	"strings"
	"testing"
)

func TestResolveListenPort(t *testing.T) {
	tests := []struct {
		name string
		flag string
		want int
	}{
		{"empty uses the default booth port", "", 10000},
		{"numeric port is used as-is", "18000", 18000},
		{"NEXT is a booth token, not a listen port", "NEXT", 10000},
		{"RANDOM is a booth token, not a listen port", "RANDOM", 10000},
		{"zero is not a host port", "0", 10000},
		{"out of range falls back", "70000", 10000},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := ResolveListenPort(tt.flag); got != tt.want {
				t.Fatalf("ResolveListenPort(%q) = %d, want %d", tt.flag, got, tt.want)
			}
		})
	}
}

func TestListenLoopback_RefusesATakenPort(t *testing.T) {
	held, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer held.Close()
	port := held.Addr().(*net.TCPAddr).Port

	_, err = ListenLoopback(port)
	if err == nil {
		t.Fatal("expected in-use error")
	}
	if !strings.Contains(err.Error(), "already in use") {
		t.Fatalf("error = %v, want already in use", err)
	}
}

func TestListenLoopback_BindsLoopbackOnly(t *testing.T) {
	listener, err := ListenLoopback(0)
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	addr := listener.Addr().(*net.TCPAddr)
	if !addr.IP.IsLoopback() {
		t.Fatalf("bound %v, want loopback", addr.IP)
	}
}
