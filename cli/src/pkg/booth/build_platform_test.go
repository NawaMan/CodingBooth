// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func args(items ...string) ilist.List[ilist.List[string]] {
	return ilist.NewList(ilist.NewList(items...))
}

var noArgs = ilist.NewList[ilist.List[string]]()

func TestBuildPlatformFlag_FromRunArgs(t *testing.T) {
	got, ok := buildPlatformFlag(noArgs, args("--device", "/dev/kvm", "--platform", "linux/amd64"), noArgs)
	if !ok || got != "linux/amd64" {
		t.Errorf("got (%q, %v), want (\"linux/amd64\", true)", got, ok)
	}
}

func TestBuildPlatformFlag_FromCommonArgsEqualsForm(t *testing.T) {
	got, ok := buildPlatformFlag(args("--platform=linux/arm64"), noArgs, noArgs)
	if !ok || got != "linux/arm64" {
		t.Errorf("got (%q, %v), want (\"linux/arm64\", true)", got, ok)
	}
}

func TestBuildPlatformFlag_None(t *testing.T) {
	if got, ok := buildPlatformFlag(noArgs, args("--device", "/dev/kvm"), noArgs); ok {
		t.Errorf("got (%q, true), want no platform", got)
	}
}

// A --platform already in build-args must not get a second one beside it:
// buildx reads two as a multi-platform build and the docker driver refuses it.
func TestBuildPlatformFlag_BuildArgsAlreadyHaveOne(t *testing.T) {
	for _, buildArgs := range []ilist.List[ilist.List[string]]{
		args("--platform", "linux/amd64"),
		args("--platform=linux/amd64"),
	} {
		if got, ok := buildPlatformFlag(noArgs, args("--platform", "linux/amd64"), buildArgs); ok {
			t.Errorf("build-args %v: got (%q, true), want no added platform", buildArgs, got)
		}
	}
}
