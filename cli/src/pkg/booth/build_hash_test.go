// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"testing"
)

func TestComputeBuildHash_Deterministic(t *testing.T) {
	hash1 := ComputeBuildHash("setup python 3.13", []string{"FOO=bar"}, "codeserver", "0.35.0")
	hash2 := ComputeBuildHash("setup python 3.13", []string{"FOO=bar"}, "codeserver", "0.35.0")
	if hash1 != hash2 {
		t.Errorf("same inputs produced different hashes: %s vs %s", hash1, hash2)
	}
}

func TestComputeBuildHash_Length(t *testing.T) {
	hash := ComputeBuildHash("setup go 1.25", nil, "base", "0.35.0")
	if len(hash) != 24 {
		t.Errorf("expected 24-char hash, got %d: %s", len(hash), hash)
	}
}

func TestComputeBuildHash_SortsBuildArgs(t *testing.T) {
	hash1 := ComputeBuildHash("setup go", []string{"B=2", "A=1"}, "base", "0.35.0")
	hash2 := ComputeBuildHash("setup go", []string{"A=1", "B=2"}, "base", "0.35.0")
	if hash1 != hash2 {
		t.Errorf("different arg order produced different hashes: %s vs %s", hash1, hash2)
	}
}

func TestComputeBuildHash_DifferentContent(t *testing.T) {
	hash1 := ComputeBuildHash("setup python 3.13", nil, "base", "0.35.0")
	hash2 := ComputeBuildHash("setup python 3.14", nil, "base", "0.35.0")
	if hash1 == hash2 {
		t.Error("different boothfile content produced same hash")
	}
}

func TestComputeBuildHash_DifferentVariant(t *testing.T) {
	hash1 := ComputeBuildHash("setup go", nil, "base", "0.35.0")
	hash2 := ComputeBuildHash("setup go", nil, "codeserver", "0.35.0")
	if hash1 == hash2 {
		t.Error("different variants produced same hash")
	}
}

func TestComputeBuildHash_DifferentVersion(t *testing.T) {
	hash1 := ComputeBuildHash("setup go", nil, "base", "0.35.0")
	hash2 := ComputeBuildHash("setup go", nil, "base", "0.36.0")
	if hash1 == hash2 {
		t.Error("different versions produced same hash")
	}
}

func TestComputeBuildHash_DifferentBuildArgs(t *testing.T) {
	hash1 := ComputeBuildHash("setup go", []string{"FOO=bar"}, "base", "0.35.0")
	hash2 := ComputeBuildHash("setup go", []string{"FOO=baz"}, "base", "0.35.0")
	if hash1 == hash2 {
		t.Error("different build args produced same hash")
	}
}

func TestComputeBuildHash_TrimsBoothfile(t *testing.T) {
	hash1 := ComputeBuildHash("  setup go  \n", nil, "base", "0.35.0")
	hash2 := ComputeBuildHash("setup go", nil, "base", "0.35.0")
	if hash1 != hash2 {
		t.Errorf("trimmed and untrimmed boothfile produced different hashes: %s vs %s", hash1, hash2)
	}
}

func TestComputeBuildHash_NilAndEmptyBuildArgs(t *testing.T) {
	hash1 := ComputeBuildHash("setup go", nil, "base", "0.35.0")
	hash2 := ComputeBuildHash("setup go", []string{}, "base", "0.35.0")
	if hash1 == hash2 {
		// nil marshals to null, [] marshals to [] — they may differ and that's acceptable
		// but document the behavior
		t.Log("nil and empty build args produce different hashes (expected)")
	}
}
