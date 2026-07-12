// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// writeBooth lays down .booth/<name> with the given content.
func writeBooth(t *testing.T, dir, name, content string) string {
	t.Helper()
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	path := filepath.Join(boothDir, name)
	require.NoError(t, os.WriteFile(path, []byte(content), 0644))
	return path
}

const generatedBoothfile = "# syntax=codingbooth/boothfile:1\n# Configured by: booth config --no-tui --select go\n\narg GO_VERSION=1.25.7\n"

// --- Drifted: classification ---

func TestDrifted_NoBooth(t *testing.T) {
	assert.Empty(t, Drifted(t.TempDir()))
}

func TestDrifted_HandWritten_NoHeaderNoHash(t *testing.T) {
	dir := t.TempDir()
	writeBooth(t, dir, "Boothfile", "setup go\ninstall apt curl\n")

	assert.Equal(t, []string{"Boothfile"}, Drifted(dir),
		"a Boothfile with no header and no recorded hash is hand-authored")
}

func TestDrifted_LegacyGenerated_HeaderButNoHash_IsAdopted(t *testing.T) {
	dir := t.TempDir()
	writeBooth(t, dir, "Boothfile", generatedBoothfile)

	assert.Empty(t, Drifted(dir),
		"a booth generated before manifests existed must not cry wolf on its first run")
}

func TestDrifted_Tracked_Unchanged(t *testing.T) {
	dir := t.TempDir()
	writeBooth(t, dir, "Boothfile", generatedBoothfile)
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, writeManifest(boothDir, map[string]string{
		"Boothfile": hashContent(generatedBoothfile),
	}))

	assert.Empty(t, Drifted(dir), "content matching what we wrote is safe to regenerate")
}

// The case the provenance header alone cannot catch: generated, then hand-edited.
// The header is still present, so only the hash reveals the edit.
func TestDrifted_Tracked_ThenHandEdited(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	writeBooth(t, dir, "Boothfile", generatedBoothfile)
	require.NoError(t, writeManifest(boothDir, map[string]string{
		"Boothfile": hashContent(generatedBoothfile),
	}))

	// A human adds a line, leaving the "# Configured by:" header intact.
	writeBooth(t, dir, "Boothfile", generatedBoothfile+"install apt ripgrep\n")

	assert.Equal(t, []string{"Boothfile"}, Drifted(dir),
		"an edit to a tracked file must be caught even though the header survives")
}

func TestDrifted_ReportsBothFiles(t *testing.T) {
	dir := t.TempDir()
	writeBooth(t, dir, "Boothfile", "setup go\n")
	writeBooth(t, dir, "config.toml", "variant = \"base\"\n")

	assert.ElementsMatch(t, []string{"Boothfile", "config.toml"}, Drifted(dir))
}

// --- WriteOutput records the manifest, closing the loop ---

func TestWriteOutput_RecordsManifest_ThenNoDrift(t *testing.T) {
	dir := t.TempDir()
	out := &BoothOutput{
		Config:    &ConfigToml{Variant: "base"},
		Boothfile: &BoothfileContent{Content: "setup go\n"},
		Command:   "booth config --no-tui --select go",
	}
	require.NoError(t, WriteOutput(out, dir))

	assert.Empty(t, Drifted(dir), "what we just wrote must not read back as drifted")

	// Now a human edits it — that must be caught.
	boothfile := filepath.Join(dir, ".booth", "Boothfile")
	content, err := os.ReadFile(boothfile)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(boothfile, append(content, []byte("install apt jq\n")...), 0644))

	assert.Equal(t, []string{"Boothfile"}, Drifted(dir))
}

// An empty selection writes no Boothfile; that must not un-track a Boothfile
// recorded by an earlier run.
func TestWriteManifest_PreservesUntouchedEntries(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))

	require.NoError(t, writeManifest(boothDir, map[string]string{"Boothfile": "sha256:aaa"}))
	require.NoError(t, writeManifest(boothDir, map[string]string{"config.toml": "sha256:bbb"}))

	entries := readManifest(boothDir)
	assert.Equal(t, "sha256:aaa", entries["Boothfile"], "an untouched file keeps its hash")
	assert.Equal(t, "sha256:bbb", entries["config.toml"])
}

