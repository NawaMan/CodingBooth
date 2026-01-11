// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package workspace

import (
	"fmt"
	"math/rand"
	"net"
	"os"
	"strconv"
	"strings"

	"github.com/nawaman/workspace/src/pkg/appctx"
)

// PortDetermination determines the host port and returns updated AppContext.
func PortDetermination(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	workspacePort := ctx.Port()
	upperPort := strings.ToUpper(workspacePort)
	portGenerated := false
	var portNumber int

	switch upperPort {
	case "RANDOM":
		// Generate random ports in increments of 1000 (10000, 11000, 12000, etc.)
		portNumber, portGenerated = findRandomPort()
		if !portGenerated {
			fmt.Fprintln(os.Stderr, "Error: unable to find a free RANDOM port above 10000.")
			os.Exit(1)
		}

	case "NEXT":
		// Find next available port starting from 10000 in increments of 1000
		portNumber, portGenerated = findNextPort()
		if !portGenerated {
			fmt.Fprintln(os.Stderr, "Error: unable to find the NEXT free port above 10000.")
			os.Exit(1)
		}

	default:
		// User-specified port: validate it
		port, err := strconv.Atoi(workspacePort)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: --port must be a number (got '%s').\n", workspacePort)
			os.Exit(1)
		}
		if port < 1 || port > 65535 {
			fmt.Fprintf(os.Stderr, "Error: --port must be between 1 and 65535 (got '%s').\n", workspacePort)
			os.Exit(1)
		}
		portNumber = port
		portGenerated = false
	}

	builder.PortNumber = portNumber
	builder.PortGenerated = portGenerated

	if (portGenerated || ctx.Verbose()) && ctx.Cmds().Length() == 0 {
		printPortBanner(portNumber)
	}

	return builder.Build()
}

// findRandomPort finds a random free port in increments of 1000.
func findRandomPort() (int, bool) {
	numSlots := (65000-10000)/1000 + 1 // 56 slots

	for i := 0; i < 200; i++ {
		slot := rand.Intn(numSlots)
		port := 10000 + (slot * 1000)
		if isPortFree(port) {
			return port, true
		}
	}

	return 0, false
}

// findNextPort finds the next free port starting from 10000 in increments of 1000.
func findNextPort() (int, bool) {
	for port := 10000; port <= 65535; port += 1000 {
		if isPortFree(port) {
			return port, true
		}
	}
	return 0, false
}

// isPortFree checks if a port is available.
func isPortFree(port int) bool {
	// Try to listen on the port
	addr := fmt.Sprintf(":%d", port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		// Port is in use
		return false
	}
	listener.Close()
	return true
}

// printPortBanner prints the port selection banner.
func printPortBanner(portNumber int) {
	fmt.Println()
	fmt.Println("============================================================")
	fmt.Println("🚀 WORKSPACE PORT SELECTED")
	fmt.Println("============================================================")
	fmt.Printf("🔌 Using host port: \033[1;32m%d\033[0m -> container: \033[1;34m10000\033[0m\n", portNumber)
	fmt.Printf("🌐 Open: http://localhost:%d\n", portNumber)
	fmt.Println("============================================================")
	fmt.Println()
}
