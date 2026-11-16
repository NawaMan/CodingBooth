// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bytes"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// repairWorkspace is a generated booth with a template-owned file the user
// edited — which repair must never re-copy.
func repairWorkspace(t *testing.T) (catalog, dir, seed string) {
	t.Helper()
	catalog = adoptCatalog(t)
	dir = adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	seed = filepath.Join(dir, ".booth", "home-seed", "settings.json")
	require.NoError(t, os.MkdirAll(filepath.Dir(seed), 0o755))
	require.NoError(t, os.WriteFile(seed, []byte("mine\n"), 0o644))
	return catalog, dir, seed
}

func repair(t *testing.T, catalog, dir string, dryrun bool) (string, error) {
	t.Helper()
	var w bytes.Buffer
	err := repairBooth(&w, "0.0.0", dir, initFlags{templatesPath: catalog, dryrun: dryrun}, repairWrite, "")
	return w.String(), err
}

func TestRepair_NothingToRepair(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	out, err := repair(t, catalog, dir, false)
	require.NoError(t, err)
	assert.Contains(t, out, "Nothing to repair")
}

func TestRepair_StaleFingerprintIsReStamped(t *testing.T) {
	catalog, dir, seed := repairWorkspace(t)
	// Same settings, different bytes: only the fingerprint disagrees.
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "\n\n" })
	require.Equal(t, []string{"config.toml"}, output.Drifted(dir))
	before := snapshotFiles(t, dir)

	out, err := repair(t, catalog, dir, true)
	require.NoError(t, err)
	assert.Contains(t, out, "Would re-stamp")
	assert.Equal(t, before, snapshotFiles(t, dir), "--dryrun writes nothing")

	out, err = repair(t, catalog, dir, false)
	require.NoError(t, err)
	assert.Contains(t, out, "Repaired")
	assert.Empty(t, output.Drifted(dir))
	after := snapshotFiles(t, dir)
	manifest := filepath.Join(dir, ".booth", output.ManifestName)
	for path, content := range before {
		if path != manifest {
			assert.Equal(t, content, after[path], "%s keeps its content", path)
		}
	}
	data, _ := os.ReadFile(seed)
	assert.Equal(t, "mine\n", string(data))
}

func TestRepair_LiftedEditIsRecordedInTheHeader(t *testing.T) {
	catalog, dir, seed := repairWorkspace(t)
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "timezone = \"UTC\"\n" })
	before := snapshotFiles(t, dir)

	out, err := repair(t, catalog, dir, true)
	require.NoError(t, err)
	assert.Contains(t, out, "Would repair")
	assert.Contains(t, out, "timezone=UTC")
	assert.Equal(t, before, snapshotFiles(t, dir), "--dryrun writes nothing")

	_, err = repair(t, catalog, dir, false)
	require.NoError(t, err)
	assert.Empty(t, output.Drifted(dir), "the booth is generated again")
	config := readBooth(t, dir, "config.toml")
	assert.Contains(t, config, `timezone = "UTC"`, "the edit is kept")
	assert.Contains(t, config, "--set timezone=UTC", "and recorded in the header")
	data, _ := os.ReadFile(seed)
	assert.Equal(t, "mine\n", string(data), "template-owned files are not re-copied")

	out, err = repair(t, catalog, dir, false)
	require.NoError(t, err)
	assert.Contains(t, out, "Nothing to repair", "a second repair has nothing left to do")
}

func TestRepair_UnreadableEditIsRefused(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	editBoothFile(t, dir, "Boothfile", func(s string) string { return s + "run echo mine\n" })
	before := snapshotFiles(t, dir)

	_, err := repair(t, catalog, dir, false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "Not repaired — nothing was written.")
	assert.Contains(t, err.Error(), "cannot be read back")
	assert.Equal(t, before, snapshotFiles(t, dir))
}

func TestRepair_CommentARewriteWouldDropIsRefused(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "# keep me\n" })
	before := snapshotFiles(t, dir)

	_, err := repair(t, catalog, dir, false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "# keep me")
	assert.Equal(t, before, snapshotFiles(t, dir))
}

func TestRepair_HandWrittenBoothfileIsRefused(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		var keep []string
		for _, line := range strings.Split(s, "\n") {
			if !strings.HasPrefix(line, "# Configured by:") {
				keep = append(keep, line)
			}
		}
		return strings.Join(keep, "\n")
	})

	_, err := repair(t, catalog, dir, false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "not written by booth config")
}

