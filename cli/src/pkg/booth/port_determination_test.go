// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"net"
	"testing"
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

	got, ok := findNextPort(base)
	if !ok {
		t.Fatal("findNextPort returned no free port")
	}
	if got < base+2*portScanStep {
		t.Errorf("findNextPort(%d) = %d, expected it to skip the two occupied ports (>= %d)", base, got, base+2*portScanStep)
	}
	if (got-base)%portScanStep != 0 {
		t.Errorf("findNextPort(%d) = %d, not aligned to step %d from base", base, got, portScanStep)
	}
	if !isPortFree(got) {
		t.Errorf("findNextPort(%d) = %d, but that port is not actually free", base, got)
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

	// Try several times: the base must never be selected (it is occupied).
	for i := 0; i < 20; i++ {
		got, ok := findRandomPort(base)
		if !ok {
			t.Skip("no free random port found in this environment")
		}
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
