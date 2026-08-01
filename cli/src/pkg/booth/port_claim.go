// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// A port claim covers the one stretch the in-process reservation cannot: from the
// moment the listener is closed so docker may bind the port, until docker has
// actually bound it.
//
// The reservation in port_determination.go keeps a socket open on the chosen port,
// which is what stops a second booth from picking it while this one is still
// preparing. But docker cannot bind a port this process holds, so the listener has
// to be closed before `docker run` is invoked — and that call takes roughly 200ms
// to reach the networking step. In that window the port reads as free to everyone
// else, and a booth scanning right then takes it; one of the two then dies with
// "port is already allocated", exit 125 and no output.
//
// A claim is a file named after the port in a directory other booths can see, so
// the signal survives across processes. It is written when the port is chosen and
// removed once the container is up. A claim older than claimTTL is ignored, which
// is what stops a booth that was killed mid-launch from parking a port forever —
// the cost of a stale claim is only that one port gets skipped for a minute.
const claimTTL = 60 * time.Second

var (
	claimMutex sync.Mutex
	heldClaim  string // path of the claim this process owns ("" when none)
)

// portClaimDir is the directory booths publish their claims in. It lives under the
// temp dir so it needs no setup and survives nothing — claims are meaningless
// across a reboot.
func portClaimDir() string {
	return filepath.Join(os.TempDir(), "codingbooth-ports")
}

func portClaimPath(port int) string {
	return filepath.Join(portClaimDir(), fmt.Sprintf("%d.claim", port))
}

// portIsClaimed reports whether another booth is mid-launch on this port. A claim
// past its TTL is treated as absent and swept where permissions allow.
func portIsClaimed(port int) bool {
	path := portClaimPath(port)
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	if time.Since(info.ModTime()) > claimTTL {
		// Best effort: on a shared temp dir the file may belong to another user,
		// and failing to sweep it costs nothing but a skipped port.
		_ = os.Remove(path)
		return false
	}
	return true
}

// claimPort records this process's intent to publish port. It reports false only
// when another live booth holds the claim — if the registry itself is unusable
// (unwritable temp dir, read-only filesystem) it reports true, degrading to the
// in-process reservation rather than refusing to start a booth at all.
func claimPort(port int) bool {
	if err := os.MkdirAll(portClaimDir(), 0o777); err != nil {
		return true
	}
	path := portClaimPath(port)

	file, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
	if err != nil {
		if !os.IsExist(err) {
			return true // registry unusable — carry on unclaimed
		}
		if portIsClaimed(port) {
			return false // a live booth is launching on this port
		}
		// The claim was stale and portIsClaimed swept it; take it over. Losing this
		// second race means another booth got there first, so treat it as taken.
		file, err = os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
		if err != nil {
			return !os.IsExist(err)
		}
	}

	fmt.Fprintf(file, "%d\n", os.Getpid())
	_ = file.Close()

	claimMutex.Lock()
	heldClaim = path
	claimMutex.Unlock()
	return true
}

// releasePortClaim drops this process's claim. Called once the container is up, at
// which point the container itself holds the port and the claim has nothing left to
// protect. Idempotent, and a no-op when no port was claimed (an explicit --port, or
// --dryrun).
func releasePortClaim() {
	claimMutex.Lock()
	defer claimMutex.Unlock()
	if heldClaim != "" {
		_ = os.Remove(heldClaim)
		heldClaim = ""
	}
}
