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

// adoptCatalog writes a one-template catalog: `tool` contributes a Boothfile line,
// a version param, and two run-args entries of its own — enough to tell template
// entries from user ones.
func adoptCatalog(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	category := filepath.Join(dir, "lang")
	require.NoError(t, os.MkdirAll(filepath.Join(category, "tool"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(category, "meta.toml"),
		[]byte("display-name = \"Lang\"\norder = 1\n"), 0o644))
	require.NoError(t, os.WriteFile(filepath.Join(category, "tool", "template.toml"), []byte(`display-name = "Tool"
primary = true
run-args = [
    "-e", "TOOL_HOME=/opt/tool",
    "-v", "/tmp/tool-cache:/cache",
]

[params.TOOL_VERSION]
default = "1.0.0"

[segments]
Boothfile = """
setup tool ${TOOL_VERSION}
"""
`), 0o644))
	return dir
}

// adoptWorkspace generates a booth the way `booth config --no-tui` does, so the
// header, fingerprint and APT snapshot are the real thing.
func adoptWorkspace(t *testing.T, catalog string, flags initFlags) string {
	t.Helper()
	dir := t.TempDir()
	flags.templatesPath = catalog
	flags.selectDSL = strings.Join(flags.selectDSLs, "/")

	out, _, err := compileSelectionE(flags, dir, nil)
	require.NoError(t, err)
	out.Command = buildConfigCommand(dir, flags)
	out.AdjustCommand = buildConfigAdjustCommand(flags)
	applyAptSnapshotID(out, "20260101T000000Z")
	require.NoError(t, output.WriteOutput(out, dir))
	require.Empty(t, output.Drifted(dir), "a freshly generated booth is not edited")
	return dir
}

func editBoothFile(t *testing.T, dir, name string, edit func(string) string) {
	t.Helper()
	path := filepath.Join(dir, ".booth", name)
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	require.NoError(t, os.WriteFile(path, []byte(edit(string(data))), 0o644))
}

func readBaseline(t *testing.T, catalog, dir string) boothBaseline {
	t.Helper()
	return readBoothBaseline("0.0.0", dir, initFlags{templatesPath: catalog})
}

func TestReadBoothBaseline_UneditedBoothIsNotChecked(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})

	baseline := readBaseline(t, catalog, dir)
	assert.Empty(t, baseline.edited)
	assert.False(t, baseline.adopt.attempted)
	assert.Equal(t, []string{"tool"}, baseline.flags.selectDSLs)
}

func TestAdopt_AddedSettingIsLiftedAndItsCommentReported(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string {
		return s + "\n# the team is in Bangkok\ntimezone = \"Asia/Bangkok\"\n"
	})

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	assert.Empty(t, baseline.drifted, "an adopted edit is not treated as hand-written")
	assert.Contains(t, baseline.flags.sets, "timezone=Asia/Bangkok")
	require.Len(t, baseline.adopt.lost, 1)
	assert.Equal(t, "config.toml", baseline.adopt.lost[0].file)
	assert.Equal(t, "# the team is in Bangkok", baseline.adopt.lost[0].Text)
}

func TestAdopt_CommentOnlyEditIsAdopted(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		return strings.Replace(s, "setup tool", "# pinned by ops\nsetup tool", 1)
	})

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	require.Len(t, baseline.adopt.lost, 1)
	assert.Equal(t, "Boothfile", baseline.adopt.lost[0].file)
}

func TestAdopt_UnproducibleBoothfileLineIsRefusedWithReason(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "Boothfile", func(s string) string { return s + "run echo hi\n" })

	baseline := readBaseline(t, catalog, dir)
	assert.True(t, baseline.adopt.attempted)
	assert.False(t, baseline.adopt.adopted)
	assert.Equal(t, []string{"Boothfile"}, baseline.drifted, "a refused edit stays hand-written")
	require.NotEmpty(t, baseline.adopt.reasons)
	assert.Contains(t, baseline.adopt.reasons[0], "run echo hi")
}

func TestAdopt_ShortFormEntryAppendedIsLiftedAsEnv(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}, envs: []string{"FOO=1"}})
	editBoothFile(t, dir, "config.toml", func(s string) string {
		return strings.Replace(s, `"--env", "FOO=1"`, `"--env", "FOO=1",`+"\n"+`    "-e", "BAR=2"`, 1)
	})

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	assert.Equal(t, []string{"FOO=1", "BAR=2"}, baseline.flags.envs)
}

