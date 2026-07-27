// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"bytes"
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func writeTemplateTree(t *testing.T, root, category, name, displayName, boothfile string) {
	t.Helper()
	dir := filepath.Join(root, category, name)
	require.NoError(t, os.MkdirAll(dir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(root, category, "meta.toml"), []byte(
		"display-name = \""+category+"\"\norder = 10\n",
	), 0644))
	content := "display-name = \"" + displayName + "\"\nprimary = true\n\n[segments]\nBoothfile = \"\"\"\n" + boothfile + "\n\"\"\"\n"
	require.NoError(t, os.WriteFile(filepath.Join(dir, "template.toml"), []byte(content), 0644))
}

func TestMergeRegistries_AddsNewTemplate(t *testing.T) {
	stockDir := t.TempDir()
	projectDir := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeTemplateTree(t, projectDir, "project", "myapp", "My App", "setup myapp")

	stock, err := LoadRegistry(stockDir)
	require.NoError(t, err)
	project, err := LoadRegistry(projectDir)
	require.NoError(t, err)

	var warn bytes.Buffer
	merged := MergeRegistries(stock, project, &warn)
	require.Contains(t, merged.ByName, "go")
	require.Contains(t, merged.ByName, "myapp")
	assert.Equal(t, "My App", merged.ByName["myapp"].DisplayName)
	assert.Empty(t, warn.String())
}

func TestMergeRegistries_OverrideWarns(t *testing.T) {
	stockDir := t.TempDir()
	projectDir := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go stock")
	writeTemplateTree(t, projectDir, "project", "go", "Go Local", "setup go local")

	stock, err := LoadRegistry(stockDir)
	require.NoError(t, err)
	project, err := LoadRegistry(projectDir)
	require.NoError(t, err)

	var warn bytes.Buffer
	merged := MergeRegistries(stock, project, &warn)
	require.Contains(t, merged.ByName, "go")
	assert.Equal(t, "Go Local", merged.ByName["go"].DisplayName)
	assert.Equal(t, "project", merged.ByName["go"].CategoryName)
	assert.Contains(t, warn.String(), `project template "go" overrides built-in`)
	assert.Contains(t, warn.String(), `category "languages" → "project"`)

	// Stock languages category should no longer list go (or be dropped if empty)
	for _, cat := range merged.Categories {
		if cat.Name == "languages" {
			for _, tmpl := range cat.Templates {
				assert.NotEqual(t, "go", tmpl.Name)
			}
		}
	}
}

func TestLoadMergedRegistry_MissingProjectDir(t *testing.T) {
	stockDir := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")

	reg, err := LoadMergedRegistry(stockDir, t.TempDir(), nil)
	require.NoError(t, err)
	require.Contains(t, reg.ByName, "go")
	assert.Len(t, reg.ByName, 1)
}

func TestLoadMergedRegistry_FromProjectRoot(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	local := filepath.Join(projectRoot, ".booth", "templates")
	writeTemplateTree(t, local, "project", "myapp", "My App", "setup myapp")

	var warn bytes.Buffer
	reg, err := LoadMergedRegistry(stockDir, projectRoot, &warn)
	require.NoError(t, err)
	require.Contains(t, reg.ByName, "myapp")
	require.Contains(t, reg.ByName, "go")
	assert.Empty(t, warn.String())
}
