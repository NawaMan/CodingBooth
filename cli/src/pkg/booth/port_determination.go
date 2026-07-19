// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"math/rand"
	"net"
	"os"
	"strconv"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// defaultPortBase is where NEXT / RANDOM start scanning when no ":base" is given.
const defaultPortBase = 10000

// portScanStep is the spacing between candidate ports scanned by NEXT / RANDOM.
const portScanStep = 1000

// PortDetermination determines the host port and returns updated AppContext.
func PortDetermination(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	boothPort := ctx.Port()
	keyword, base, err := parseSymbolicPort(boothPort)
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}
	portGenerated := false
	var portNumber int

	switch keyword {
	case "RANDOM":
		// In dryrun mode, avoid binding sockets so tests remain deterministic in restricted environments.
		if ctx.Dryrun() {
			portNumber, portGenerated = base, true
			break
		}
		// Generate random ports in increments of portScanStep from base (e.g. 10000, 11000, 12000, ...).
		portNumber, portGenerated = findRandomPort(base)
		if !portGenerated {
			fmt.Fprintf(os.Stderr, "Error: unable to find a free RANDOM port at or above %d.\n", base)
			os.Exit(1)
		}

	case "NEXT":
		// In dryrun mode, avoid binding sockets so tests remain deterministic in restricted environments.
		if ctx.Dryrun() {
			portNumber, portGenerated = base, true
			break
		}
		// Find next available port starting from base in increments of portScanStep.
		portNumber, portGenerated = findNextPort(base)
		if !portGenerated {
			fmt.Fprintf(os.Stderr, "Error: unable to find the NEXT free port at or above %d.\n", base)
			os.Exit(1)
		}

	default:
		// User-specified port: validate it
		port, err := strconv.Atoi(boothPort)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error: --port must be a number, NEXT[:base], or RANDOM[:base] (got '%s').\n", boothPort)
			os.Exit(1)
		}
		if port < 1 || port > 65535 {
			fmt.Fprintf(os.Stderr, "Error: --port must be between 1 and 65535 (got '%s').\n", boothPort)
			os.Exit(1)
		}
		portNumber = port
		portGenerated = false
	}

	builder.PortNumber = portNumber
	builder.PortGenerated = portGenerated

	if (portGenerated || portNumber != defaultPortBase || ctx.Verbose()) && ctx.Cmds().Length() == 0 {
		printPortBanner(portNumber, ctx.Public())
	}

	return builder.Build()
}

// parseSymbolicPort parses a NEXT / RANDOM port spec, optionally suffixed with
// ":base" to start scanning from a port other than the default. Examples:
//
//	NEXT          -> ("NEXT",   10000, nil)
//	NEXT:20000    -> ("NEXT",   20000, nil)
//	RANDOM:20000  -> ("RANDOM", 20000, nil)
//
// For a non-symbolic value (e.g. a literal number) it returns keyword "" and the
// caller treats the value as a fixed port. A malformed base returns an error.
func parseSymbolicPort(spec string) (keyword string, base int, err error) {
	name, rest, hasBase := strings.Cut(spec, ":")
	name = strings.ToUpper(name)
	if name != "NEXT" && name != "RANDOM" {
		return "", 0, nil
	}
	if !hasBase {
		return name, defaultPortBase, nil
	}
	b, convErr := strconv.Atoi(rest)
	if convErr != nil {
		return name, 0, fmt.Errorf("Error: --port %s base must be a number (got '%s').", name, rest)
	}
	if b < 1 || b > 65535 {
		return name, 0, fmt.Errorf("Error: --port %s base must be between 1 and 65535 (got '%s').", name, rest)
	}
	return name, b, nil
}

// findRandomPort finds a random free port at or above base in increments of portScanStep.
func findRandomPort(base int) (int, bool) {
	numSlots := (65000-base)/portScanStep + 1
	if numSlots < 1 {
		numSlots = 1
	}

	for i := 0; i < 200; i++ {
		port := base + (rand.Intn(numSlots) * portScanStep)
		if port > 65535 {
			continue
		}
		if isPortFree(port) {
			return port, true
		}
	}

	return 0, false
}

// findNextPort finds the next free port at or above base in increments of portScanStep.
func findNextPort(base int) (int, bool) {
	for port := base; port <= 65535; port += portScanStep {
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
func printPortBanner(portNumber int, public bool) {
	fmt.Println()
	LogPrintln("============================================================")
	LogPrintln("🚀 BOOTH PORT SELECTED")
	LogPrintln("============================================================")
	if public {
		LogPrintf("🔌 Using host port: \033[1;32m%d\033[0m -> container: \033[1;34m10443\033[0m (HTTPS)\n", portNumber)
		LogPrintf("🌐 Open: https://coder@localhost:%d\n", portNumber)
		LogPrintln("🔑 Login username: coder")
		LogPrintln("🔓 PUBLIC: PORT IS OPEN ON ALL INTERFACES (PASSWORD + HTTPS)")
	} else {
		LogPrintf("🔌 Using host port: \033[1;32m%d\033[0m -> container: \033[1;34m10000\033[0m\n", portNumber)
		LogPrintf("🌐 Open: http://localhost:%d\n", portNumber)
	}
	LogPrintln("============================================================")
	fmt.Println()
}
