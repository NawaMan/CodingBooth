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
	assert.False(t, merged.ByName["go"].Local)
	assert.True(t, merged.ByName["myapp"].Local)
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
	assert.True(t, merged.ByName["go"].Local)
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

// writeBareTemplate writes a template.toml with only a segment — no meta.toml,
// no display keys — plus any extra lines.
func writeBareTemplate(t *testing.T, root, category, name, extra string) {
	t.Helper()
	dir := filepath.Join(root, category, name)
	require.NoError(t, os.MkdirAll(dir, 0755))
	content := extra + "[segments]\nBoothfile = \"\"\"\nsetup " + name + "\n\"\"\"\n"
	require.NoError(t, os.WriteFile(filepath.Join(dir, "template.toml"), []byte(content), 0644))
}

func projectCategory(t *testing.T, reg *TemplateRegistry) *Category {
	t.Helper()
	for _, c := range reg.Categories {
		if c.Name == ProjectCategoryName {
			return c
		}
	}
	t.Fatalf("no %q category", ProjectCategoryName)
	return nil
}

func TestLoadMergedRegistry_ProjectTemplateNeedsNoMetaOrDisplayKeys(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeBareTemplate(t, filepath.Join(projectRoot, ".booth", "templates"), "project", "native-libs", "")

	reg, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.NoError(t, err)

	cat := projectCategory(t, reg)
	assert.Equal(t, ProjectCategoryDisplayName, cat.DisplayName)
	assert.Equal(t, ProjectCategoryOrder, cat.Order)
	assert.Equal(t, ProjectCategoryName, reg.Categories[0].Name, "project category sorts first")

	tmpl := reg.ByName["native-libs"]
	require.NotNil(t, tmpl)
	assert.Equal(t, "native-libs", tmpl.DisplayName, "display-name falls back to the template name")
	assert.True(t, tmpl.Primary, "primary defaults to true for a project template")
	assert.True(t, tmpl.Local)
	require.Len(t, tmpl.BoothfileSegments, 1)
}

func TestLoadMergedRegistry_ProjectTemplateKeepsExplicitPrimaryFalse(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeBareTemplate(t, filepath.Join(projectRoot, ".booth", "templates"), "project", "quiet", "primary = false\n")

	reg, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.NoError(t, err)
	assert.False(t, reg.ByName["quiet"].Primary)
}

func TestLoadMergedRegistry_AllProjectTemplatesShareOneCategory(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	local := filepath.Join(projectRoot, ".booth", "templates")
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeTemplateTree(t, local, "languages", "go", "Our Go", "setup go 1.24") // overrides stock, with a meta.toml
	writeBareTemplate(t, local, "tools", "native-libs", "")                   // no meta.toml
	require.NoError(t, os.MkdirAll(filepath.Join(local, "project"), 0755))    // project meta names the category
	require.NoError(t, os.WriteFile(filepath.Join(local, "project", "meta.toml"),
		[]byte("display-name = \"Acme\"\norder = 0\n"), 0644))

	reg, err := LoadMergedRegistry(stockDir, projectRoot, &bytes.Buffer{})
	require.NoError(t, err)

	cat := projectCategory(t, reg)
	assert.Equal(t, "Acme", cat.DisplayName, "project/meta.toml still names the category")
	var names []string
	for _, tmpl := range cat.Templates {
		names = append(names, tmpl.Name)
		assert.Equal(t, ProjectCategoryName, tmpl.CategoryName)
	}
	assert.ElementsMatch(t, []string{"go", "native-libs"}, names)
	for _, c := range reg.Categories {
		assert.NotEqual(t, "tools", c.Name, "a local folder is not a category of its own")
		if c.Name == "languages" {
			assert.Empty(t, c.Templates, "the overridden stock go left Languages")
		}
	}
}

func TestLoadRegistry_StockStillRequiresMeta(t *testing.T) {
	stockDir := t.TempDir()
	writeBareTemplate(t, stockDir, "tools", "native-libs", "")

	reg, err := LoadRegistry(stockDir)
	require.NoError(t, err)
	assert.Empty(t, reg.Categories)
	assert.NotContains(t, reg.ByName, "native-libs")
}
