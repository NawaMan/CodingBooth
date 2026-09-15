// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package configweb

import (
	"fmt"
	"net"
	"strconv"
	"strings"
)

// defaultBoothPort is the host port a booth serves on when none is configured.
// The Web UI binds the same number so configure and run share one address.
const defaultBoothPort = 10000

// ResolveListenPort picks the loopback port for the config Web UI.
//
// A numeric --port / config.toml port is used as-is. Empty, NEXT, RANDOM, and
// anything else that is not a host port fall back to 10000 — those tokens are
// for a running booth, not for a file-generation server.
func ResolveListenPort(portFlag string) int {
	trimmed := strings.TrimSpace(portFlag)
	port, err := strconv.Atoi(trimmed)
	if err != nil || port <= 0 || port > 65535 {
		return defaultBoothPort
	}
	return port
}

// ListenLoopback binds 127.0.0.1:port. The config UI writes .booth/, so it is
// never exposed on 0.0.0.0.
func ListenLoopback(port int) (net.Listener, error) {
	listener, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return nil, fmt.Errorf("booth port %d is already in use (is a booth running? stop it, or pass --port)", port)
	}
	return listener, nil
}
