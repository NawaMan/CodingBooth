// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import "testing"

// takenSet returns an isTaken checker backed by a fixed set of occupied names.
func takenSet(names ...string) func(string) (bool, error) {
	set := make(map[string]bool, len(names))
	for _, n := range names {
		set[n] = true
	}
	return func(candidate string) (bool, error) {
		return set[candidate], nil
	}
}

func TestResolveUniqueName(t *testing.T) {
	tests := []struct {
		name         string
		reqName      string
		project      string
		port         int
		occupied     []string
		wantName     string
		wantSuffixed bool
		wantErr      bool
	}{
		{
			name:     "free default name used as-is",
			reqName:  "myproj", project: "myproj", port: 10000,
			occupied: nil,
			wantName: "myproj", wantSuffixed: false,
		},
		{
			name:    "taken default name auto-suffixes with port",
			reqName: "myproj", project: "myproj", port: 11000,
			occupied:     []string{"myproj"},
			wantName:     "myproj-11000",
			wantSuffixed: true,
		},
		{
			name:    "explicit custom name collision is an error (no suffix)",
			reqName: "custom", project: "myproj", port: 11000,
			occupied: []string{"custom"},
			wantErr:  true,
		},
		{
			name:    "default and suffixed both taken is an error",
			reqName: "myproj", project: "myproj", port: 11000,
			occupied: []string{"myproj", "myproj-11000"},
			wantErr:  true,
		},
		{
			name:    "free explicit name used as-is",
			reqName: "custom", project: "myproj", port: 12000,
			occupied: []string{"myproj"}, // default taken, but not what was requested
			wantName: "custom", wantSuffixed: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, suffixed, err := resolveUniqueName(tt.reqName, tt.project, tt.port, takenSet(tt.occupied...))
			if (err != nil) != tt.wantErr {
				t.Fatalf("resolveUniqueName err = %v, wantErr %v", err, tt.wantErr)
			}
			if tt.wantErr {
				return
			}
			if got != tt.wantName {
				t.Errorf("name = %q, want %q", got, tt.wantName)
			}
			if suffixed != tt.wantSuffixed {
				t.Errorf("suffixed = %v, want %v", suffixed, tt.wantSuffixed)
			}
		})
	}
}
