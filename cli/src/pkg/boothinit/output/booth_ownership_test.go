// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestBoothOwnershipTargets(t *testing.T) {
	tests := []struct {
		name  string
		setup func(dir string)
		want  []string
	}{
		{
			name:  "NothingToStamp",
			setup: func(string) {},
			want:  nil,
		},
		{
			name: "BoothDirOnly",
			setup: func(dir string) {
				assert.NoError(t, os.Mkdir(filepath.Join(dir, ".booth"), 0755))
			},
			want: []string{"/target/.booth"},
		},
		{
			name: "WrapperOnly",
			setup: func(dir string) {
				assert.NoError(t, os.WriteFile(filepath.Join(dir, "booth"), []byte("#!/bin/sh\n"), 0755))
			},
			want: []string{"/target/booth"},
		},
		{
			name: "BothInBoothDirFirstOrder",
			setup: func(dir string) {
				assert.NoError(t, os.Mkdir(filepath.Join(dir, ".booth"), 0755))
				assert.NoError(t, os.WriteFile(filepath.Join(dir, "booth"), []byte("#!/bin/sh\n"), 0755))
			},
			want: []string{"/target/.booth", "/target/booth"},
		},
		{
			// addReadOnlyBoothWrapper skips a directory named "booth", so the
			// stamp must skip it too -- it is never mounted, so never root-owned.
			name: "WrapperIsADirectory",
			setup: func(dir string) {
				assert.NoError(t, os.Mkdir(filepath.Join(dir, "booth"), 0755))
			},
			want: nil,
		},
		{
			// Mirror of the above: addReadOnlyBoothDir requires .booth to be a
			// directory, so a stray file by that name is not a stamp target.
			name: "BoothDirIsAFile",
			setup: func(dir string) {
				assert.NoError(t, os.WriteFile(filepath.Join(dir, ".booth"), []byte("oops"), 0644))
			},
			want: nil,
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			dir := t.TempDir()
			test.setup(dir)
			assert.Equal(t, test.want, boothOwnershipTargets(dir))
		})
	}
}
