// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import "testing"

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
