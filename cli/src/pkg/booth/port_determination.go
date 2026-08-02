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
	"sync"

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
		var listener net.Listener
		portNumber, listener, portGenerated = findRandomPort(base)
		if !portGenerated {
			fmt.Fprintf(os.Stderr, "Error: unable to find a free RANDOM port at or above %d.\n", base)
			os.Exit(1)
		}
		holdPortReservation(listener)

	case "NEXT":
		// In dryrun mode, avoid binding sockets so tests remain deterministic in restricted environments.
		if ctx.Dryrun() {
			portNumber, portGenerated = base, true
			break
		}
		// Find next available port starting from base in increments of portScanStep.
		var listener net.Listener
		portNumber, listener, portGenerated = findNextPort(base)
		if !portGenerated {
			fmt.Fprintf(os.Stderr, "Error: unable to find the NEXT free port at or above %d.\n", base)
			os.Exit(1)
		}
		holdPortReservation(listener)

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

// portReservation holds the socket for the port NEXT / RANDOM picked, from the
// moment it is chosen until the container that publishes it is started.
//
// Without it, port selection was check-then-use: bind, close immediately, hand the
// number back — and only seconds later does `docker run -p 127.0.0.1:<port>` claim
// it. Everything in between (name resolution, sidecar startup, manifest writes)
// makes several docker calls, so the gap is roughly 1-3 seconds. NEXT hands every
// caller the *first* free port, so two booths starting together do not merely risk
// the same number, they are steered onto it, and the loser dies with
// "Bind for 127.0.0.1:<port> failed: port is already allocated" — exit 125 and no
// output at all, which is how this surfaced: as booths intermittently producing
// nothing under a parallel test run.
//
// Keeping the listener open makes the port genuinely busy for that whole window,
// so a second booth's scan skips it and moves to the next slot. It is released
// immediately before the port is published; see releasePortReservation.
var (
	portReservationMutex sync.Mutex
	portReservation      net.Listener
)

// findRandomPort finds a random free port at or above base in increments of portScanStep.
// The returned listener is a live reservation on that port; the caller owns it.
func findRandomPort(base int) (int, net.Listener, bool) {
	numSlots := (65000-base)/portScanStep + 1
	if numSlots < 1 {
		numSlots = 1
	}

	for i := 0; i < 200; i++ {
		port := base + (rand.Intn(numSlots) * portScanStep)
		if port > 65535 {
			continue
		}
		if listener, ok := reservePort(port); ok {
			return port, listener, true
		}
	}

	return 0, nil, false
}

// findNextPort finds the next free port at or above base in increments of portScanStep.
// The returned listener is a live reservation on that port; the caller owns it.
func findNextPort(base int) (int, net.Listener, bool) {
	for port := base; port <= 65535; port += portScanStep {
		if listener, ok := reservePort(port); ok {
			return port, listener, true
		}
	}
	return 0, nil, false
}

// reservePort takes a port for this booth, on both signals that matter: the socket
// itself, and the on-disk claim that covers the stretch where the socket has been
// handed to docker but docker has not bound it yet (see port_claim.go). On success
// the returned listener is still open and the claim is recorded.
func reservePort(port int) (net.Listener, bool) {
	// A booth already inside `docker run` for this port has closed its listener, so
	// the port reads as bindable. Only its claim reveals it.
	if portIsClaimed(port) {
		return nil, false
	}
	listener, ok := bindPort(port)
	if !ok {
		return nil, false
	}
	if !claimPort(port) {
		// Another booth claimed it between the check above and now.
		listener.Close()
		return nil, false
	}
	return listener, true
}

// bindPort binds the port and returns the still-open listener. A closed listener
// would only prove the port was free a moment ago; holding it open is what keeps
// the port ours until the container takes it.
//
// The probe binds 127.0.0.1, not the wildcard ":port", because that is the address
// the booth publishes on: `docker run -p 127.0.0.1:<port>:10000` (see
// formatPortMapping). It has to be the same address, or the scan does not measure
// what it thinks. On macOS/BSD a wildcard listener (with SO_REUSEADDR, which Go
// sets) can bind 0.0.0.0:<port> even while docker already holds 127.0.0.1:<port>,
// so probing the wildcard reported an occupied port as free — NEXT then handed it
// straight back and `docker run` died with "port is already allocated". Binding
// 127.0.0.1 instead fails whenever loopback OR the wildcard is already taken, on
// both macOS and Linux, which is exactly the conflict docker itself would hit.
func bindPort(port int) (net.Listener, bool) {
	addr := fmt.Sprintf("127.0.0.1:%d", port)
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		// Port is in use
		return nil, false
	}
	return listener, true
}

// isPortFree reports whether a port can be bound right now, releasing it again
// straight away. Only meaningful as an observation — use reservePort when the
// answer has to still be true a moment later.
func isPortFree(port int) bool {
	listener, ok := bindPort(port)
	if !ok {
		return false
	}
	listener.Close()
	return true
}

// holdPortReservation parks the reservation until the container is started,
// replacing (and closing) any reservation already held.
func holdPortReservation(listener net.Listener) {
	portReservationMutex.Lock()
	defer portReservationMutex.Unlock()
	if portReservation != nil && portReservation != listener {
		_ = portReservation.Close()
	}
	portReservation = listener
}

// releasePortReservation frees the held port so docker can bind it. It must be
// called before anything publishes the booth port — the booth container itself, or
// a DinD/egress sidecar that publishes it on the booth's behalf. Idempotent, and a
// no-op when no port was reserved (an explicit --port, or --dryrun).
func releasePortReservation() {
	portReservationMutex.Lock()
	defer portReservationMutex.Unlock()
	if portReservation != nil {
		_ = portReservation.Close()
		portReservation = nil
	}
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
