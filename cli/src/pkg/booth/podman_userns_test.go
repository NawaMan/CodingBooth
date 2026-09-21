// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"reflect"
	"testing"
)

func TestPodmanUserNamespaceArgs(t *testing.T) {
	tests := []struct {
		name   string
		engine string
		euid   int
		want   []string
	}{
		{"rootless podman", "podman", 1000, []string{"--userns=keep-id", "--user", "root"}},
		{"rootful podman", "podman", 0, nil},
		{"docker as user", "docker", 1000, nil},
		{"docker as root", "docker", 0, nil},
		{"windows podman machine (euid -1)", "podman", -1, []string{"--userns=keep-id", "--user", "root"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := podmanUserNamespaceArgs(tt.engine, tt.euid)
			if !reflect.DeepEqual(got, tt.want) {
				t.Errorf("podmanUserNamespaceArgs(%q, %d) = %v, want %v", tt.engine, tt.euid, got, tt.want)
			}
		})
	}
}
