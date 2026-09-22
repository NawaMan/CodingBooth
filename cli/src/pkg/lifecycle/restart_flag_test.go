// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import "testing"

func TestRestartTimeoutFlag(t *testing.T) {
	if got := restartTimeoutFlag("podman"); got != "--time" {
		t.Errorf("podman = %q, want --time (podman restart has no --timeout)", got)
	}
	for _, engine := range []string{"docker", ""} {
		if got := restartTimeoutFlag(engine); got != "--timeout" {
			t.Errorf("%q = %q, want --timeout", engine, got)
		}
	}
}

func TestExportUserNamespaceArgs(t *testing.T) {
	tests := []struct {
		engine string
		euid   int
		want   int // number of args
	}{
		{"podman", 1000, 1},
		{"podman", 0, 0},
		{"docker", 1000, 0},
		{"", 1000, 0},
	}
	for _, tt := range tests {
		got := exportUserNamespaceArgs(tt.engine, tt.euid)
		if len(got) != tt.want {
			t.Errorf("exportUserNamespaceArgs(%q, %d) = %v, want %d arg(s)", tt.engine, tt.euid, got, tt.want)
		}
		if tt.want == 1 && got[0] != "--userns=keep-id" {
			t.Errorf("got %v, want --userns=keep-id", got)
		}
	}
}
