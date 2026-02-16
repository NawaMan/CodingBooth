// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/nillable"
)

func TestPrepareCommonArgs_AddsLifecycleLabels(t *testing.T) {
	builder := &appctx.AppContextBuilder{
		CbVersion:  "v-test",
		CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
		BuildArgs:  ilist.NewAppendableList[ilist.List[string]](),
		RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
		Cmds:       ilist.NewAppendableList[ilist.List[string]](),
	}
	builder.Config.Name = "demo"
	builder.Config.ProjectName = "demo"
	builder.Config.Variant = "base"
	builder.Config.Code = nillable.NewNillableString(".")
	builder.Config.HostUID = "1000"
	builder.Config.HostGID = "1000"
	builder.Config.KeepAlive = true
	builder.Config.WebSplit = true
	builder.Config.Port = "10000"
	builder.PortNumber = 10000

	ctx := PrepareCommonArgs(builder.Build())

	assertContainsArgPair(t, ctx.CommonArgs(), "--label", "cb.managed=true")
	assertContainsArgPair(t, ctx.CommonArgs(), "--label", "cb.project=demo")
	assertContainsArgPair(t, ctx.CommonArgs(), "--label", "cb.variant=base")
	assertContainsArgPair(t, ctx.CommonArgs(), "--label", "cb.keep-alive=true")
	assertContainsArgPrefix(t, ctx.CommonArgs(), "--label", "cb.created-at=")
	assertContainsArgPrefix(t, ctx.CommonArgs(), "--label", "cb.code-path=")
	assertContainsArgPair(t, ctx.CommonArgs(), "-e", "BOOTH_CODE_PATH="+normalizeCodePath("."))
	assertContainsArgPair(t, ctx.CommonArgs(), "-e", "BOOTH_WEB_SPLIT=true")
}

func TestNormalizeCodePath(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Path format differs on Windows; behavior is covered by non-empty assertion elsewhere")
	}

	got := normalizeCodePath(".")
	want, err := filepath.Abs(".")
	if err != nil {
		t.Fatalf("failed to resolve absolute path: %v", err)
	}
	if got != want {
		t.Fatalf("normalizeCodePath('.') = %q, want %q", got, want)
	}
}

func assertContainsArgPair(t *testing.T, args ilist.List[ilist.List[string]], first string, second string) {
	t.Helper()
	found := false
	args.Range(func(_ int, group ilist.List[string]) bool {
		if group.Length() == 2 && group.At(0) == first && group.At(1) == second {
			found = true
			return false
		}
		return true
	})
	if !found {
		t.Fatalf("expected arg pair [%q %q]", first, second)
	}
}

func assertContainsArgPrefix(t *testing.T, args ilist.List[ilist.List[string]], first string, secondPrefix string) {
	t.Helper()
	found := false
	args.Range(func(_ int, group ilist.List[string]) bool {
		if group.Length() == 2 && group.At(0) == first && strings.HasPrefix(group.At(1), secondPrefix) {
			found = true
			return false
		}
		return true
	})
	if !found {
		t.Fatalf("expected arg pair with prefix [%q %q*]", first, secondPrefix)
	}
}