func TestAdopt_RemovedUserEntryIsDropped(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}, envs: []string{"FOO=1", "BAR=2"}})
	editBoothFile(t, dir, "config.toml", func(s string) string {
		return strings.Replace(s, `"--env", "FOO=1",`+"\n", "", 1)
	})

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	assert.Equal(t, []string{"BAR=2"}, baseline.flags.envs)
}

// Ordering is the one thing lifting cannot promise: user entries are always
// written after the templates' own, so one placed among them does not come back
// where it was put.
func TestAdopt_EntryAmongTemplateEntriesIsRefusedAsOrder(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string {
		return strings.Replace(s, `"-e", "TOOL_HOME=/opt/tool",`, `"-e", "EXTRA=1",`+"\n"+`    "-e", "TOOL_HOME=/opt/tool",`, 1)
	})

	baseline := readBaseline(t, catalog, dir)
	assert.False(t, baseline.adopt.adopted)
	require.NotEmpty(t, baseline.adopt.reasons)
	assert.Contains(t, strings.Join(baseline.adopt.reasons, "\n"), "order")
}

func TestAdopt_RemovedTemplateEntryIsRefused(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string {
		return strings.Replace(s, `"-e", "TOOL_HOME=/opt/tool",`+"\n", "", 1)
	})

	baseline := readBaseline(t, catalog, dir)
	assert.False(t, baseline.adopt.adopted)
	assert.Contains(t, strings.Join(baseline.adopt.reasons, "\n"), "comes from a selected template")
}

func TestAdopt_EditedExplicitPinMovesIntoTheSelection(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool:1.5.0"}})
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		return strings.Replace(s, "arg TOOL_VERSION=1.5.0", "arg TOOL_VERSION=2.0.0", 1)
	})

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	assert.Equal(t, []string{"tool:2.0.0"}, baseline.flags.selectDSLs)
}

func TestAdopt_UnknownKeyIsRefused(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "bogus = 1\n" })

	baseline := readBaseline(t, catalog, dir)
	assert.False(t, baseline.adopt.adopted)
	assert.Contains(t, strings.Join(baseline.adopt.reasons, "\n"), "`bogus` is not a setting booth reads")
}

func TestAdopt_InvalidTOMLIsRefused(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "port = \n" })

	baseline := readBaseline(t, catalog, dir)
	assert.False(t, baseline.adopt.adopted)
	assert.Contains(t, strings.Join(baseline.adopt.reasons, "\n"), "not valid TOML")
}

// A booth with no "# Configured by:" header was never generated, so there is no
// baseline to read an edit back against: it is hand-written, as before.
func TestAdopt_HandWrittenFromScratchIsNotAttempted(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(dir, ".booth"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "Boothfile"), []byte("setup tool 1.0.0\n"), 0o644))

	baseline := readBaseline(t, catalog, dir)
	assert.Equal(t, []string{"Boothfile"}, baseline.drifted)
	assert.False(t, baseline.adopt.attempted)
	assert.Empty(t, adoptReasonsText(baseline))
}

// The comparison regenerates with the booth's own APT snapshot, so a booth
// written on another day is not "edited" by the date alone.
func TestAdopt_OldAptSnapshotDoesNotCountAsAnEdit(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "timezone = \"UTC\"\n" })

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
}

// --- APT snapshot preservation (reconfigure keeps the booth's own date) ---

func TestApplyBoothAptSnapshot_KeepsExistingSnapshot(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "")
	dir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(dir, ".booth"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "Boothfile"),
		[]byte("env APT_SNAPSHOT=20250101T000000Z\n\nsetup go\n"), 0o644))

	out := &output.BoothOutput{Boothfile: &output.BoothfileContent{Content: "setup go\n"}}
	applyBoothAptSnapshot(out, dir)
	assert.True(t, strings.HasPrefix(out.Boothfile.Content, "env APT_SNAPSHOT=20250101T000000Z\n"),
		"a reconfigure must not move the freeze date: %q", out.Boothfile.Content)
}

func TestApplyBoothAptSnapshot_EnvOverrideMovesIt(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "20270101T000000Z")
	dir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(dir, ".booth"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "Boothfile"),
		[]byte("env APT_SNAPSHOT=20250101T000000Z\n\nsetup go\n"), 0o644))

	out := &output.BoothOutput{Boothfile: &output.BoothfileContent{Content: "setup go\n"}}
	applyBoothAptSnapshot(out, dir)
	assert.True(t, strings.HasPrefix(out.Boothfile.Content, "env APT_SNAPSHOT=20270101T000000Z\n"))
}

