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

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func printSelection(t *testing.T, catalog, dir string, cli initFlags) (out, notes string, err error) {
	t.Helper()
	cli.templatesPath = catalog
	var o, n bytes.Buffer
	err = printBoothSelection(&o, &n, "0.0.0", dir, cli)
	return o.String(), n.String(), err
}

func TestConfigPrint_ListsTheRecordedSelection(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool:2.0.0"}})
	files := snapshotFiles(t, dir)

	out, notes, err := printSelection(t, catalog, dir, initFlags{})
	require.NoError(t, err)
	assert.Equal(t, "  - Tool (TOOL_VERSION=2.0.0)\n", out)
	assert.Empty(t, notes)
	assert.Equal(t, files, snapshotFiles(t, dir), "print writes nothing")
}

func TestConfigPrint_ShowsAHandEditedPinItReadsBack(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})
	editBoothFile(t, dir, "Boothfile", func(s string) string {
		return strings.Replace(s, "arg TOOL_VERSION=1.0.0", "arg TOOL_VERSION=3.1.0", 1)
	})

	out, _, err := printSelection(t, catalog, dir, initFlags{})
	require.NoError(t, err)
	assert.Equal(t, "  - Tool (TOOL_VERSION=3.1.0)\n", out)
}

func TestConfigPrint_PreviewsAReconfigureFlag(t *testing.T) {
	catalog := adoptCatalog(t)
	dir := adoptWorkspace(t, catalog, initFlags{selectDSLs: []string{"tool"}})

	out, _, err := printSelection(t, catalog, dir, parseInitFlags([]string{"--remove-select", "tool"}))
	require.NoError(t, err)
	assert.Equal(t, "No templates selected.\n", out)
}

func TestConfigPrint_RefusesAFolderWithoutABooth(t *testing.T) {
	_, _, err := printSelection(t, adoptCatalog(t), t.TempDir(), initFlags{})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "no booth configured")
}

func TestConfigPrint_RefusesAHandWrittenBoothfile(t *testing.T) {
	dir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(dir, ".booth"), 0o755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, ".booth", "Boothfile"), []byte("setup tool 1.0.0\n"), 0o644))

	_, _, err := printSelection(t, adoptCatalog(t), dir, initFlags{})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "not written by booth config")
}

func TestSummaryParams_FollowDeclarationOrder(t *testing.T) {
	tpl := &tmpl.Template{ParamOrder: []string{"Z", "A"}}
	values := map[string]string{"A": "1", "Z": "2", "extra": "3", "b": "4"}
	for range 20 { // map order is random; one pass could pass by luck
		assert.Equal(t, " (Z=2, A=1, b=4, extra=3)", summaryParams(tpl, values))
	}
	assert.Equal(t, "", summaryParams(tpl, nil))
}

func TestWriteSummary_ListsRemovedTools(t *testing.T) {
	var b bytes.Buffer
	writeSummary(&b, &selection.ResolvedSelection{Removed: []*tmpl.Template{{DisplayName: "glow"}}})
	assert.Equal(t, "  - glow (removed from the image)\n\n", b.String())
}

// snapshotFiles maps every file under dir/.booth to its content.
func snapshotFiles(t *testing.T, dir string) map[string]string {
	t.Helper()
	files := map[string]string{}
	require.NoError(t, filepath.Walk(filepath.Join(dir, ".booth"), func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return err
		}
		data, err := os.ReadFile(path)
		files[path] = string(data)
		return err
	}))
	return files
}
