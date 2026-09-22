// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// tcpTunnel represents an active tunnel from a host port to a container port via `<engine> exec` + socat.
type tcpTunnel struct {
	containerPort int
	externalPort  int
	listener      net.Listener
	cancel        context.CancelFunc
}

// StartTcpTunnelWatcher watches .booth/.tmp/tcp-tunnels/ for control files
// and creates host-side TCP listeners that forward traffic via `<engine> exec` + socat
// to the container (the engine is the one the booth was started with). It runs until the provided context is cancelled.
func StartTcpTunnelWatcher(ctx context.Context, appCtx appctx.AppContext, containerName string) {
	codePath := appCtx.Code()
	if codePath == "" {
		return
	}

	tunnelDir := filepath.Join(codePath, ".booth", ".tmp", "tcp-tunnels")
	verbose := appCtx.Verbose()
	engine := appCtx.Engine()

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
				tunnel, err := startTunnel(ctx, engine, containerName, containerPort, externalPort, verbose)
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

func startTunnel(parentCtx context.Context, engine, containerName string, containerPort, externalPort int, verbose bool) (*tcpTunnel, error) {
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

	go acceptLoop(ctx, listener, engine, containerName, containerPort, verbose)

	return tunnel, nil
}

func acceptLoop(ctx context.Context, listener net.Listener, engine, containerName string, containerPort int, verbose bool) {
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
		go handleTunnelConn(ctx, conn, engine, containerName, containerPort, verbose)
	}
}

// tunnelExecCommand builds the `<engine> exec -i <container> socat …` process
// that carries one tunnelled connection. An empty engine means Docker.
func tunnelExecCommand(ctx context.Context, engine, containerName string, containerPort int) *exec.Cmd {
	if engine == "" {
		engine = "docker"
	}
	return exec.CommandContext(ctx, engine, "exec", "-i", containerName,
		"socat", "STDIO", fmt.Sprintf("TCP:localhost:%d", containerPort))
}

func handleTunnelConn(ctx context.Context, tcpConn net.Conn, engine, containerName string, containerPort int, verbose bool) {
	defer tcpConn.Close()

	cmd := tunnelExecCommand(ctx, engine, containerName, containerPort)
	cmd.Stdin = tcpConn
	cmd.Stdout = tcpConn
	if verbose {
		cmd.Stderr = os.Stderr
	}

	if err := cmd.Run(); err != nil {
		if verbose {
			fmt.Fprintf(os.Stderr, "  Tunnel exec error (port %d): %v\n", containerPort, err)
		}
	}
}
