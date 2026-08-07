// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"
)

func TestDeviceHostPath(t *testing.T) {
	tests := []struct {
		name string
		spec string
		want string
	}{
		{"HostOnly", "/dev/kvm", "/dev/kvm"},
		{"HostAndContainer", "/dev/kvm:/dev/kvm", "/dev/kvm"},
		{"HostContainerPerms", "/dev/kvm:/dev/kvm:rwm", "/dev/kvm"},
		{"Renamed", "/dev/sda:/dev/xvda:r", "/dev/sda"},
		{"Empty", "", ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := deviceHostPath(tt.spec); got != tt.want {
				t.Fatalf("deviceHostPath(%q) = %q, want %q", tt.spec, got, tt.want)
			}
		})
	}
}

func TestFilterMissingDeviceItems(t *testing.T) {
	// /dev/null exists everywhere this runs; the bogus path never does.
	const present = "/dev/null"
	const missing = "/dev/definitely-not-a-real-device-cb"

	tests := []struct {
		name  string
		items []string
		want  []string
	}{
		{
			name:  "KeepsPresentDevice",
			items: []string{"--device", present},
			want:  []string{"--device", present},
		},
		{
			name:  "DropsMissingDevice",
			items: []string{"--device", missing},
			want:  nil,
		},
		{
			// The whole point: the rest of the run-args must survive intact, so a
			// missing device costs you the device and nothing else.
			name:  "DropsOnlyTheMissingPair",
			items: []string{"-p", "8080:80", "--device", missing, "-e", "FOO=bar"},
			want:  []string{"-p", "8080:80", "-e", "FOO=bar"},
		},
		{
			name:  "KeepsPresentDropsMissing",
			items: []string{"--device", present, "--device", missing},
			want:  []string{"--device", present},
		},
		{
			name:  "KeepsPermissionSuffixForm",
			items: []string{"--device", present + ":" + present + ":rwm"},
			want:  []string{"--device", present + ":" + present + ":rwm"},
		},
		{
			// Not an absolute path, so not checkable — passed through rather than
			// guessed at.
			name:  "PassesThroughNonAbsolute",
			items: []string{"--device", "some-token"},
			want:  []string{"--device", "some-token"},
		},
		{
			// A trailing --device with no value must not panic or eat past the end.
			name:  "DanglingFlag",
			items: []string{"-e", "A=1", "--device"},
			want:  []string{"-e", "A=1", "--device"},
		},
		{
			name:  "UntouchedWithoutDevices",
			items: []string{"-p", "1:1", "-v", "/a:/b"},
			want:  []string{"-p", "1:1", "-v", "/a:/b"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := filterMissingDeviceItems(tt.items)
			if len(got) != len(tt.want) {
				t.Fatalf("filterMissingDeviceItems(%v) = %v, want %v", tt.items, got, tt.want)
			}
			for i := range got {
				if got[i] != tt.want[i] {
					t.Fatalf("filterMissingDeviceItems(%v) = %v, want %v", tt.items, got, tt.want)
				}
			}
		})
	}
}
