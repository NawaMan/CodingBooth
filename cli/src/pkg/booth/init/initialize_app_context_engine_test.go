// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
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