// --- WriteOutputBeside: keep theirs, write ours alongside ---

func TestWriteOutputBeside_KeepsOriginalAndWritesNew(t *testing.T) {
	dir := t.TempDir()
	handwritten := "setup go\ninstall apt ripgrep\n"
	writeBooth(t, dir, "Boothfile", handwritten)

	out := &BoothOutput{
		Config:    &ConfigToml{Variant: "base"},
		Boothfile: &BoothfileContent{Content: "setup go\n"},
		Command:   "booth config --no-tui --select go",
	}
	require.NoError(t, WriteOutputBeside(out, dir, []string{"Boothfile"}))

	boothDir := filepath.Join(dir, ".booth")

	kept, err := os.ReadFile(filepath.Join(boothDir, "Boothfile"))
	require.NoError(t, err)
	assert.Equal(t, handwritten, string(kept), "the hand-written file is left exactly as it was")

	generated, err := os.ReadFile(filepath.Join(boothDir, "Boothfile.new"))
	require.NoError(t, err)
	assert.Contains(t, string(generated), "# Configured by:", "the generated content lands as .new")

	assert.NoFileExists(t, filepath.Join(boothDir, "Boothfile.bak"),
		"nothing was destroyed, so nothing needs backing up")
}

// A diverted file must NOT be recorded in the manifest: the canonical path still
// holds the user's own content, so it has to keep reading back as hand-written
// until they actually merge. Recording it would bless their file as ours and let
// the next run clobber it silently — reintroducing the original bug.
func TestWriteOutputBeside_DoesNotAdoptTheUsersFile(t *testing.T) {
	dir := t.TempDir()
	writeBooth(t, dir, "Boothfile", "setup go\ninstall apt ripgrep\n")

	out := &BoothOutput{
		Config:    &ConfigToml{Variant: "base"},
		Boothfile: &BoothfileContent{Content: "setup go\n"},
	}
	require.NoError(t, WriteOutputBeside(out, dir, []string{"Boothfile"}))

	assert.Equal(t, []string{"Boothfile"}, Drifted(dir),
		"the kept file must still be guarded on the next run")
}

// Non-diverted guarded files are written normally in the same pass — a booth can
// have a hand-written Boothfile and a config.toml that is still ours.
func TestWriteOutputBeside_WritesUndriftedFilesNormally(t *testing.T) {
	dir := t.TempDir()
	writeBooth(t, dir, "Boothfile", "setup go\n")

	out := &BoothOutput{
		Config:    &ConfigToml{Variant: "base"},
		Boothfile: &BoothfileContent{Content: "setup go\n"},
		Command:   "booth config --no-tui --select go",
	}
	require.NoError(t, WriteOutputBeside(out, dir, []string{"Boothfile"}))

	boothDir := filepath.Join(dir, ".booth")
	assert.FileExists(t, filepath.Join(boothDir, "Boothfile.new"))
	assert.NoFileExists(t, filepath.Join(boothDir, "config.toml.new"),
		"config.toml was not hand-written, so it is written in place")

	entries := readManifest(boothDir)
	assert.Contains(t, entries, "config.toml", "the file we did write is tracked")
	assert.NotContains(t, entries, "Boothfile", "the file we diverted is not")
}

// --- BackupDrifted ---

func TestBackupDrifted_KeepsOriginalContent(t *testing.T) {
	dir := t.TempDir()
	original := "setup go\ninstall apt curl\n"
	writeBooth(t, dir, "Boothfile", original)

	require.NoError(t, BackupDrifted(dir, []string{"Boothfile"}))

	backup, err := os.ReadFile(filepath.Join(dir, ".booth", "Boothfile.bak"))
	require.NoError(t, err)
	assert.Equal(t, original, string(backup))
}