func TestApplyBoothAptSnapshot_NewBoothGetsToday(t *testing.T) {
	t.Setenv("CB_APT_SNAPSHOT", "")
	out := &output.BoothOutput{Boothfile: &output.BoothfileContent{Content: "setup go\n"}}
	applyBoothAptSnapshot(out, t.TempDir())
	assert.True(t, strings.HasPrefix(out.Boothfile.Content, "env APT_SNAPSHOT="+aptSnapshotID()+"\n"))
}

func TestTemplatesVersionFor(t *testing.T) {
	sel := []string{"go"}
	assert.Equal(t, "0.9.0", templatesVersionFor(initFlags{selectDSLs: sel}, "0.9.0"))
	assert.Equal(t, "0.8.0", templatesVersionFor(initFlags{selectDSLs: sel, version: "0.8.0"}, "0.9.0"))
	assert.Empty(t, templatesVersionFor(initFlags{selectDSLs: sel, templatesPath: "/local"}, "0.9.0"),
		"a local catalog has no release to record")
	assert.Empty(t, templatesVersionFor(initFlags{}, "0.9.0"), "no selection compiles no templates")
}

// A config.toml that cannot be read back must not hide what else blocks the
// Boothfile — the reasons name both, so fixing one does not just uncover the next.
func TestAdopt_ReportsBoothfileReasonsAlongsideConfigOnes(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string { return s + "bogus = 1\n" })
	editBoothFile(t, dir, "Boothfile", func(s string) string { return s + "run echo hi\n" })

	baseline := readBaseline(t, catalog, dir)
	assert.False(t, baseline.adopt.adopted)
	reasons := strings.Join(baseline.adopt.reasons, "\n")
	assert.Contains(t, reasons, "`bogus`")
	assert.Contains(t, reasons, "run echo hi")
}

// A hand-written Boothfile has no header, but config.toml still records how the
// booth was configured — reconfiguring must start from that, not from nothing.
func TestReadExistingBooth_FallsBackToConfigTomlHeader(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(dir, ".booth"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "Boothfile"),
		[]byte("# syntax=codingbooth/boothfile:1\n# Hand-written.\n"), 0o644))
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "config.toml"),
		[]byte("# Configured by: booth config --no-tui --overwrite --set timezone=UTC --select shell-history\n"), 0o644))

	flags := readExistingBooth(dir)
	assert.Equal(t, []string{"shell-history"}, flags.selectDSLs)
	assert.Equal(t, []string{"timezone=UTC"}, flags.sets)
}

// --- Stale fingerprint: the files are booth config's, .generated disagrees ---

func staleManifest(t *testing.T, dir string) {
	t.Helper()
	path := filepath.Join(dir, ".booth", output.ManifestName)
	data, err := os.ReadFile(path)
	require.NoError(t, err)
	stale := regexp.MustCompile(`sha256:[0-9a-f]+`).ReplaceAllString(string(data), "sha256:0000")
	require.NoError(t, os.WriteFile(path, []byte(stale), 0o644))
}

func TestReadBoothBaseline_StaleFingerprintOnly(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	staleManifest(t, dir)

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	assert.True(t, baseline.adopt.unchanged, "nothing to lift — only the fingerprint disagrees")
	assert.Empty(t, baseline.adoptedChanges)

	require.NoError(t, output.RefreshManifest(dir, baseline.edited))
	assert.Empty(t, output.Drifted(dir), "after the refresh the files are booth config's again")
}

// A read-back edit is described as the flag it became.
func TestReadBoothBaseline_DescribesLiftedEdit(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "config.toml", func(s string) string {
		return s + "timezone = \"Asia/Bangkok\"\n"
	})

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	assert.False(t, baseline.adopt.unchanged)
	assert.Equal(t, []string{"+ --set timezone=Asia/Bangkok"}, baseline.adoptedChanges)
}

// An added comment is an edit too, not a fingerprint-only difference.
func TestReadBoothBaseline_AddedCommentIsAnEdit(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "Boothfile", func(s string) string { return s + "# note\n" })

	baseline := readBaseline(t, catalog, dir)
	require.True(t, baseline.adopt.adopted, "reasons: %v", baseline.adopt.reasons)
	assert.False(t, baseline.adopt.unchanged)
}
