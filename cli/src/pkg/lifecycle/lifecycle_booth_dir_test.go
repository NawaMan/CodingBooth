// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"path/filepath"
	"testing"
)

func TestHostBoothDir(t *testing.T) {
	tests := []struct {
		name      string
		container managedContainer
		want      string
	}{
		{"an express booth uses cb.booth-dir", managedContainer{CodePath: "/work/demo", BoothDir: "/cache/spec/.booth"}, "/cache/spec/.booth"},
		{"every other booth uses the project .booth", managedContainer{CodePath: "/work/demo"}, filepath.Join("/work/demo", ".booth")},
		{"a booth with no code path has no directory", managedContainer{}, ""},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := tt.container.hostBoothDir(); got != tt.want {
				t.Fatalf("hostBoothDir() = %q, want %q", got, tt.want)
			}
		})
	}
}
