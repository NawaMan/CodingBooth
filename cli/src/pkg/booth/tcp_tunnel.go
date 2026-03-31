// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// tcpTunnel represents an active tunnel from a host port to a container port via WebSocket.
type tcpTunnel struct {
	containerPort int
	externalPort  int
	listener      net.Listener
	cancel        context.CancelFunc
}

// StartTcpTunnelWatcher watches .booth/.tmp/tcp-tunnels/ for control files
// and creates host-side TCP listeners that forward traffic via WebSocket to
// the container. It runs until the provided context is cancelled.
func StartTcpTunnelWatcher(ctx context.Context, appCtx appctx.AppContext) {
	codePath := appCtx.Code()
	if codePath == "" {
		return
	}

	tunnelDir := filepath.Join(codePath, ".booth", ".tmp", "tcp-tunnels")
	startupFile := filepath.Join(codePath, ".booth", ".tmp", "booth-startup.txt")

	boothPort := appCtx.PortNumber()
	verbose := appCtx.Verbose()

	var mu sync.Mutex
	activeTunnels := make(map[int]*tcpTunnel) // keyed by container port

	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			// Shutdown all tunnels
			mu.Lock()
			for _, t := range activeTunnels {
				t.cancel()
				t.listener.Close()
			}
			mu.Unlock()
			return

		case <-ticker.C:
			sessionID := readSessionID(startupFile)
			if sessionID == "" {
				continue
			}

			entries, err := os.ReadDir(tunnelDir)
			if err != nil {
				continue
			}

			// Track which ports have control files
			seen := make(map[int]bool)

			for _, entry := range entries {
				if entry.IsDir() {
					continue
				}

				containerPort, err := strconv.Atoi(entry.Name())
				if err != nil {
					continue
				}
				seen[containerPort] = true

				mu.Lock()
				_, exists := activeTunnels[containerPort]
				mu.Unlock()

				if exists {
					continue
				}

				// Read external port from control file
				data, err := os.ReadFile(filepath.Join(tunnelDir, entry.Name()))
				if err != nil {
					continue
				}
				externalPort, err := strconv.Atoi(strings.TrimSpace(string(data)))
				if err != nil {
					continue
				}

				// Start tunnel
				tunnel, err := startTunnel(ctx, boothPort, sessionID, containerPort, externalPort, verbose)
				if err != nil {
					fmt.Fprintf(os.Stderr, "  Tunnel error (port %d): %v\n", containerPort, err)
					continue
				}

				mu.Lock()
				activeTunnels[containerPort] = tunnel
				mu.Unlock()

				fmt.Fprintf(os.Stderr, "  Tunnel opened: localhost:%d -> container:%d\n", externalPort, containerPort)
			}

			// Remove tunnels whose control files are gone
			mu.Lock()
			for port, t := range activeTunnels {
				if !seen[port] {
					t.cancel()
					t.listener.Close()
					delete(activeTunnels, port)
					fmt.Fprintf(os.Stderr, "  Tunnel closed: localhost:%d -> container:%d\n", t.externalPort, port)
				}
			}
			mu.Unlock()
		}
	}
}

func readSessionID(startupFile string) string {
	data, err := os.ReadFile(startupFile)
	if err != nil {
		return ""
	}
	for _, line := range strings.Split(string(data), "\n") {
		if strings.HasPrefix(line, "session-id") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) == 2 {
				return strings.TrimSpace(parts[1])
			}
		}
	}
	return ""
}

func startTunnel(parentCtx context.Context, boothPort int, sessionID string, containerPort, externalPort int, verbose bool) (*tcpTunnel, error) {
	listener, err := net.Listen("tcp", fmt.Sprintf("localhost:%d", externalPort))
	if err != nil {
		return nil, fmt.Errorf("cannot listen on port %d: %w", externalPort, err)
	}

	ctx, cancel := context.WithCancel(parentCtx)

	tunnel := &tcpTunnel{
		containerPort: containerPort,
		externalPort:  externalPort,
		listener:      listener,
		cancel:        cancel,
	}

	wsPath := fmt.Sprintf("/tcp-tunnel-%s/%d", sessionID, containerPort)
	wsURL := url.URL{
		Scheme: "ws",
		Host:   fmt.Sprintf("localhost:%d", boothPort),
		Path:   wsPath,
	}

	go acceptLoop(ctx, listener, wsURL.String(), verbose)

	return tunnel, nil
}

func acceptLoop(ctx context.Context, listener net.Listener, wsURL string, verbose bool) {
	for {
		conn, err := listener.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return
			default:
				continue
			}
		}
		go handleTunnelConn(ctx, conn, wsURL, verbose)
	}
}

func handleTunnelConn(ctx context.Context, tcpConn net.Conn, wsURL string, verbose bool) {
	defer tcpConn.Close()

	dialer := websocket.Dialer{}
	wsConn, _, err := dialer.DialContext(ctx, wsURL, nil)
	if err != nil {
		if verbose {
			fmt.Fprintf(os.Stderr, "  Tunnel WS dial error: %v\n", err)
		}
		return
	}
	defer wsConn.Close()

	done := make(chan struct{}, 2)

	// TCP -> WS
	go func() {
		defer func() { done <- struct{}{} }()
		buf := make([]byte, 32*1024)
		for {
			n, err := tcpConn.Read(buf)
			if n > 0 {
				if werr := wsConn.WriteMessage(websocket.BinaryMessage, buf[:n]); werr != nil {
					return
				}
			}
			if err != nil {
				return
			}
		}
	}()

	// WS -> TCP
	go func() {
		defer func() { done <- struct{}{} }()
		for {
			_, reader, err := wsConn.NextReader()
			if err != nil {
				return
			}
			if _, err := io.Copy(tcpConn, reader); err != nil {
				return
			}
		}
	}()

	// Wait for either direction to finish
	select {
	case <-done:
	case <-ctx.Done():
	}
}
