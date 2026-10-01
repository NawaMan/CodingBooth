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
		{"apple", "apple"},
		{" Apple ", "apple"},
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
	// "container" is the Apple engine's binary, not an engine name: the
	// engine is "apple".
	for _, raw := range []string{"nerdctl", "container"} {
		if _, err := ResolveEngineValue(raw, true); err == nil {
			t.Errorf("expected an error for unsupported engine value %q", raw)
		}
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
	if got != "docker" && got != "podman" && got != "apple" {
		t.Errorf("ResolveEngineValue(\"\") = %q, want docker, podman or apple", got)
	}
}

// pathWith puts empty executables with the given names alone on PATH. The
// name "container+running" installs a `container` whose `system status` reports
// its service running; a plain "container" reports nothing, like a stopped one.
func pathWith(t *testing.T, binaries ...string) {
	t.Helper()
	dir := t.TempDir()
	for _, name := range binaries {
		script := "#!/bin/sh\n"
		if name == "container+running" {
			name = "container"
			script += `[ "$1 $2" = "system status" ] && echo '{"status":"running"}'` + "\nexit 0\n"
		}
		if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir)
}

func TestResolveEngineValue_DefaultOrder(t *testing.T) {
	tests := []struct {
		name     string
		binaries []string
		appleOK  bool
		want     string
	}{
		{"Apple container running comes first", []string{"docker", "podman", "container+running"}, true, "apple"},
		{"Apple container running beats docker", []string{"docker", "container+running"}, true, "apple"},
		{"Apple container stopped: docker", []string{"docker", "podman", "container"}, true, "docker"},
		{"Apple container stopped, no docker: podman", []string{"podman", "container"}, true, "podman"},
		{"only Apple container, stopped: apple, so its error shows", []string{"container"}, true, "apple"},
		{"no Apple container: docker", []string{"docker", "podman"}, true, "docker"},
		{"no docker: podman", []string{"podman"}, true, "podman"},
		{"nothing installed: docker", nil, true, "docker"},
		{"sidecar run skips a running Apple container", []string{"docker", "container+running"}, false, "docker"},
		{"sidecar run with only Apple container: docker", []string{"container+running"}, false, "docker"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			pathWith(t, tt.binaries...)
			resolve := ResolveEngineValue
			if !tt.appleOK {
				resolve = ResolveEngineValueWithoutApple
			}
			got, err := resolve("", true)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tt.want {
				t.Errorf("default engine = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestResolveEngineValueWithoutApple_ExplicitAppleStays(t *testing.T) {
	pathWith(t, "docker", "container+running")
	got, err := ResolveEngineValueWithoutApple("apple", true)
	if err != nil || got != "apple" {
		t.Errorf("explicit apple = %q, %v; want apple, for the caller to refuse", got, err)
	}
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
		{"nothing chosen, all three installed: all three", []string{"docker", "podman", "container"}, "", "", []string{"apple", "docker", "podman"}},
		{"nothing chosen, docker and Apple container", []string{"docker", "container"}, "", "", []string{"apple", "docker"}},
		{"nothing chosen, only Apple container: apple", []string{"container"}, "", "", []string{"apple"}},
		{"CB_ENGINE=apple is only apple", []string{"docker", "podman", "container"}, "apple", "", []string{"apple"}},
		{"CB_ENGINE=docker excludes Apple container", []string{"docker", "container"}, "docker", "", []string{"docker"}},
		{"config file engine=apple is only apple", []string{"docker", "container"}, "", "apple", []string{"apple"}},
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
