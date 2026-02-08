// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testdataDir() string {
	_, currentFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(currentFile), "testdata", "templates")
}

// --- ParseSegmentOrder ---

func TestParseSegmentOrder_BoothfileDefault(t *testing.T) {
	order, ok := parseSegmentOrder("Boothfile", "Boothfile", "")
	assert.True(t, ok)
	assert.Equal(t, DefaultSegmentOrder, order)
}

func TestParseSegmentOrder_BoothfileWithOrder(t *testing.T) {
	order, ok := parseSegmentOrder("Boothfile--30", "Boothfile", "")
	assert.True(t, ok)
	assert.Equal(t, 30, order)
}

func TestParseSegmentOrder_BoothfileWithOrder80(t *testing.T) {
	order, ok := parseSegmentOrder("Boothfile--80", "Boothfile", "")
	assert.True(t, ok)
	assert.Equal(t, 80, order)
}

func TestParseSegmentOrder_StartupDefault(t *testing.T) {
	order, ok := parseSegmentOrder("startup.sh", "startup", ".sh")
	assert.True(t, ok)
	assert.Equal(t, DefaultSegmentOrder, order)
}

func TestParseSegmentOrder_StartupWithOrder(t *testing.T) {
	order, ok := parseSegmentOrder("startup--10.sh", "startup", ".sh")
	assert.True(t, ok)
	assert.Equal(t, 10, order)
}

func TestParseSegmentOrder_NoMatch(t *testing.T) {
	_, ok := parseSegmentOrder("readme.md", "Boothfile", "")
	assert.False(t, ok)
}

func TestParseSegmentOrder_WrongPrefix(t *testing.T) {
	_, ok := parseSegmentOrder("Dockerfile", "Boothfile", "")
	assert.False(t, ok)
}

func TestParseSegmentOrder_WrongSuffix(t *testing.T) {
	_, ok := parseSegmentOrder("startup.txt", "startup", ".sh")
	assert.False(t, ok)
}

func TestParseSegmentOrder_InvalidOrder(t *testing.T) {
	_, ok := parseSegmentOrder("Boothfile--abc", "Boothfile", "")
	assert.False(t, ok)
}

func TestParseSegmentOrder_PartialPrefix(t *testing.T) {
	_, ok := parseSegmentOrder("Booth", "Boothfile", "")
	assert.False(t, ok)
}

func TestParseSegmentOrder_ExtraChars(t *testing.T) {
	_, ok := parseSegmentOrder("Boothfile-extra", "Boothfile", "")
	assert.False(t, ok)
}

// --- LoadRegistry ---

func TestLoadRegistry_FullFixture(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)
	require.NotNil(t, registry)

	// Should have 3 categories sorted by order
	require.Len(t, registry.Categories, 3)
	assert.Equal(t, "Languages", registry.Categories[0].DisplayName)
	assert.Equal(t, "Frameworks", registry.Categories[1].DisplayName)
	assert.Equal(t, "Tools", registry.Categories[2].DisplayName)
}

func TestLoadRegistry_CategoryOrdering(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	assert.Equal(t, 1, registry.Categories[0].Order)
	assert.Equal(t, 2, registry.Categories[1].Order)
	assert.Equal(t, 3, registry.Categories[2].Order)
}

func TestLoadRegistry_ByNameLookup(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	// All top-level templates should be in ByName
	assert.Contains(t, registry.ByName, "go")
	assert.Contains(t, registry.ByName, "python")
	assert.Contains(t, registry.ByName, "django")
	assert.Contains(t, registry.ByName, "neovim")
	assert.Contains(t, registry.ByName, "claude-code")

	// Extensions should NOT be in ByName
	assert.NotContains(t, registry.ByName, "linter")
}

func TestLoadRegistry_NonexistentDir(t *testing.T) {
	_, err := LoadRegistry("/nonexistent/path")
	assert.Error(t, err)
}

// --- Category loading ---

func TestLoadRegistry_LanguagesCategory(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	languages := registry.Categories[0]
	assert.Equal(t, "languages", languages.Name)
	assert.Equal(t, "Languages", languages.DisplayName)

	// Should have 2 templates sorted by display-order (go=10, python=20)
	require.Len(t, languages.Templates, 2)
	assert.Equal(t, "go", languages.Templates[0].Name)
	assert.Equal(t, "python", languages.Templates[1].Name)
}

// --- Go template ---

