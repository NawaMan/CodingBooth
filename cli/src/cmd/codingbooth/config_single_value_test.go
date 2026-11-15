// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestIsSnapshotOnlyChange(t *testing.T) {
	cases := []struct {
		args []string
		want bool
	}{
		{[]string{"--no-tui", "--apt-snapshot", "20261023T000000Z"}, true},
		{[]string{"--no-tui", "--overwrite", "--apt-snapshot", "none"}, true},
		{[]string{"--apt-snapshot", "today", "--no-tui", "--dryrun", "--beside", "--debug"}, true},
		{[]string{"--no-tui"}, false},
		{[]string{"--no-tui", "--apt-snapshot"}, false},
		{[]string{"--no-tui", "--apt-snapshot", "none", "--variant", "codeserver"}, false},
		{[]string{"--no-tui", "--apt-snapshot", "none", "--select", "go"}, false},
		{[]string{"--no-tui", "--apt-snapshot", "none", "--set", "port=1"}, false},
		{[]string{"--no-tui", "--apt-snapshot", "none", "--start"}, false},
	}
	for _, tc := range cases {
		assert.Equal(t, tc.want, isSnapshotOnlyChange(tc.args), "%v", tc.args)
	}
}

func TestSetAptSnapshotLine_ReplacesOnlyThatLine(t *testing.T) {
	in := "# syntax=codingbooth/boothfile:1\n# Configured by: booth config\n\nenv APT_SNAPSHOT=20260101T000000Z\n\nsetup tool 1.0.0\n"
	got, prev, found := setAptSnapshotLine(in, "20261023T000000Z")
	assert.True(t, found)
	assert.Equal(t, "20260101T000000Z", prev)
	assert.Equal(t, strings.Replace(in, "20260101T000000Z", "20261023T000000Z", 1), got)

	got, prev, found = setAptSnapshotLine(got, "")
	assert.True(t, found)
	assert.Equal(t, "20261023T000000Z", prev)
	assert.Contains(t, got, "\nenv APT_SNAPSHOT=\n", "none writes the empty line, the recorded no-freeze")
}

func TestSetAptSnapshotLine_InsertsAfterHeaderWhenMissing(t *testing.T) {
	got, _, found := setAptSnapshotLine("# syntax=codingbooth/boothfile:1\n\nsetup tool\n", "20261023T000000Z")
	assert.False(t, found)
	assert.Equal(t, "# syntax=codingbooth/boothfile:1\n\nenv APT_SNAPSHOT=20261023T000000Z\n\nsetup tool\n", got)

	got, _, _ = setAptSnapshotLine("# header\nsetup tool\n", "X")
	assert.Equal(t, "# header\n\nenv APT_SNAPSHOT=X\n\nsetup tool\n", got)

	got, _, _ = setAptSnapshotLine("setup tool\n", "X")
	assert.Equal(t, "env APT_SNAPSHOT=X\n\nsetup tool\n", got)
}

// snapshotWorkspace is a generated booth plus a template-owned file the user
// edited by hand — the kind of content a full reconfigure would overwrite.
func snapshotWorkspace(t *testing.T) (dir, seedPath string) {
	t.Helper()
	dir = adoptWorkspace(t, adoptCatalog(t), initFlags{selectDSLs: []string{"tool"}})
	seedPath = filepath.Join(dir, ".booth", "home-seed", ".claude", "settings.json")
	require.NoError(t, os.MkdirAll(filepath.Dir(seedPath), 0o755))
	require.NoError(t, os.WriteFile(seedPath, []byte(`{"deny":["curl|bash"]}`), 0o644))
	return dir, seedPath
}

func readBooth(t *testing.T, dir, name string) string {
	t.Helper()
	data, err := os.ReadFile(filepath.Join(dir, ".booth", name))
	require.NoError(t, err)
	return string(data)
}

