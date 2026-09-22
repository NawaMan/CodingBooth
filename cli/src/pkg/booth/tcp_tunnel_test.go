// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"context"
	"reflect"
	"testing"
)

func TestTunnelExecCommand(t *testing.T) {
	tests := []struct {
		name     string
		engine   string
		wantArgs []string
	}{
		{"podman", "podman", []string{"podman", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
		{"docker", "docker", []string{"docker", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
		{"unset engine means docker", "", []string{"docker", "exec", "-i", "mybooth", "socat", "STDIO", "TCP:localhost:8080"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cmd := tunnelExecCommand(context.Background(), tt.engine, "mybooth", 8080)
			if !reflect.DeepEqual(cmd.Args, tt.wantArgs) {
				t.Errorf("tunnelExecCommand args = %v, want %v", cmd.Args, tt.wantArgs)
			}
		})
	}
}
