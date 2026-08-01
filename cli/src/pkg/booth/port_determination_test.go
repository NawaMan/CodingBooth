// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"net"
	"os"
	"testing"
	"time"
)

func TestParseSymbolicPort(t *testing.T) {
	tests := []struct {
		spec        string
		wantKeyword string
		wantBase    int
		wantErr     bool
	}{
		{"NEXT", "NEXT", 10000, false},
		{"next", "NEXT", 10000, false}, // case-insensitive keyword
		{"RANDOM", "RANDOM", 10000, false},
		{"NEXT:20000", "NEXT", 20000, false},
		{"RANDOM:20000", "RANDOM", 20000, false},
		{"NEXT:20500", "NEXT", 20500, false}, // base need not be 1000-aligned
		{"NEXT:1", "NEXT", 1, false},
		{"NEXT:65535", "NEXT", 65535, false},
		// non-symbolic -> keyword "" so the caller treats it as a literal port
		{"8080", "", 0, false},
		{"", "", 0, false},
		// malformed bases
		{"NEXT:abc", "NEXT", 0, true},
		{"NEXT:0", "NEXT", 0, true},
		{"NEXT:70000", "NEXT", 0, true},
		{"RANDOM:-5", "RANDOM", 0, true},
	}

	for _, tt := range tests {
		t.Run(tt.spec, func(t *testing.T) {
			kw, base, err := parseSymbolicPort(tt.spec)
			if (err != nil) != tt.wantErr {
				t.Fatalf("parseSymbolicPort(%q) err = %v, wantErr %v", tt.spec, err, tt.wantErr)
			}
			if kw != tt.wantKeyword {
				t.Errorf("parseSymbolicPort(%q) keyword = %q, want %q", tt.spec, kw, tt.wantKeyword)
			}
			if !tt.wantErr && base != tt.wantBase {
				t.Errorf("parseSymbolicPort(%q) base = %d, want %d", tt.spec, base, tt.wantBase)
			}
		})
	}
}

func TestFindNextPort_SkipsOccupied(t *testing.T) {
	// Hold the base and the very next slot open, so the scan must skip BOTH occupied
	// ports and land on base+2*step. Uses an OS-assigned base so no fixed port is
	// assumed free.
	lnBase, err := net.Listen("tcp", ":0")
	if err != nil {
		t.Skipf("could not bind an ephemeral port: %v", err)
	}
	defer lnBase.Close()
	base := lnBase.Addr().(*net.TCPAddr).Port
	if base+2*portScanStep > 65535 {
		t.Skipf("ephemeral base %d too high for this test", base)
	}

	// Occupy base+step too. If it happens to be taken already, that only reinforces
	// the "must skip" expectation, so a bind failure here is not fatal.
	if lnNext, err := net.Listen("tcp", fmt.Sprintf(":%d", base+portScanStep)); err == nil {
		defer lnNext.Close()
	}

	got, reservation, ok := findNextPort(base)
	if !ok {
		t.Fatal("findNextPort returned no free port")
	}
	if got < base+2*portScanStep {
		t.Errorf("findNextPort(%d) = %d, expected it to skip the two occupied ports (>= %d)", base, got, base+2*portScanStep)
	}
	if (got-base)%portScanStep != 0 {
		t.Errorf("findNextPort(%d) = %d, not aligned to step %d from base", base, got, portScanStep)
	}
	// The port comes back reserved, not merely observed-free: while the listener is
	// held the port must read as busy, and only after release can it be bound again.
	// That is the whole point — a concurrent booth scanning the same range skips it.
	if isPortFree(got) {
		t.Errorf("findNextPort(%d) = %d, but the port was not held; a concurrent scan could take it", base, got)
	}
	reservation.Close()
	releasePortClaim()
	if !isPortFree(got) {
		t.Errorf("findNextPort(%d) = %d, but the port stayed busy after releasing the reservation", base, got)
	}
}

func TestFindRandomPort_AvoidsOccupiedBase(t *testing.T) {
	// Occupy the base slot, then confirm RANDOM never hands it back and still returns
	// a free, correctly-aligned port at or above the base.
	lnBase, err := net.Listen("tcp", ":0")
	if err != nil {
		t.Skipf("could not bind an ephemeral port: %v", err)
	}
	defer lnBase.Close()
	base := lnBase.Addr().(*net.TCPAddr).Port
	if (65000-base)/portScanStep < 1 {
		t.Skipf("ephemeral base %d leaves no room above it for RANDOM", base)
	}

	// Try several times: the base must never be selected (it is occupied). Each
	// attempt hands back a live reservation; release it right away, or later passes
	// would be skipping the ports this loop is itself holding.
	for i := 0; i < 20; i++ {
		got, reservation, ok := findRandomPort(base)
		if !ok {
			t.Skip("no free random port found in this environment")
		}
		reservation.Close()
		releasePortClaim()
		if got == base {
			t.Fatalf("findRandomPort(%d) returned the occupied base port", base)
		}
		if got < base {
			t.Errorf("findRandomPort(%d) = %d, want >= base", base, got)
		}
		if (got-base)%portScanStep != 0 {
			t.Errorf("findRandomPort(%d) = %d, not aligned to step %d from base", base, got, portScanStep)
		}
	}
}