func TestRepair_NoBooth(t *testing.T) {
	_, err := repair(t, adoptCatalog(t), t.TempDir(), false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "no booth configured")
}

func validate(t *testing.T, catalog, dir string) (string, error) {
	t.Helper()
	var w bytes.Buffer
	err := repairBooth(&w, "0.0.0", dir, initFlags{templatesPath: catalog}, repairCheck, "")
	return w.String(), err
}

func TestValidate_GeneratedBoothIsValid(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	out, err := validate(t, catalog, dir)
	require.NoError(t, err)
	assert.Contains(t, out, "Valid")
}

func TestValidate_ReportsWhatRepairWouldDoAndWritesNothing(t *testing.T) {
	cases := map[string]struct {
		file, add, want string
	}{
		"stale fingerprint": {"config.toml", "\n\n", "repair re-stamps it"},
		"lifted edit":       {"config.toml", "timezone = \"UTC\"\n", "timezone=UTC"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			catalog, dir, _ := repairWorkspace(t)
			editBoothFile(t, dir, c.file, func(s string) string { return s + c.add })
			before := snapshotFiles(t, dir)

			out, err := validate(t, catalog, dir)
			assert.ErrorIs(t, err, errInvalid)
			assert.Contains(t, out, "Not valid")
			assert.Contains(t, out, c.want)
			assert.Equal(t, before, snapshotFiles(t, dir), "validate writes nothing")
		})
	}
}

func TestValidate_UnrepairableSaysRepairCannotFixIt(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	// A template's line removed: no flag and no added template brings that about.
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		return strings.Replace(s, "setup tool ${TOOL_VERSION}\n", "", 1)
	})
	before := snapshotFiles(t, dir)

	_, err := validate(t, catalog, dir)
	require.Error(t, err)
	assert.NotErrorIs(t, err, errInvalid)
	assert.Contains(t, err.Error(), "repair cannot fix it")
	assert.Contains(t, err.Error(), "cannot be read back")
	assert.Equal(t, before, snapshotFiles(t, dir))
}

// A selection with nothing to build writes config.toml alone — still a booth.
func TestValidate_ConfigOnlyBoothIsChecked(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	require.NoError(t, os.Remove(filepath.Join(dir, ".booth", "Boothfile")))

	_, err := validate(t, catalog, dir)
	assert.NotContains(t, fmt.Sprint(err), "no booth configured")
}

func runRepairInto(t *testing.T, catalog, dir, into string, dryrun bool) (string, error) {
	t.Helper()
	var w bytes.Buffer
	err := repairBooth(&w, "0.0.0", dir, initFlags{templatesPath: catalog, dryrun: dryrun}, repairWrite, into)
	return w.String(), err
}

// The booth with lines no flag writes: one before the template's setup line and
// one after it, each with its comment, an added arg, and an unflagged run-arg.
func intoWorkspace(t *testing.T) (catalog, dir string) {
	t.Helper()
	catalog, dir, _ = repairWorkspace(t)
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		s = strings.Replace(s, "arg TOOL_VERSION=1.0.0\n", "arg MY_LIB=2.1\narg TOOL_VERSION=1.0.0\n", 1)
		s = strings.Replace(s, "setup tool ${TOOL_VERSION}\n",
			"# the tool needs it\ninstall apt libfoo\nsetup tool ${TOOL_VERSION}\n# and then mine\nrun echo ${MY_LIB}\n", 1)
		return s
	})
	editBoothFile(t, dir, "config.toml", func(s string) string {
		// After the template's own entries: an added template's run-args land there.
		start := strings.Index(s, "run-args = [")
		end := start + strings.Index(s[start:], "\n]")
		return strings.TrimSuffix(s[:end], ",") + ",\n    \"--gpus\", \"all\"" + s[end:]
	})
	return catalog, dir
}

func TestValidate_SaysIntoWouldFixLinesNoFlagWrites(t *testing.T) {
	catalog, dir := intoWorkspace(t)
	before := snapshotFiles(t, dir)
	out, err := validate(t, catalog, dir)
	assert.ErrorIs(t, err, errInvalid)
	assert.Contains(t, out, "booth config repair --into local")
	assert.Contains(t, out, "install apt libfoo")
	assert.Equal(t, before, snapshotFiles(t, dir))
}

