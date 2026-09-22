// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"bytes"
	"io"
	"os"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// captureStderr runs fn and returns whatever it wrote to os.Stderr.
func captureStderr(fn func()) string {
	oldStderr := os.Stderr
	reader, writer, _ := os.Pipe()
	os.Stderr = writer

	fn()

	writer.Close()
	os.Stderr = oldStderr

	var buf bytes.Buffer
	io.Copy(&buf, reader)
	return buf.String()
}

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

func TestResolveEngineConfig_ExplicitValues(t *testing.T) {
	for _, engine := range []string{"docker", "podman"} {
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
	if config.Engine != "docker" && config.Engine != "podman" {
		t.Errorf("resolveEngineConfig(\"\") left Engine as %q, want docker or podman", config.Engine)
	}
}

// TestResolveEngineConfig_DindPodmanWarns verifies --dind with --engine podman
// warns instead of failing or silently trying (see docs/PODMAN_SUPPORT.md,
// "Refuse or clearly warn on --dind when the engine is Podman").
func TestResolveEngineConfig_DindPodmanWarns(t *testing.T) {
	config := &appctx.AppConfig{Engine: "podman", Dind: true, Quiet: true}
	stderr := captureStderr(func() {
		if err := resolveEngineConfig(config); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	})
	if !strings.Contains(stderr, "--dind") || !strings.Contains(stderr, "Podman") {
		t.Errorf("expected a --dind/Podman warning, got: %q", stderr)
	}
}

// TestResolveEngineConfig_DindDockerNoWarning verifies the new warning is
// specific to Podman and does not fire for Docker, which has always
// supported --dind.
func TestResolveEngineConfig_DindDockerNoWarning(t *testing.T) {
	config := &appctx.AppConfig{Engine: "docker", Dind: true, Quiet: true}
	stderr := captureStderr(func() {
		if err := resolveEngineConfig(config); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	})
	if strings.Contains(stderr, "--dind") {
		t.Errorf("did not expect a --dind warning for docker, got: %q", stderr)
	}
}

// TestResolveEngineConfig_PodmanWithoutDindNoDindWarning verifies plain
// --engine podman (no --dind) does not print the --dind-specific warning.
func TestResolveEngineConfig_PodmanWithoutDindNoDindWarning(t *testing.T) {
	config := &appctx.AppConfig{Engine: "podman", Dind: false, Quiet: true}
	stderr := captureStderr(func() {
		if err := resolveEngineConfig(config); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	})
	if strings.Contains(stderr, "--dind") {
		t.Errorf("did not expect a --dind warning without --dind, got: %q", stderr)
	}
}
