// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
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

// --- apt snapshot ---

func TestAptSnapshotID_Override(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "20250101T120000Z")
	assert.Equal(t, "20250101T120000Z", aptSnapshotID())
}

func TestAptSnapshotID_DefaultIsTodayUTCMidnight(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "")
	id := aptSnapshotID()
	// UTC, day granularity: YYYYMMDDT000000Z
	assert.Regexp(t, regexp.MustCompile(`^\d{8}T000000Z$`), id)
}

func TestApplyAptSnapshot_PrependsEnvBeforeContent(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "20260601T000000Z")
	out := &output.BoothOutput{Boothfile: &output.BoothfileContent{Content: "install apt htop\n"}}

	applyAptSnapshot(out)

	assert.Equal(t, "env APT_SNAPSHOT=20260601T000000Z\n\ninstall apt htop\n", out.Boothfile.Content)
	// env must precede the install line so the ENV is visible to the install RUN.
	assert.Less(t, strings.Index(out.Boothfile.Content, "APT_SNAPSHOT"),
		strings.Index(out.Boothfile.Content, "install apt"))
}

func TestApplyAptSnapshot_NoBoothfileIsNoop(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "20260601T000000Z")

	// nil Boothfile
	out := &output.BoothOutput{}
	applyAptSnapshot(out)
	assert.Nil(t, out.Boothfile)

	// empty Boothfile content — nothing to freeze, leave empty
	out = &output.BoothOutput{Boothfile: &output.BoothfileContent{Content: ""}}
	applyAptSnapshot(out)
	assert.Equal(t, "", out.Boothfile.Content)
}

func TestApplyAptSnapshot_Idempotent(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "20260601T000000Z")
	out := &output.BoothOutput{Boothfile: &output.BoothfileContent{
		Content: "env APT_SNAPSHOT=20240101T000000Z\n\ninstall apt htop\n",
	}}

	applyAptSnapshot(out)

	// Existing APT_SNAPSHOT is preserved, not stamped again.
	assert.Equal(t, "env APT_SNAPSHOT=20240101T000000Z\n\ninstall apt htop\n", out.Boothfile.Content)
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
