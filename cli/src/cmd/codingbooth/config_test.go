// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- reverseExposeMapping ---

func TestReverseExposeMapping(t *testing.T) {
	tests := []struct {
		name     string
		mapping  string
		expected string
	}{
		{
			name:     "plain port same host and container",
			mapping:  "8080:8080",
			expected: "8080",
		},
		{
			name:     "different host and container ports kept as-is",
			mapping:  "9090:3000",
			expected: "9090:3000",
		},
		{
			name:     "offset shorthand same port",
			mapping:  "+8080:8080",
			expected: "+8080",
		},
		{
			name:     "offset with different container port kept as-is",
			mapping:  "+3000:5000",
			expected: "+3000:5000",
		},
		{
			name:     "IP binding kept as-is",
			mapping:  "127.0.0.1:8080:8080",
			expected: "127.0.0.1:8080:8080",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			result := reverseExposeMapping(tc.mapping)
			assert.Equal(t, tc.expected, result)
		})
	}
}

// --- sliceContains ---

func TestSliceContains(t *testing.T) {
	assert.True(t, sliceContains([]string{"a", "b", "c"}, "b"))
	assert.False(t, sliceContains([]string{"a", "b", "c"}, "d"))
	assert.False(t, sliceContains(nil, "a"))
	assert.False(t, sliceContains([]string{}, "a"))
}

// --- extractUserRunArgs ---

func TestExtractUserRunArgs_MixedShortAndLongForm(t *testing.T) {
	// Create a temp directory with a .booth/config.toml containing mixed short/long form flags
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))

	// Write a config.toml with mixed short-form (template) and long-form (user) run-args
	configContent := `run-args = [
    "-e", "FOO=1",
    "--env", "BAR=2",
    "-p", "8080:8080",
    "--publish", "3000:3000",
    "-v", "/a:/b",
    "--volume", "/c:/d"
]
`
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte(configContent), 0644))

	var flags initFlags
	extractUserRunArgs(tmpDir, &flags)

	// Only long-form values should be extracted
	assert.Equal(t, []string{"BAR=2"}, flags.envs, "only --env (long-form) values should be extracted")
	assert.Equal(t, []string{"3000"}, flags.exposes, "only --publish (long-form) values should be extracted, reversed via reverseExposeMapping")
	assert.Equal(t, []string{"/c:/d"}, flags.mounts, "only --volume (long-form) values should be extracted")
}

func TestExtractUserRunArgs_NoDuplicates(t *testing.T) {
	// Pre-populate flags with existing values; extractUserRunArgs should not add duplicates
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))

	configContent := `run-args = [
    "--env", "BAR=2",
    "--publish", "3000:3000",
    "--volume", "/c:/d"
]
`
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte(configContent), 0644))

	flags := initFlags{
		envs:    []string{"BAR=2"},
		exposes: []string{"3000"}, // reversed form of 3000:3000
		mounts:  []string{"/c:/d"},
	}
	extractUserRunArgs(tmpDir, &flags)

	// Should not duplicate existing values
	assert.Equal(t, []string{"BAR=2"}, flags.envs)
	assert.Equal(t, []string{"3000"}, flags.exposes)
	assert.Equal(t, []string{"/c:/d"}, flags.mounts)
}

func TestExtractUserRunArgs_NoConfigFile(t *testing.T) {
	// When config.toml does not exist, extractUserRunArgs should return without error
	tmpDir := t.TempDir()

	var flags initFlags
	extractUserRunArgs(tmpDir, &flags)

	assert.Empty(t, flags.envs)
	assert.Empty(t, flags.exposes)
	assert.Empty(t, flags.mounts)
}

func TestExtractUserRunArgs_ExposeReverseMapping(t *testing.T) {
	// Verify that --publish values go through reverseExposeMapping
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))

	configContent := `run-args = [
    "--publish", "8080:8080",
    "--publish", "+8080:8080",
    "--publish", "9090:3000"
]
`
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte(configContent), 0644))

	var flags initFlags
	extractUserRunArgs(tmpDir, &flags)

	// 8080:8080 → 8080, +8080:8080 → +8080, 9090:3000 → 9090:3000
	assert.Equal(t, []string{"8080", "+8080", "9090:3000"}, flags.exposes)
}
