// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"sort"
	"strings"
)

// buildHashInput is the JSON structure hashed to produce a content-based tag.
type buildHashInput struct {
	Boothfile string   `json:"boothfile"`
	BuildArgs []string `json:"build-args"`
	Variant   string   `json:"variant"`
	Version   string   `json:"version"`
}

// ComputeBuildHash computes a 24-character hex tag from the Boothfile content,
// build arguments, variant, and version. Identical inputs always produce the
// same hash, making the tag content-addressable.
func ComputeBuildHash(boothfileContent string, buildArgs []string, variant string, version string) string {
	// Sort build args for deterministic output
	sorted := make([]string, len(buildArgs))
	copy(sorted, buildArgs)
	sort.Strings(sorted)

	input := buildHashInput{
		Boothfile: strings.TrimSpace(boothfileContent),
		BuildArgs: sorted,
		Variant:   variant,
		Version:   version,
	}

	data, _ := json.Marshal(input)
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])[:24]
}
