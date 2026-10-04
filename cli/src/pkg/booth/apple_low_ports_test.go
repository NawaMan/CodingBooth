// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"reflect"
	"strings"
	"testing"
)

func TestAppleLowPortsArgs(t *testing.T) {
	want := [][]string{
		{"-e", "BOOTH_LOW_PORTS=true"},
		{"--label", "cb.apple-low-ports=true"},
	}
	if got := appleLowPortsArgs("apple", true); !reflect.DeepEqual(got, want) {
		t.Errorf("apple with the flag = %v, want %v", got, want)
	}
	if got := appleLowPortsArgs("apple", false); got != nil {
		t.Errorf("apple without the flag = %v, want nil (low ports are opt-in)", got)
	}
	for _, engine := range []string{"docker", "podman", ""} {
		if got := appleLowPortsArgs(engine, true); got != nil {
			t.Errorf("%q with the flag = %v, want nil (only Apple container needs it)", engine, got)
		}
	}
}

func TestAppleLowPortsNote(t *testing.T) {
	tests := []struct {
		name             string
		engine           string
		lowPorts, public bool
		want             string // substring; "" = no note
	}{
		{"flag on docker is ignored, and says so", "docker", true, false, "ignored on docker"},
		{"flag on podman is ignored, and says so", "podman", true, false, "ignored on podman"},
		{"flag on apple: nothing to say", "apple", true, true, ""},
		{"--public on apple without the flag warns", "apple", false, true, "Add --apple-low-ports"},
		{"apple without --public or the flag: nothing", "apple", false, false, ""},
		{"--public on docker: nothing", "docker", false, true, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := appleLowPortsNote(tt.engine, tt.lowPorts, tt.public)
			if tt.want == "" && got != "" {
				t.Errorf("note = %q, want none", got)
			}
			if tt.want != "" && !strings.Contains(got, tt.want) {
				t.Errorf("note = %q, want it to contain %q", got, tt.want)
			}
		})
	}
}