func TestLoadRegistry_GoTemplate(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	goTmpl := registry.ByName["go"]
	require.NotNil(t, goTmpl)

	assert.Equal(t, "Go", goTmpl.DisplayName)
	assert.Equal(t, "Go language toolchain", goTmpl.DisplayDesc)
	assert.Equal(t, 10, goTmpl.DisplayOrder)
	assert.Equal(t, "languages", goTmpl.CategoryName)
	assert.ElementsMatch(t, []string{"golang", "backend"}, goTmpl.Tags)
}

func TestLoadRegistry_GoTemplateParams(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	goTmpl := registry.ByName["go"]
	require.Contains(t, goTmpl.Params, "GO_VERSION")

	param := goTmpl.Params["GO_VERSION"]
	assert.Equal(t, "1.24", param.Default)
	assert.ElementsMatch(t, []string{"1.22", "1.23", "1.24"}, param.Suggests)
}

func TestLoadRegistry_GoTemplateRunArgs(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	goTmpl := registry.ByName["go"]
	assert.Equal(t, []string{"-e", "GOPROXY=https://proxy.golang.org,direct"}, goTmpl.RunArgs)
}

func TestLoadRegistry_GoTemplateBoothfile(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	goTmpl := registry.ByName["go"]
	require.Len(t, goTmpl.BoothfileSegments, 1)
	assert.Equal(t, DefaultSegmentOrder, goTmpl.BoothfileSegments[0].Order)
	assert.Contains(t, goTmpl.BoothfileSegments[0].Content, "setup go ${GO_VERSION}")
}

func TestLoadRegistry_GoExtension(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	goTmpl := registry.ByName["go"]
	require.Len(t, goTmpl.Extensions, 1)

	linter := goTmpl.Extensions[0]
	assert.Equal(t, "linter", linter.Name)
	assert.Equal(t, "Go Linter", linter.DisplayName)
	assert.Equal(t, false, *linter.AutoSelect)

	// Extension has its own Boothfile
	require.Len(t, linter.BoothfileSegments, 1)
	assert.Contains(t, linter.BoothfileSegments[0].Content, "install go golangci-lint")
}

// --- Python template ---

func TestLoadRegistry_PythonTemplate(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	py := registry.ByName["python"]
	require.NotNil(t, py)

	assert.Equal(t, "Python", py.DisplayName)
	assert.Equal(t, 20, py.DisplayOrder)
}

func TestLoadRegistry_PythonStartup(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	py := registry.ByName["python"]
	require.Len(t, py.StartupSegments, 1)
	assert.Equal(t, DefaultSegmentOrder, py.StartupSegments[0].Order)
	assert.Contains(t, py.StartupSegments[0].Content, "Python environment ready")
}

func TestLoadRegistry_PythonHomeSeed(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	py := registry.ByName["python"]
	require.Len(t, py.HomeSeed, 1)
	assert.Equal(t, ".python_history", py.HomeSeed[0].RelPath)
}

// --- Django template ---

func TestLoadRegistry_DjangoTemplate(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	django := registry.ByName["django"]
	require.NotNil(t, django)

	assert.Equal(t, "Django", django.DisplayName)
	assert.Equal(t, "frameworks", django.CategoryName)
	assert.Equal(t, []string{"python"}, django.Requires)
}

func TestLoadRegistry_DjangoSetups(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	django := registry.ByName["django"]
	require.Len(t, django.Setups, 1)
	assert.Equal(t, "django--setup.sh", django.Setups[0].RelPath)
}

// --- Neovim template ---

func TestLoadRegistry_NeovimHome(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	nvim := registry.ByName["neovim"]
	require.NotNil(t, nvim)
	require.Len(t, nvim.Home, 1)
	assert.Equal(t, filepath.Join(".config", "nvim", "init.lua"), nvim.Home[0].RelPath)
}

// --- Claude Code template (ordered segments) ---

func TestLoadRegistry_ClaudeCodeBoothfileSegments(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	cc := registry.ByName["claude-code"]
	require.NotNil(t, cc)

	// Should have 2 segments sorted by order (30, 80)
	require.Len(t, cc.BoothfileSegments, 2)
	assert.Equal(t, 30, cc.BoothfileSegments[0].Order)
	assert.Contains(t, cc.BoothfileSegments[0].Content, "setup nodejs 20")
	assert.Equal(t, 80, cc.BoothfileSegments[1].Order)
	assert.Contains(t, cc.BoothfileSegments[1].Content, "npm install")
}

