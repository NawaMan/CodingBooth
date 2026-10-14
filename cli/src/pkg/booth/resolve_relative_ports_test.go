// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

func TestResolveRelativeMapping_ValidOffset(t *testing.T) {
	tests := []struct {
		name      string
		mapping   string
		boothPort int
		want      string
		wantOk    bool
	}{
		{
			name:      "simple offset",
			mapping:   "+8080:8080",
			boothPort: 10000,
			want:      "18080:8080",
			wantOk:    true,
		},
		{
			name:      "different booth port",
			mapping:   "+3000:3000",
			boothPort: 12000,
			want:      "15000:3000",
			wantOk:    true,
		},
		{
			name:      "zero offset",
			mapping:   "+0:8080",
			boothPort: 10000,
			want:      "10000:8080",
			wantOk:    true,
		},
		{
			name:      "offset with different container port",
			mapping:   "+5432:5432",
			boothPort: 10000,
			want:      "15432:5432",
			wantOk:    true,
		},
		{
			name:      "small offset",
			mapping:   "+1:80",
			boothPort: 10000,
			want:      "10001:80",
			wantOk:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, ok, err := resolveRelativeMapping(tt.mapping, tt.boothPort)
			if err != nil {
				t.Fatalf("resolveRelativeMapping(%q, %d) returned %v", tt.mapping, tt.boothPort, err)
			}
			if ok != tt.wantOk {
				t.Errorf("resolveRelativeMapping(%q, %d) ok = %v, want %v", tt.mapping, tt.boothPort, ok, tt.wantOk)
			}
			if got != tt.want {
				t.Errorf("resolveRelativeMapping(%q, %d) = %q, want %q", tt.mapping, tt.boothPort, got, tt.want)
			}
		})
	}
}

func TestResolveRelativeMapping_Invalid(t *testing.T) {
	tests := []struct {
		name    string
		mapping string
	}{
		{name: "no plus prefix", mapping: "8080:8080"},
		{name: "no colon separator", mapping: "+8080"},
		{name: "non-numeric offset", mapping: "+abc:8080"},
		{name: "empty string", mapping: ""},
		{name: "just plus", mapping: "+"},
		{name: "plus colon only", mapping: "+:8080"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, ok, err := resolveRelativeMapping(tt.mapping, 10000)
			if ok {
				t.Errorf("resolveRelativeMapping(%q, 10000) should return false", tt.mapping)
			}
			// Not a relative mapping at all: passed through, not an error.
			if err != nil {
				t.Errorf("resolveRelativeMapping(%q, 10000) returned %v, want it left alone", tt.mapping, err)
			}
		})
	}
}

// buildCtxWithRunArgs builds a context whose offset base is the booth port —
// what PortDetermination settles on when offset-base is unset.
func buildCtxWithRunArgs(boothPort int, args ...string) appctx.AppContext {
	return buildCtxWithOffsetBase(boothPort, boothPort, args...)
}

// buildCtxWithOffsetBase builds a context whose offset base has been moved off
// the booth port, as --offset-base does.
func buildCtxWithOffsetBase(boothPort, offsetBase int, args ...string) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs:       ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:        ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:          ilist.NewAppendableList[ilist.List[string]](),
		Cmds:             ilist.NewAppendableList[ilist.List[string]](),
		PortNumber:       boothPort,
		OffsetBaseNumber: offsetBase,
	}
	builder.Config.Code = nillable.NewNillableString("/tmp/test")

	argList := ilist.NewAppendableList[string]()
	for _, a := range args {
		argList.Append(a)
	}
	builder.RunArgs.Append(argList.ToList())

	return builder.Build()
}

func flattenRunArgs(ctx appctx.AppContext) []string {
	var result []string
	ctx.RunArgs().Range(func(_ int, list ilist.List[string]) bool {
		list.Range(func(_ int, s string) bool {
			result = append(result, s)
			return true
		})
		return true
	})
	return result
}

func TestResolveRelativePorts_PlusOffset(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "-p", "+8080:8080")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	if len(args) != 2 || args[0] != "-p" || args[1] != "18080:8080" {
		t.Errorf("Expected [-p 18080:8080], got %v", args)
	}
}

func TestResolveRelativePorts_PlainPortUnchanged(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "-p", "8080:8080")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	if len(args) != 2 || args[0] != "-p" || args[1] != "8080:8080" {
		t.Errorf("Expected [-p 8080:8080], got %v", args)
	}
}

func TestResolveRelativePorts_PublishLongForm(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "--publish", "+3000:3000")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	if len(args) != 2 || args[0] != "--publish" || args[1] != "13000:3000" {
		t.Errorf("Expected [--publish 13000:3000], got %v", args)
	}
}

func TestResolveRelativePorts_EqualsSyntax(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "-p=+5432:5432")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	if len(args) != 1 || args[0] != "-p=15432:5432" {
		t.Errorf("Expected [-p=15432:5432], got %v", args)
	}
}

func TestResolveRelativePorts_PublishEqualsSyntax(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "--publish=+8080:8080")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	if len(args) != 1 || args[0] != "--publish=18080:8080" {
		t.Errorf("Expected [--publish=18080:8080], got %v", args)
	}
}

func TestResolveRelativePorts_MixedArgs(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "-e", "FOO=BAR", "-p", "+8080:8080", "-v", "/a:/b", "-p", "3000:3000")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	expected := []string{"-e", "FOO=BAR", "-p", "18080:8080", "-v", "/a:/b", "-p", "3000:3000"}
	if len(args) != len(expected) {
		t.Fatalf("Expected %v, got %v", expected, args)
	}
	for i := range expected {
		if args[i] != expected[i] {
			t.Errorf("args[%d] = %q, want %q", i, args[i], expected[i])
		}
	}
}

