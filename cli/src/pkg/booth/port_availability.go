// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
)

// A booth port picked by NEXT/RANDOM, and every +OFFSET port that follows it, avoids
// what is already running. A port written as a plain number does not: a fixed
// `port = "10000"`, or an expose such as `-p 4566:4566`, is a contract, so a second
// booth of the same project — or anything else holding that port — makes `docker run`
// fail with "port is already allocated", which names neither the mapping nor a way out.
// CheckHostPortsFree asks the same question first and answers it with both.
//
// It is a check, not a reservation: a port that is free here can still be taken before
// docker binds it. Its job is the common case of a port held for minutes or hours by
// another booth or a host service.

// minProbePort is the lowest port probed. Below it, binding needs privileges this
// process may not have, so a failed bind would not mean the port is taken.
const minProbePort = 1024

// HostPortBusy is a fixed host port another process already holds.
type HostPortBusy struct {
	Port   int
	Raw    string // the mapping as written, or "" for the booth's own port
	Source string
}

// CheckHostPortsFree refuses to start a booth whose fixed host ports are already in use.
// It must run after ResolveRelativePorts and NormalizePortMappings, so every mapping is
// the concrete, deduped port it will claim.
func CheckHostPortsFree(ctx appctx.AppContext) appctx.AppContext {
	if ctx.Dryrun() {
		return ctx
	}
	// With DinD or egress a sidecar publishes the ports. One left from an earlier run of
	// this same name and port is reused as it is, and it holds these ports itself.
	if ctx.Dind() || ctx.Egress() {
		if taken, err := containerNameTaken(ctx, getEgressNetnsOwnerName(ctx)); err != nil || taken {
			return ctx
		}
	}

	busy := busyHostPorts(ctx, isPortFree)
	if len(busy) == 0 {
		return ctx
	}

	boothPort, expose := false, false
	for _, b := range busy {
		if b.Raw == "" {
			boothPort = true
			fmt.Fprintf(os.Stderr, "Error: booth port %d is already in use (%s).\n", b.Port, b.Source)
		} else {
			expose = true
			fmt.Fprintf(os.Stderr, "Error: host port %d is already in use — %q (%s).\n", b.Port, b.Raw, b.Source)
		}
	}
	fmt.Fprintln(os.Stderr, "Another booth, or another program, holds it, and a fixed port does not move. Either:")
	if boothPort {
		fmt.Fprintln(os.Stderr, "  - let booth pick a free booth port:     --port NEXT")
	}
	if expose {
		fmt.Fprintln(os.Stderr, "  - publish it relative to the booth port: +OFFSET:CONTAINER (e.g. -p +4566:4566)")
	}
	fmt.Fprintln(os.Stderr, "  - or stop what holds it ('booth list' shows booths — stop only one you started).")
	os.Exit(1)
	return ctx
}

// busyHostPorts is the decision half of CheckHostPortsFree: the fixed host ports this
// booth would bind that isFree reports as taken. Split out so it is testable without
// binding anything.
func busyHostPorts(ctx appctx.AppContext, isFree func(int) bool) []HostPortBusy {
	var busy []HostPortBusy
	seen := make(map[int]bool)

	probe := func(port int, raw, source string) {
		if port < minProbePort || seen[port] {
			return
		}
		seen[port] = true
		if !isFree(port) {
			busy = append(busy, HostPortBusy{Port: port, Raw: raw, Source: source})
		}
	}

	// A NEXT/RANDOM booth port is held by this process's own reservation, so it reads
	// as busy; it was chosen free, which is the point.
	if !ctx.PortGenerated() {
		probe(ctx.PortNumber(), "", "--port "+ctx.Port())
	}

	for _, m := range collectPortMappings(ctx.RunArgs(), "run-args") {
		if m.Relative || m.Proto != "tcp" {
			continue // a UDP port cannot be probed with a TCP bind
		}
		if !isWildcardIP(m.IP) && m.IP != "127.0.0.1" {
			continue // the probe binds 127.0.0.1, which says nothing about another address
		}
		if m.Host == ctx.PortNumber() {
			continue // NormalizePortMappings already refused a clash with the booth port
		}
		probe(m.Host, m.Raw, m.Source)
	}

	return busy
}
