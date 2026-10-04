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

func TestVmResourceArgs(t *testing.T) {
	args, notes, err := vmResourceArgs("apple", "8g", "6", "2g", "desktop-kde", true)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := [][]string{{"--memory", "8g"}, {"--cpus", "6"}, {"--shm-size", "2g"}}
	if !reflect.DeepEqual(args, want) || len(notes) != 0 {
		t.Errorf("apple with all three = %v, notes %v; want %v and no notes", args, notes, want)
	}

	args, notes, _ = vmResourceArgs("apple", "", "", "", "desktop-kde", true)
	if args != nil || len(notes) != 1 || !strings.Contains(notes[0], "Add --vm-memory 4g") {
		t.Errorf("a desktop on apple without vm-memory = %v, %q; want no args and the warning", args, notes)
	}
	if _, notes, _ := vmResourceArgs("apple", "", "", "", "base", false); len(notes) != 0 {
		t.Errorf("a non-desktop on apple needs no warning, got %q", notes)
	}

	args, notes, _ = vmResourceArgs("docker", "8g", "", "", "desktop-kde", true)
	if args != nil || len(notes) != 1 || !strings.Contains(notes[0], "ignored on docker") {
		t.Errorf("docker = %v, %q; want nothing passed and the ignored note", args, notes)
	}
	if _, notes, _ := vmResourceArgs("docker", "", "", "", "desktop-kde", true); len(notes) != 0 {
		t.Errorf("docker with nothing set says nothing, got %q", notes)
	}

	for _, bad := range []struct{ memory, cpus, shm string }{
		{"lots", "", ""}, {"", "0", ""}, {"", "two", ""}, {"", "", "1 g"},
	} {
		if _, _, err := vmResourceArgs("apple", bad.memory, bad.cpus, bad.shm, "base", false); err == nil {
			t.Errorf("%+v: want a validation error", bad)
		}
	}
	for _, ok := range []string{"512m", "4g", "4096m", "2048mb", "1.5g", "8G"} {
		if _, _, err := vmResourceArgs("apple", ok, "", "", "base", false); err != nil {
			t.Errorf("%q should be a valid size: %v", ok, err)
		}
	}
}