// An offset base of its own is what a cloud booth uses: the front door sits on a
// fixed port it did not choose, and services still want to land where the base
// says.
func TestResolveRelativePorts_OffsetBaseOverridesBoothPort(t *testing.T) {
	ctx := buildCtxWithOffsetBase(8443, 20000, "-p", "+90:8090")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	if len(args) != 2 || args[0] != "-p" || args[1] != "20090:8090" {
		t.Errorf("Expected [-p 20090:8090], got %v", args)
	}
}

// Base 0 turns every +OFFSET into the port it names, so templates written in
// offsets publish at their stock ports without being rewritten.
func TestResolveRelativePorts_ZeroOffsetBaseIsAbsolute(t *testing.T) {
	ctx := buildCtxWithOffsetBase(8443, 0, "-p", "+8090:8090", "--publish=+5432:5432")
	newCtx := ResolveRelativePorts(ctx)
	args := flattenRunArgs(newCtx)

	expected := []string{"-p", "8090:8090", "--publish=5432:5432"}
	if len(args) != len(expected) {
		t.Fatalf("Expected %v, got %v", expected, args)
	}
	for i := range expected {
		if args[i] != expected[i] {
			t.Errorf("args[%d] = %q, want %q", i, args[i], expected[i])
		}
	}
}

func TestResolveRelativePorts_NoChangeReturnsOriginal(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "-e", "FOO=BAR")
	newCtx := ResolveRelativePorts(ctx)

	// When nothing changes, the same context should be returned
	if newCtx.PortNumber() != ctx.PortNumber() {
		t.Errorf("Expected same context when no changes made")
	}
}

// A mapping that resolves past the ceiling is the failure docker used to report
// as "invalid hostPort: 73888", with nothing to say where the number came from.
func TestResolveRelativeMapping_PastCeiling(t *testing.T) {
	tests := []struct {
		name      string
		mapping   string
		boothPort int
	}{
		{name: "the data-example mapping on a high pick", mapping: "+8888:18888", boothPort: 65000},
		{name: "one over the ceiling", mapping: "+1:8080", boothPort: maxPortNumber},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, ok, err := resolveRelativeMapping(tt.mapping, tt.boothPort)
			if err == nil {
				t.Fatalf("resolveRelativeMapping(%q, %d) accepted a host port above %d", tt.mapping, tt.boothPort, maxPortNumber)
			}
			if ok {
				t.Errorf("resolveRelativeMapping(%q, %d) reported success alongside an error", tt.mapping, tt.boothPort)
			}
		})
	}
}

// The ceiling is the host port's, not the offset's: the same mapping is fine
// from a base that leaves room for it.
func TestResolveRelativeMapping_AtCeiling(t *testing.T) {
	got, ok, err := resolveRelativeMapping("+8888:18888", maxPortNumber-8888)
	if err != nil || !ok {
		t.Fatalf("resolveRelativeMapping at the ceiling = (%q, %v, %v), want it accepted", got, ok, err)
	}
	if got != "65535:18888" {
		t.Errorf("resolveRelativeMapping at the ceiling = %q, want \"65535:18888\"", got)
	}
}

func TestMaxRelativeOffset(t *testing.T) {
	tests := []struct {
		name       string
		args       []string
		wantOffset int
		wantFound  bool
	}{
		{
			name:       "no relative publish",
			args:       []string{"-e", "FOO=BAR", "-p", "8080:8080"},
			wantOffset: 0,
			wantFound:  false,
		},
		{
			name:       "the largest of several, across both spellings",
			args:       []string{"-p", "+3000:13000", "--publish=+8888:18888", "-p=+90:8090"},
			wantOffset: 8888,
			wantFound:  true,
		},
		{
			name:       "a zero offset is still a relative publish",
			args:       []string{"--publish", "+0:10000"},
			wantOffset: 0,
			wantFound:  true,
		},
		{
			name:       "a value that only looks like a mapping is skipped",
			args:       []string{"-e", "+9999:nope", "-p", "+100:8080"},
			wantOffset: 100,
			wantFound:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			offset, found := maxRelativeOffset(buildCtxWithRunArgs(10000, tt.args...))
			if found != tt.wantFound {
				t.Errorf("maxRelativeOffset(%v) found = %v, want %v", tt.args, found, tt.wantFound)
			}
			if offset != tt.wantOffset {
				t.Errorf("maxRelativeOffset(%v) = %d, want %d", tt.args, offset, tt.wantOffset)
			}
		})
	}
}

// NEXT / RANDOM scan within the headroom the offsets need, so the pick itself
// can never produce a host port docker will refuse.
func TestFindNextPort_StopsAtCeiling(t *testing.T) {
	// maxRelativeOffset of a "+8888" publish leaves this ceiling.
	ceiling := maxPortNumber - 8888
	port, listener, ok := findNextPort(ceiling-portScanStep+1, ceiling)
	if !ok {
		t.Skip("no free port in the one slot this ceiling allows")
	}
	defer listener.Close()
	defer releasePortClaim()

	if port > ceiling {
		t.Errorf("findNextPort returned %d, above the ceiling %d", port, ceiling)
	}
	if port+8888 > maxPortNumber {
		t.Errorf("findNextPort returned %d, which puts a +8888 publish at %d", port, port+8888)
	}
}

func TestFindNextPort_NoSlotUnderCeiling(t *testing.T) {
	if _, _, ok := findNextPort(60000, 50000); ok {
		t.Error("findNextPort found a port above its own ceiling")
	}
}
