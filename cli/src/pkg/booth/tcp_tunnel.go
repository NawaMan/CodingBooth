// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// tcpTunnel represents an active tunnel from a host port to a container port via `<engine> exec` + socat.
type tcpTunnel struct {
	containerPort int
	externalPort  int
	listener      net.Listener
	cancel        context.CancelFunc
}

// tunnelBindAddr is the host address tunnel listeners bind to: every interface
// for a public booth, loopback otherwise. It mirrors formatPortMapping's choice
// for the booth's own published port, so `-p` mappings and `booth--expose`
// tunnels agree about who can reach the booth.
func tunnelBindAddr(public bool) string {
	if public {
		return "0.0.0.0"
	}
	return "localhost"
}

// StartTcpTunnelWatcher watches .booth/.tmp/tcp-tunnels/ for control files
// and creates host-side TCP listeners that forward traffic via `<engine> exec` + socat
// to the container (the engine is the one the booth was started with). It runs until the
// provided context is cancelled.
//
// foreground marks whether this runs alongside a non-detached `docker run` whose own
// stdout/stderr streams straight to the terminal (runAsCommand/runAsForeground; never
// runAsDaemon, which detaches with -d) — see foregroundPrefix in open_browser.go for why
// every print below needs it: without it, one of this goroutine's lines can land wherever
// the container's own concurrent output left the cursor, not at the left margin.
func StartTcpTunnelWatcher(ctx context.Context, appCtx appctx.AppContext, containerName string, foreground bool) {
	codePath := appCtx.Code()
	if codePath == "" {
		return
	}

	tunnelDir := filepath.Join(codePath, ".booth", ".tmp", "tcp-tunnels")
	verbose := appCtx.Verbose()
	engine := appCtx.Engine()

	// A public booth tunnels publicly. Binding these to localhost while the
	// booth's own front door is on every interface makes `booth--expose`
	// unusable exactly where it is most wanted — a remote or hosted booth,
	// where "the host" is not the machine holding the browser.
	bindAddr := tunnelBindAddr(appCtx.Public())

	var mu sync.Mutex
	activeTunnels := make(map[int]*tcpTunnel) // keyed by container port
	// The last error printed per container port. A tunnel that cannot open is
	// retried every tick (the port may be freed), but its error is printed
	// once, not every second, until it changes.
	reported := make(map[int]string)

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
				tunnel, err := startTunnel(ctx, engine, containerName, containerPort, externalPort, bindAddr, verbose)
				if err != nil {
					if message := tunnelErrorMessage(containerPort, externalPort, err); reported[containerPort] != message {
						reported[containerPort] = message
						fmt.Fprint(os.Stderr, rawSafe(foregroundPrefix(foreground)+message, foreground))
					}
					continue
				}
				delete(reported, containerPort)

				mu.Lock()
				activeTunnels[containerPort] = tunnel
				mu.Unlock()

				fmt.Fprintf(os.Stderr, rawSafe(foregroundPrefix(foreground)+"  Tunnel opened: container:%d -> %s:%d\n", foreground), containerPort, bindAddr, externalPort)
			}

			// Forget errors of tunnels no longer asked for, so asking again reports again.
			for port := range reported {
				if !seen[port] {
					delete(reported, port)
				}
			}

			// Remove tunnels whose control files are gone
			mu.Lock()
			for port, t := range activeTunnels {
				if !seen[port] {
					t.cancel()
					t.listener.Close()
					delete(activeTunnels, port)
					fmt.Fprintf(os.Stderr, rawSafe(foregroundPrefix(foreground)+"  Tunnel closed: container:%d -> %s:%d\n", foreground), port, bindAddr, t.externalPort)
				}
			}
			mu.Unlock()
		}
	}
}

// tunnelErrorMessage is the line printed when a tunnel cannot open. Refused
// permission on a host port below 1024 gets a hint: an unprivileged user may
// not listen there — on macOS not on localhost even though 0.0.0.0 is allowed,
// on Linux not at all — and the tunnel deliberately binds localhost, not every
// interface. Pure for unit tests.
func tunnelErrorMessage(containerPort, externalPort int, err error) string {
	message := fmt.Sprintf("  Tunnel error (port %d): %v\n", containerPort, err)
	if externalPort < 1024 && errors.Is(err, syscall.EACCES) {
		message += fmt.Sprintf("  Host ports below 1024 need root on this machine; expose to a port of 1024 or above, e.g. booth--expose %d %d\n",
			containerPort, suggestedHostPort(containerPort, externalPort))
	}
	return message
}

// suggestedHostPort is a host port of 1024 or above for the hint: the
// container port itself when it is one, else the requested port + 8000
// (80 → 8080, 443 → 8443).
func suggestedHostPort(containerPort, externalPort int) int {
	if containerPort >= 1024 {
		return containerPort
	}
	return externalPort + 8000
}

func startTunnel(parentCtx context.Context, engine, containerName string, containerPort, externalPort int, bindAddr string, verbose bool) (*tcpTunnel, error) {
	if bindAddr == "" {
		bindAddr = "localhost"
	}
	listener, err := net.Listen("tcp", net.JoinHostPort(bindAddr, strconv.Itoa(externalPort)))
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
// that carries one tunnelled connection. An empty engine means Docker; apple
// runs `container`, whose `exec -i` takes the same arguments.
func tunnelExecCommand(ctx context.Context, engine, containerName string, containerPort int) *exec.Cmd {
	return exec.CommandContext(ctx, docker.EngineBinary(engine), "exec", "-i", containerName,
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
			fmt.Fprintf(os.Stderr, rawSafe("  Tunnel exec error (port %d): %v\n", true), containerPort, err)
		}
	}
}
