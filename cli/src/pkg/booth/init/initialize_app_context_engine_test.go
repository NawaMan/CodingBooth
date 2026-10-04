// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func TestParseArgs_Engine(t *testing.T) {
	argList := ilist.NewListFromSlice([]string{"--engine", "podman"})
	config := appctx.AppConfig{
		RunArgs:   ilist.SemicolonStringList{List: ilist.NewList[string]()},
		BuildArgs: ilist.SemicolonStringList{List: ilist.NewList[string]()},
		Cmds:      ilist.SemicolonStringList{List: ilist.NewList[string]()},
	}

	if err := parseArgs(argList, &config); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}
	if config.Engine != "podman" {
		t.Errorf("Expected Engine to be %q, got %q", "podman", config.Engine)
	}
}

func TestParseArgs_AppleLowPorts(t *testing.T) {
	config := appctx.AppConfig{
		RunArgs:   ilist.SemicolonStringList{List: ilist.NewList[string]()},
		BuildArgs: ilist.SemicolonStringList{List: ilist.NewList[string]()},
		Cmds:      ilist.SemicolonStringList{List: ilist.NewList[string]()},
	}
	if err := parseArgs(ilist.NewListFromSlice([]string{"--apple-low-ports"}), &config); err != nil {
		t.Fatalf("parseArgs failed: %v", err)
	}
	if !config.AppleLowPorts {
		t.Error("--apple-low-ports did not set AppleLowPorts")
	}
}

func TestResolveEngineConfig_ExplicitValues(t *testing.T) {
	for _, engine := range []string{"docker", "podman", "apple"} {
		config := &appctx.AppConfig{Engine: engine, Quiet: true}
		if err := resolveEngineConfig(config); err != nil {
			t.Fatalf("resolveEngineConfig(%q) unexpected error: %v", engine, err)
		}
		if config.Engine != engine {
			t.Errorf("resolveEngineConfig(%q) left Engine as %q", engine, config.Engine)
		}
	}
}

func TestResolveEngineConfig_Invalid(t *testing.T) {
	config := &appctx.AppConfig{Engine: "nerdctl", Quiet: true}
	if err := resolveEngineConfig(config); err == nil {
		t.Fatal("expected an error for an unsupported --engine value")
	}
}

func TestResolveEngineConfig_EmptyResolvesToConcreteValue(t *testing.T) {
	config := &appctx.AppConfig{Engine: "", Quiet: true}
	if err := resolveEngineConfig(config); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if config.Engine != "docker" && config.Engine != "podman" && config.Engine != "apple" {
		t.Errorf("resolveEngineConfig(\"\") left Engine as %q, want docker, podman or apple", config.Engine)
	}
}

// pathWithRunningApple puts docker and a `container` whose service reports
// running alone on PATH, so Apple container is the default engine.
func pathWithRunningApple(t *testing.T) {
	t.Helper()
	dir := t.TempDir()
	scripts := map[string]string{
		"docker":    "#!/bin/sh\n",
		"container": "#!/bin/sh\n[ \"$1 $2\" = \"system status\" ] && echo '{\"status\":\"running\"}'\nexit 0\n",
	}
	for name, script := range scripts {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
}

func TestResolveEngineConfig_DefaultIsAppleWhenRunning(t *testing.T) {
	pathWithRunningApple(t)
	config := &appctx.AppConfig{Engine: "", Quiet: true}
	if err := resolveEngineConfig(config); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if config.Engine != "apple" {
		t.Errorf("Engine = %q, want apple", config.Engine)
	}
}

// --dind and --egress need a sidecar Apple container cannot start, so with no
// engine chosen they fall to docker instead of being refused.
func TestResolveEngineConfig_SidecarRunSkipsDefaultApple(t *testing.T) {
	pathWithRunningApple(t)
	for _, config := range []*appctx.AppConfig{
		{Engine: "", Dind: true, Quiet: true},
		{Engine: "", Egress: true, Quiet: true},
	} {
		if err := resolveEngineConfig(config); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if config.Engine != "docker" {
			t.Errorf("Engine = %q (dind=%t egress=%t), want docker", config.Engine, config.Dind, config.Egress)
		}
	}
}

func TestResolveEngineConfig_ExplicitAppleWithDindIsStillRefused(t *testing.T) {
	pathWithRunningApple(t)
	config := &appctx.AppConfig{Engine: "apple", Dind: true, Quiet: true}
	if err := resolveEngineConfig(config); err == nil {
		t.Fatal("explicit --engine apple with --dind must still be refused")
	}
}

// TestResolveEngineConfig_DindPodmanNoError verifies --dind with --engine
// podman is accepted (Phase 4, docs/PODMAN_SUPPORT.md): it runs a nested-Podman
// sidecar instead of docker:dind (see startDindSidecar in dind_setup.go),
// rather than the outright refusal this used to be. It still only warns, on
// stderr, which this test does not capture.
func TestResolveEngineConfig_DindPodmanNoError(t *testing.T) {
	config := &appctx.AppConfig{Engine: "podman", Dind: true, Quiet: true}
	if err := resolveEngineConfig(config); err != nil {
		t.Errorf("did not expect an error for --dind with --engine podman, got: %v", err)
	}
}

// TestResolveEngineConfig_DindDockerNoError verifies plain Docker --dind
// (always supported) is unaffected by the Podman-specific warning above.
func TestResolveEngineConfig_DindDockerNoError(t *testing.T) {
	config := &appctx.AppConfig{Engine: "docker", Dind: true, Quiet: true}
	if err := resolveEngineConfig(config); err != nil {
		t.Errorf("did not expect an error for --dind with docker, got: %v", err)
	}
}

// TestResolveEngineConfig_PodmanWithoutDindNoError verifies plain --engine
// podman (no --dind) is not affected by the --dind-specific refusal.
func TestResolveEngineConfig_PodmanWithoutDindNoError(t *testing.T) {
	config := &appctx.AppConfig{Engine: "podman", Dind: false, Quiet: true}
	if err := resolveEngineConfig(config); err != nil {
		t.Errorf("did not expect an error for plain --engine podman, got: %v", err)
	}
}

// TestResolveEngineConfig_AppleRefusesSidecars: --dind needs a
// --privileged daemon and --egress a shared network namespace, neither of
// which Apple container offers (docs/CONTAINER_SUPPORT.md).
func TestResolveEngineConfig_AppleRefusesSidecars(t *testing.T) {
	for _, config := range []*appctx.AppConfig{
		{Engine: "apple", Quiet: true, Dind: true},
		{Engine: "apple", Quiet: true, Egress: true},
	} {
		err := resolveEngineConfig(config)
		if err == nil || !strings.Contains(err.Error(), "not supported on engine apple") {
			t.Errorf("dind=%t egress=%t: want a refusal, got %v", config.Dind, config.Egress, err)
		}
	}
}
