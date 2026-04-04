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
			got, ok := resolveRelativeMapping(tt.mapping, tt.boothPort)
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
			_, ok := resolveRelativeMapping(tt.mapping, 10000)
			if ok {
				t.Errorf("resolveRelativeMapping(%q, 10000) should return false", tt.mapping)
			}
		})
	}
}

func buildCtxWithRunArgs(boothPort int, args ...string) appctx.AppContext {
	builder := &appctx.AppContextBuilder{
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
		PortNumber: boothPort,
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

func TestResolveRelativePorts_NoChangeReturnsOriginal(t *testing.T) {
	ctx := buildCtxWithRunArgs(10000, "-e", "FOO=BAR")
	newCtx := ResolveRelativePorts(ctx)

	// When nothing changes, the same context should be returned
	if newCtx.PortNumber() != ctx.PortNumber() {
		t.Errorf("Expected same context when no changes made")
	}
}