func TestRepair_WithoutIntoRefusesButPointsAtIt(t *testing.T) {
	catalog, dir := intoWorkspace(t)
	_, err := repair(t, catalog, dir, false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "booth config repair --into <name>")
}

func TestRepairInto_MovesTheLinesIntoATemplateAndReadsBack(t *testing.T) {
	catalog, dir := intoWorkspace(t)
	boothfile := readBooth(t, dir, "Boothfile")
	before := snapshotFiles(t, dir)

	out, err := runRepairInto(t, catalog, dir, "mine", true)
	require.NoError(t, err, out)
	assert.Contains(t, out, "Would repair")
	assert.Contains(t, out, "[params.MY_LIB]")
	assert.Equal(t, before, snapshotFiles(t, dir), "--dryrun writes nothing")

	out, err = runRepairInto(t, catalog, dir, "mine", false)
	require.NoError(t, err, out)
	assert.Empty(t, output.Drifted(dir), "the booth is generated again")

	tpl := readBooth(t, dir, "templates/mine.toml")
	assert.Contains(t, tpl, "# the tool needs it\ninstall apt libfoo\n")
	assert.Contains(t, tpl, "# and then mine\nrun echo ${MY_LIB}\n")
	assert.Contains(t, tpl, `"--gpus", "all",`)

	after := readBooth(t, dir, "Boothfile")
	assert.Equal(t, output.BoothfileDirectives(boothfile), output.BoothfileDirectives(after), "the same directives, in the same order")
	assert.Contains(t, after, "# the tool needs it", "and the comments are kept")
	assert.Contains(t, after, "--select tool/mine")
	assert.Contains(t, readBooth(t, dir, "config.toml"), `"--gpus", "all"`)

	out, err = validate(t, catalog, dir)
	require.NoError(t, err)
	assert.Contains(t, out, "Valid")
}

func TestRepairInto_RemovedTemplateLineIsRefused(t *testing.T) {
	catalog, dir, _ := repairWorkspace(t)
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		return strings.Replace(s, "setup tool ${TOOL_VERSION}\n", "setup tool ${TOOL_VERSION} --old\n", 1)
	})
	before := snapshotFiles(t, dir)
	_, err := runRepairInto(t, catalog, dir, "mine", false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "Not repaired")
	assert.Contains(t, err.Error(), "can only add lines")
	assert.Equal(t, before, snapshotFiles(t, dir))
}

func TestRepairInto_TakenNameIsRefused(t *testing.T) {
	catalog, dir := intoWorkspace(t)
	_, err := runRepairInto(t, catalog, dir, "tool", false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "already exists")
}

func TestPickBand(t *testing.T) {
	cases := []struct {
		name  string
		lo    int
		loSrc string
		hi    int
		hiSrc string
		want  int
		ok    bool
	}{
		{"mine", 60, "nodejs+pnpm-install", 65, "nodejs+vscode-ext", 62, true},
		{"mine", -1, "", 100, "\uffff", 49, true},
		{"mine", 50, "a", 51, "z", 50, true}, // no band between: share 50, "mine" sorts after "a"
		{"b", 50, "a", 50, "c", 50, true},    // same band, sorts between
		{"z", 50, "a", 50, "c", 0, false},    // same band, sorts outside
		{"mine", 50, "x", 50, "x", 0, false}, // inside one segment
	}
	for _, c := range cases {
		got, ok := pickBand(c.name, c.lo, c.loSrc, c.hi, c.hiSrc)
		assert.Equal(t, c.ok, ok, "%+v", c)
		if c.ok {
			assert.Equal(t, c.want, got, "%+v", c)
		}
	}
}

func TestRepairInto_ReorderedTemplateLinesAreNamedAsReordered(t *testing.T) {
	catalog := adoptCatalog(t)
	require.NoError(t, os.MkdirAll(filepath.Join(catalog, "lang", "other"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(catalog, "lang", "other", "template.toml"),
		[]byte("primary = true\n[segments]\n\"Boothfile--60\" = \"\"\"\nsetup other\n\"\"\"\n"), 0o644))
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool/other"}})
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		s = strings.Replace(s, "setup other\n", "", 1)
		return strings.Replace(s, "setup tool ${TOOL_VERSION}\n", "setup other\nsetup tool ${TOOL_VERSION}\n", 1)
	})
	_, err := runRepairInto(t, catalog, dir, "mine", false)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "reordered")
}