func TestLoadRegistry_ClaudeCodeStartupSegments(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	cc := registry.ByName["claude-code"]

	// Should have 2 segments sorted by order (10, 90)
	require.Len(t, cc.StartupSegments, 2)
	assert.Equal(t, 10, cc.StartupSegments[0].Order)
	assert.Contains(t, cc.StartupSegments[0].Content, "Setting up Claude Code")
	assert.Equal(t, 90, cc.StartupSegments[1].Order)
	assert.Contains(t, cc.StartupSegments[1].Content, "Claude Code ready")
}

func TestLoadRegistry_ClaudeCodeDind(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	cc := registry.ByName["claude-code"]
	require.NotNil(t, cc.Dind)
	assert.True(t, *cc.Dind)
}

// --- Optional fields ---

func TestLoadRegistry_NilDind(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	// Go template doesn't set dind
	goTmpl := registry.ByName["go"]
	assert.Nil(t, goTmpl.Dind)
}

func TestLoadRegistry_NilAutoSelect(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	// Top-level templates don't set auto-select
	goTmpl := registry.ByName["go"]
	assert.Nil(t, goTmpl.AutoSelect)
}

func TestLoadRegistry_EmptySegments(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	// Neovim has no Boothfile or startup segments
	nvim := registry.ByName["neovim"]
	assert.Empty(t, nvim.BoothfileSegments)
	assert.Empty(t, nvim.StartupSegments)
}

func TestLoadRegistry_EmptyExtensions(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	// Python has no extensions
	py := registry.ByName["python"]
	assert.Empty(t, py.Extensions)
}

// --- Duplicate template names ---

func TestLoadRegistry_DuplicateTemplateNames(t *testing.T) {
	tmpDir := t.TempDir()

	// Create two categories with templates sharing the same name
	cat1Dir := filepath.Join(tmpDir, "cat1")
	cat2Dir := filepath.Join(tmpDir, "cat2")
	tmpl1Dir := filepath.Join(cat1Dir, "dupe")
	tmpl2Dir := filepath.Join(cat2Dir, "dupe")

	require.NoError(t, os.MkdirAll(tmpl1Dir, 0755))
	require.NoError(t, os.MkdirAll(tmpl2Dir, 0755))

	require.NoError(t, os.WriteFile(filepath.Join(cat1Dir, "meta.toml"),
		[]byte("display-name = \"Cat1\"\norder = 1\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(cat2Dir, "meta.toml"),
		[]byte("display-name = \"Cat2\"\norder = 2\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmpl1Dir, "template.toml"),
		[]byte("display-name = \"Dupe\"\ndisplay-order = 1\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmpl2Dir, "template.toml"),
		[]byte("display-name = \"Dupe2\"\ndisplay-order = 1\n"), 0644))

	_, err := LoadRegistry(tmpDir)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "duplicate template name")
}

// --- Edge cases ---

func TestLoadRegistry_EmptyDir(t *testing.T) {
	tmpDir := t.TempDir()
	registry, err := LoadRegistry(tmpDir)
	require.NoError(t, err)
	assert.Empty(t, registry.Categories)
	assert.Empty(t, registry.ByName)
}

func TestLoadRegistry_SkipsDirWithoutMeta(t *testing.T) {
	tmpDir := t.TempDir()
	require.NoError(t, os.MkdirAll(filepath.Join(tmpDir, "no-meta"), 0755))

	registry, err := LoadRegistry(tmpDir)
	require.NoError(t, err)
	assert.Empty(t, registry.Categories)
}

func TestLoadRegistry_SkipsHiddenDirs(t *testing.T) {
	tmpDir := t.TempDir()
	hiddenDir := filepath.Join(tmpDir, ".hidden")
	require.NoError(t, os.MkdirAll(hiddenDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(hiddenDir, "meta.toml"),
		[]byte("display-name = \"Hidden\"\norder = 1\n"), 0644))

	registry, err := LoadRegistry(tmpDir)
	require.NoError(t, err)
	assert.Empty(t, registry.Categories)
}

func TestLoadRegistry_SkipsTemplateWithoutSpec(t *testing.T) {
	tmpDir := t.TempDir()
	catDir := filepath.Join(tmpDir, "mycat")
	tmplDir := filepath.Join(catDir, "nospec")
	require.NoError(t, os.MkdirAll(tmplDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(catDir, "meta.toml"),
		[]byte("display-name = \"MyCat\"\norder = 1\n"), 0644))
	// No template.toml in tmplDir

	registry, err := LoadRegistry(tmpDir)
	require.NoError(t, err)
	require.Len(t, registry.Categories, 1)
	assert.Empty(t, registry.Categories[0].Templates)
}