// TestFindNextPort_ConcurrentScansDoNotCollide is the regression guard for the
// booth-port race. NEXT hands back the *first* free slot, so two booths starting
// together used to be steered onto the same number: each bound it, closed it
// immediately, and both went on to `docker run -p <same port>`. The second one
// died with "port is already allocated" — exit 125, no output — which is how it
// showed up in the suite, as booths intermittently producing nothing.
//
// Holding the listener is what prevents it, so the assertion is simply that a
// second scan started while the first reservation is live picks a different port.
func TestFindNextPort_ConcurrentScansDoNotCollide(t *testing.T) {
	base := 20000

	firstPort, firstReservation, ok := findNextPort(base)
	if !ok {
		t.Skip("no free port at or above the base in this environment")
	}
	defer firstReservation.Close()
	defer os.Remove(portClaimPath(firstPort))

	// Second booth scanning the same range while the first still holds its port.
	secondPort, secondReservation, ok := findNextPort(base)
	if !ok {
		t.Skip("no second free port at or above the base in this environment")
	}
	defer secondReservation.Close()
	defer releasePortClaim()

	if firstPort == secondPort {
		t.Fatalf("both scans picked port %d; the reservation did not hold, so two booths would race to bind it", firstPort)
	}
}

// TestReleasePortReservation_FreesThePort covers the other half of the contract:
// the held port must become bindable again once released, or docker could never
// publish the very port that was reserved for it.
func TestReleasePortReservation_FreesThePort(t *testing.T) {
	port, reservation, ok := findNextPort(20000)
	if !ok {
		t.Skip("no free port at or above the base in this environment")
	}
	holdPortReservation(reservation)
	defer releasePortClaim()

	if isPortFree(port) {
		t.Fatalf("port %d reads as free while reserved", port)
	}

	releasePortReservation()

	if !isPortFree(port) {
		t.Errorf("port %d is still bound after releasePortReservation; docker could not publish it", port)
	}

	// Idempotent: a second release (e.g. a sidecar released it, then Run releases
	// again) must not panic or double-close.
	releasePortReservation()
}

// TestReservePort_SkipsPortAnotherBoothIsLaunchingOn covers the window the
// in-process reservation cannot: a booth inside `docker run` has already closed its
// listener so docker may bind, but docker has not bound yet. For those ~200ms the
// port is genuinely bindable, and before claims existed a second booth took it —
// measured at 2-3 failures per 8 booths started together. The claim is the only
// evidence available across processes, so reservePort must honour it.
func TestReservePort_SkipsPortAnotherBoothIsLaunchingOn(t *testing.T) {
	port, listener, ok := findNextPort(21000)
	if !ok {
		t.Skip("no free port at or above the base in this environment")
	}
	// Stand where a launching booth stands: claim recorded, listener handed back.
	listener.Close()
	defer releasePortClaim()

	if !isPortFree(port) {
		t.Fatalf("port %d is not bindable, so this test is not exercising the claim", port)
	}
	if _, ok := reservePort(port); ok {
		t.Errorf("reservePort(%d) took a port another booth is mid-launch on", port)
	}
}

// TestPortClaim_StaleClaimIsIgnored guards the other direction: a booth killed
// between claiming and starting leaves a file behind, and nothing else would ever
// remove it. Left unchecked that would park the port permanently, so a claim past
// its TTL must not block anyone.
func TestPortClaim_StaleClaimIsIgnored(t *testing.T) {
	const port = 21987
	path := portClaimPath(port)
	if err := os.MkdirAll(portClaimDir(), 0o777); err != nil {
		t.Skipf("cannot use the claim directory here: %v", err)
	}
	if err := os.WriteFile(path, []byte("999999\n"), 0o644); err != nil {
		t.Skipf("cannot write a claim here: %v", err)
	}
	defer os.Remove(path)

	if !portIsClaimed(port) {
		t.Fatalf("a fresh claim on %d should read as claimed", port)
	}

	// Age it past the TTL, as if the booth that wrote it died a while ago.
	old := time.Now().Add(-claimTTL - time.Minute)
	if err := os.Chtimes(path, old, old); err != nil {
		t.Skipf("cannot age the claim file: %v", err)
	}

	if portIsClaimed(port) {
		t.Errorf("a claim older than the TTL still blocks port %d", port)
	}
}
