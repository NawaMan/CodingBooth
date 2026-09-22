// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestResolveEngineValue_Explicit(t *testing.T) {
	tests := []struct {
		raw    string
		expect string
	}{
		{"docker", "docker"},
		{"Docker", "docker"},
		{" DOCKER ", "docker"},
		{"podman", "podman"},
		{"Podman", "podman"},
	}
	for _, tt := range tests {
		got, err := ResolveEngineValue(tt.raw, true)
		if err != nil {
			t.Errorf("ResolveEngineValue(%q) unexpected error: %v", tt.raw, err)
			continue
		}
		if got != tt.expect {
			t.Errorf("ResolveEngineValue(%q) = %q, want %q", tt.raw, got, tt.expect)
		}
	}
}

func TestResolveEngineValue_Invalid(t *testing.T) {
	_, err := ResolveEngineValue("nerdctl", true)
	if err == nil {
		t.Fatal("expected an error for an unsupported engine value")
	}
}

func TestResolveEngineValue_EmptyNeverErrors(t *testing.T) {
	// Whatever engines happen to be on this machine's PATH, an unset value
	// must always resolve to something usable ("docker" or "podman"), never
	// an error — the caller shells out next and that's where a missing
	// binary should surface, not here.
	got, err := ResolveEngineValue("", true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "docker" && got != "podman" {
		t.Errorf("ResolveEngineValue(\"\") = %q, want \"docker\" or \"podman\"", got)
	}
}

// pathWith puts empty executables with the given names alone on PATH.
func pathWith(t *testing.T, binaries ...string) {
	t.Helper()
	dir := t.TempDir()
	for _, name := range binaries {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("#!/bin/sh\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
}

func TestResolveEnginesForPath(t *testing.T) {
	writeConfig := func(t *testing.T, engine string) string {
		t.Helper()
		codeDir := t.TempDir()
		if err := os.MkdirAll(filepath.Join(codeDir, ".booth"), 0o755); err != nil {
			t.Fatal(err)
		}
		body := "engine = \"" + engine + "\"\n"
		if err := os.WriteFile(filepath.Join(codeDir, ".booth", "config.toml"), []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
		return codeDir
	}

	tests := []struct {
		name     string
		binaries []string
		env      string
		config   string // engine= in the config file ("" = no file)
		want     []string
	}{
		{"nothing chosen, both installed: both", []string{"docker", "podman"}, "", "", []string{"docker", "podman"}},
		{"nothing chosen, only docker", []string{"docker"}, "", "", []string{"docker"}},
		{"nothing chosen, only podman", []string{"podman"}, "", "", []string{"podman"}},
		{"nothing chosen, neither: docker so the real error shows", nil, "", "", []string{"docker"}},
		{"CB_ENGINE=podman is only podman", []string{"docker", "podman"}, "podman", "", []string{"podman"}},
		{"CB_ENGINE=docker is only docker", []string{"docker", "podman"}, "docker", "", []string{"docker"}},
		{"config file beats CB_ENGINE", []string{"docker", "podman"}, "docker", "podman", []string{"podman"}},
		{"config file alone is explicit", []string{"docker", "podman"}, "", "docker", []string{"docker"}},
		{"invalid explicit value falls back to docker, not both", []string{"docker", "podman"}, "nerdctl", "", []string{"docker"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pathWith(t, tt.binaries...)
			t.Setenv("CB_ENGINE", tt.env)
			codeDir := ""
			if tt.config != "" {
				codeDir = writeConfig(t, tt.config)
			}
			got := ResolveEnginesForPath(codeDir, true)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("ResolveEnginesForPath = %v, want %v", got, tt.want)
			}
		})
	}
}