func TestChangeAptSnapshotOnly_GeneratedBoothStaysGenerated(t *testing.T) {
	dir, seedPath := snapshotWorkspace(t)
	configBefore := readBooth(t, dir, "config.toml")
	boothfileBefore := readBooth(t, dir, "Boothfile")

	change, err := changeAptSnapshotOnly(dir, "20261023T000000Z", false)
	require.NoError(t, err)
	assert.True(t, change.changed)
	assert.False(t, change.handWritten)
	assert.Equal(t, "20260101T000000Z", change.previous)

	assert.Equal(t,
		strings.Replace(boothfileBefore, "env APT_SNAPSHOT=20260101T000000Z", "env APT_SNAPSHOT=20261023T000000Z", 1),
		readBooth(t, dir, "Boothfile"), "only the snapshot line changes")
	assert.Equal(t, configBefore, readBooth(t, dir, "config.toml"))
	seed, _ := os.ReadFile(seedPath)
	assert.Equal(t, `{"deny":["curl|bash"]}`, string(seed), "template-owned files are not re-copied")
	assert.Empty(t, output.Drifted(dir), "the fingerprint was re-stamped, so the booth is still generated")
}

func TestChangeAptSnapshotOnly_HandEditedFilesStayAsTheyAre(t *testing.T) {
	dir, _ := snapshotWorkspace(t)
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "# my note\n" })
	editBoothFile(t, dir, "Boothfile", func(s string) string { return s + "run echo mine\n" })
	configBefore := readBooth(t, dir, "config.toml")
	manifestBefore := readBooth(t, dir, output.ManifestName)

	change, err := changeAptSnapshotOnly(dir, "20261023T000000Z", false)
	require.NoError(t, err)
	assert.True(t, change.handWritten)

	boothfile := readBooth(t, dir, "Boothfile")
	assert.Contains(t, boothfile, "env APT_SNAPSHOT=20261023T000000Z")
	assert.Contains(t, boothfile, "run echo mine\n", "the user's own lines are kept")
	assert.Equal(t, configBefore, readBooth(t, dir, "config.toml"))
	assert.Equal(t, manifestBefore, readBooth(t, dir, output.ManifestName),
		"a hand-written Boothfile is not re-stamped as generated")
	assert.ElementsMatch(t, []string{"Boothfile", "config.toml"}, output.Drifted(dir))
}

func TestChangeAptSnapshotOnly_SameValueWritesNothing(t *testing.T) {
	dir, _ := snapshotWorkspace(t)
	path := filepath.Join(dir, ".booth", output.ManifestName)
	require.NoError(t, os.Remove(path)) // adopted on its header; a write would create it

	change, err := changeAptSnapshotOnly(dir, "20260101T000000Z", false)
	require.NoError(t, err)
	assert.False(t, change.changed)
	assert.NoFileExists(t, path)
}

func TestChangeAptSnapshotOnly_DryrunWritesNothing(t *testing.T) {
	dir, _ := snapshotWorkspace(t)
	before := readBooth(t, dir, "Boothfile")

	change, err := changeAptSnapshotOnly(dir, "20261023T000000Z", true)
	require.NoError(t, err)
	assert.True(t, change.changed)
	assert.Contains(t, change.content, "env APT_SNAPSHOT=20261023T000000Z")
	assert.Equal(t, before, readBooth(t, dir, "Boothfile"))

	var w bytes.Buffer
	reportSnapshotChange(&w, dir, "20261023T000000Z", true, change)
	assert.Contains(t, w.String(), "Would set apt snapshot")
	assert.Contains(t, w.String(), "20260101T000000Z -> 20261023T000000Z")
}

func TestReadConfigImageSettings(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(dir, ".booth"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "config.toml"),
		[]byte("variant = \"codeserver\"\ndind = true\nversion = \"0.82.0\"\nport = 10000\n"), 0o644))

	settings := configImageSettings(readConfigImageSettings(dir))
	assert.Equal(t, map[string]string{"variant": "codeserver", "dind": "true", "version": "0.82.0"}, settings)

	assert.Equal(t, map[string]string{"variant": ""}, configImageSettings(readConfigImageSettings(t.TempDir())))
}
