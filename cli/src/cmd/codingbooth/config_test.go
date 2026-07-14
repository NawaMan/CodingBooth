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
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- readExistingArgs / overlayExistingArgs (param pin preservation) ---

func TestReadExistingArgs_ParsesArgLinesOnly(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(dir, ".booth"), 0o755))
	content := "# syntax=codingbooth/boothfile:1\n" +
		"env APT_SNAPSHOT=20260101T000000Z\n" +
		"arg NODE_VERSION=22\n" +
		"arg PLAYWRIGHT_VERSION=1.58.2\n" +
		"setup nodejs ${NODE_VERSION}\n"
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "Boothfile"), []byte(content), 0o644))

	args := readExistingArgs(dir)
	assert.Equal(t, "22", args["NODE_VERSION"])
	assert.Equal(t, "1.58.2", args["PLAYWRIGHT_VERSION"])
	_, hasEnv := args["APT_SNAPSHOT"]
	assert.False(t, hasEnv, "env lines must not be read as args")
}

func TestReadExistingArgs_NoBoothfileReturnsNil(t *testing.T) {
	assert.Nil(t, readExistingArgs(t.TempDir()))
}

func TestOverlayExistingArgs_FillsNonDefaultPin(t *testing.T) {
	tmplT := &tmpl.Template{Params: map[string]tmpl.Param{"PLAYWRIGHT_VERSION": {Default: "latest"}}}
	pv := map[string]string{}
	overlayExistingArgs(pv, "playwright", tmplT, map[string]string{"PLAYWRIGHT_VERSION": "1.58.2"})
	assert.Equal(t, "1.58.2", pv["playwright:PLAYWRIGHT_VERSION"])
}

func TestOverlayExistingArgs_SkipsDefaultValue(t *testing.T) {
	tmplT := &tmpl.Template{Params: map[string]tmpl.Param{"NODE_VERSION": {Default: "22"}}}
	pv := map[string]string{}
	overlayExistingArgs(pv, "nodejs", tmplT, map[string]string{"NODE_VERSION": "22"})
	_, ok := pv["nodejs:NODE_VERSION"]
	assert.False(t, ok, "a value equal to the default is not overlaid")
}

func TestOverlayExistingArgs_DoesNotOverwriteDSLValue(t *testing.T) {
	tmplT := &tmpl.Template{Params: map[string]tmpl.Param{"PLAYWRIGHT_VERSION": {Default: "latest"}}}
	pv := map[string]string{"playwright:PLAYWRIGHT_VERSION": "1.59.0"} // set from the selection DSL
	overlayExistingArgs(pv, "playwright", tmplT, map[string]string{"PLAYWRIGHT_VERSION": "1.58.2"})
	assert.Equal(t, "1.59.0", pv["playwright:PLAYWRIGHT_VERSION"], "explicit DSL value must win")
}

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

// --- overlayExistingArgs with a following default ("${SSH_PORT}") ---

// sshExpose is the expose extension's host-port param: it follows the port the SSH
// server listens on, so its Boothfile `arg` line holds a resolved number, not the
// "${SSH_PORT}" reference the template declares.
func sshExpose() *tmpl.Template {
	return &tmpl.Template{Params: map[string]tmpl.Param{"SSH_HOST_PORT": {Default: "${SSH_PORT}"}}}
}

func TestOverlayExistingArgs_DerivedValueIsNotPinned(t *testing.T) {
	// Boothfile from "openssh+server:2200+expose": the host port was derived from the
	// service port, not chosen. Re-configuring must let it re-derive — pinning 2200 here
	// is what would publish 2200:22 after the service moves to 22.
	pv := map[string]string{}
	overlayExistingArgs(pv, "openssh/expose", sshExpose(), map[string]string{
		"SSH_PORT":      "2200",
		"SSH_HOST_PORT": "2200",
	})
	_, ok := pv["openssh/expose:SSH_HOST_PORT"]
	assert.False(t, ok, "a derived host port must not be preserved as a pin")
}

func TestOverlayExistingArgs_PinnedHostPortSurvives(t *testing.T) {
	// Boothfile from "openssh+server:22+expose:2222": 2222 is a real choice — the host
	// port the user asked for — and it must survive re-configuration.
	pv := map[string]string{}
	overlayExistingArgs(pv, "openssh/expose", sshExpose(), map[string]string{
		"SSH_PORT":      "22",
		"SSH_HOST_PORT": "2222",
	})
	assert.Equal(t, "2222", pv["openssh/expose:SSH_HOST_PORT"], "an explicit host-port pin must be preserved")
}

// --- normalizePublishedPorts (duplicate/overlapping port mappings) ---

func TestNormalizePublishedPorts_LongFormWinsOverIdenticalShortForm(t *testing.T) {
	// "cloudbeaver+expose --expose 8978:8978": one mapping, spelled twice. Docker cannot
	// bind a host port twice, so the booth would not start. The user-owned long form is
	// the keeper — it is what `booth config` reads back into --expose on reconfigure.
	cfg := &output.ConfigToml{RunArgs: []string{
		"-p", "8978:8978",
		"--publish", "8978:8978",
	}}

	normalizePublishedPorts(cfg)
	assert.Equal(t, []string{"--publish", "8978:8978"}, cfg.RunArgs)
}

func TestNormalizePublishedPorts_CollapsesTwoTemplatesOnTheSameMapping(t *testing.T) {
	// nginx+expose/apache+expose: the compiler's dedup runs before params are expanded,
	// so "${NGINX_PORT}:80" and "${APACHE_PORT}:80" both survive as "8080:80".
	cfg := &output.ConfigToml{RunArgs: []string{
		"-p", "8080:80",
		"-p", "8080:80",
	}}

	normalizePublishedPorts(cfg)
	assert.Equal(t, []string{"-p", "8080:80"}, cfg.RunArgs)
}

func TestNormalizePublishedPorts_KeepsDistinctMappingsAndOtherArgs(t *testing.T) {
	cfg := &output.ConfigToml{RunArgs: []string{
		"-v", "booth-data:/opt/data",
		"-p", "5672:5672",
		"-p", "15672:15672",
		"--env", "X=1",
	}}
	before := append([]string{}, cfg.RunArgs...)

	normalizePublishedPorts(cfg)
	assert.Equal(t, before, cfg.RunArgs, "nothing to collapse: run-args untouched")
}

func TestNormalizePublishedPorts_RelativeAndAbsoluteAreNotConfused(t *testing.T) {
	// "+4567:5672" and "4567:5672" are different mappings — the first claims boothPort+4567.
	cfg := &output.ConfigToml{RunArgs: []string{
		"-p", "+4567:5672",
		"--publish", "4567:5672",
	}}
	before := append([]string{}, cfg.RunArgs...)

	normalizePublishedPorts(cfg)
	assert.Equal(t, before, cfg.RunArgs)
}
