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
	writeFlatProjectTemplate(t, projectRoot, "myapp.toml", "display-name = \"My App\"\nprimary = true\n\n[segments]\nBoothfile = \"\"\"\nsetup myapp\n\"\"\"\n")

	var warn bytes.Buffer
	reg, err := LoadMergedRegistry(stockDir, projectRoot, &warn)
	require.NoError(t, err)
	require.Contains(t, reg.ByName, "myapp")
	require.Contains(t, reg.ByName, "go")
	assert.Empty(t, warn.String())
}

// writeFlatProjectTemplate writes .booth/templates/<name>.toml.
func writeFlatProjectTemplate(t *testing.T, projectRoot, name, content string) {
	t.Helper()
	dir := filepath.Join(projectRoot, ".booth", "templates")
	require.NoError(t, os.MkdirAll(dir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(dir, name), []byte(content), 0644))
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
	writeFlatProjectTemplate(t, projectRoot, "native-libs.toml", "[segments]\nBoothfile = \"\"\"\nsetup native-libs\n\"\"\"\n")

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
	writeFlatProjectTemplate(t, projectRoot, "quiet.toml", "primary = false\n\n[segments]\nBoothfile = \"\"\"\nsetup quiet\n\"\"\"\n")

	reg, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.NoError(t, err)
	assert.False(t, reg.ByName["quiet"].Primary)
}

func TestLoadMergedRegistry_FlatFilesShareOneCategory(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeFlatProjectTemplate(t, projectRoot, "go.toml", "display-name = \"Our Go\"\n\n[segments]\nBoothfile = \"\"\"\nsetup go 1.24\n\"\"\"\n")
	writeFlatProjectTemplate(t, projectRoot, "native-libs.toml", "[segments]\nBoothfile = \"\"\"\nsetup native-libs\n\"\"\"\n")
	writeFlatProjectTemplate(t, projectRoot, "native-libs--fancy--extension.toml", "[segments]\nBoothfile = \"\"\"\nsetup native-libs-fancy\n\"\"\"\n")

	var warn bytes.Buffer
	reg, err := LoadMergedRegistry(stockDir, projectRoot, &warn)
	require.NoError(t, err)

	cat := projectCategory(t, reg)
	assert.Equal(t, ProjectCategoryDisplayName, cat.DisplayName)
	var names []string
	for _, tmpl := range cat.Templates {
		names = append(names, tmpl.Name)
		assert.Equal(t, ProjectCategoryName, tmpl.CategoryName)
	}
	assert.ElementsMatch(t, []string{"go", "native-libs"}, names)
	require.Len(t, reg.ByName["native-libs"].Extensions, 1)
	assert.Equal(t, "fancy", reg.ByName["native-libs"].Extensions[0].Name)
	assert.Contains(t, warn.String(), `project template "go" overrides built-in`)
	for _, c := range reg.Categories {
		if c.Name == "languages" {
			assert.Empty(t, c.Templates, "the overridden stock go left Languages")
		}
	}
}

func TestLoadMergedRegistry_ProjectDirectoryIsAnError(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	dir := filepath.Join(projectRoot, ".booth", "templates", "project")
	require.NoError(t, os.MkdirAll(dir, 0755))

	_, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "is a directory")
	assert.Contains(t, err.Error(), "<name>.toml")
}

func TestLoadMergedRegistry_ProjectMetaTomlIsAnError(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeFlatProjectTemplate(t, projectRoot, "meta.toml", "display-name = \"Acme\"\norder = 0\n")

	_, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "meta.toml")
	assert.Contains(t, err.Error(), "This project")
}

func TestLoadMergedRegistry_ExtensionNeedsParentPrefix(t *testing.T) {
	stockDir := t.TempDir()
	projectRoot := t.TempDir()
	writeTemplateTree(t, stockDir, "languages", "go", "Go", "setup go")
	writeFlatProjectTemplate(t, projectRoot, "fancy--extension.toml", "[segments]\nBoothfile = \"\"\"\nsetup fancy\n\"\"\"\n")

	_, err := LoadMergedRegistry(stockDir, projectRoot, nil)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "needs a parent prefix")
}

func TestLoadRegistry_StockStillRequiresMeta(t *testing.T) {
	stockDir := t.TempDir()
	writeBareTemplate(t, stockDir, "tools", "native-libs", "")

	reg, err := LoadRegistry(stockDir)
	require.NoError(t, err)
	assert.Empty(t, reg.Categories)
	assert.NotContains(t, reg.ByName, "native-libs")
}
