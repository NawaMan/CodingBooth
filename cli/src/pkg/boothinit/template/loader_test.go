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

// --- ParseInlineSegments ---

func TestParseInlineSegments_BoothfileOnly(t *testing.T) {
	segs := map[string]string{
		"Boothfile": "setup go 1.24\n",
	}
	booth, startup, err := parseInlineSegments(segs)
	require.NoError(t, err)
	require.Len(t, booth, 1)
	assert.Equal(t, DefaultSegmentOrder, booth[0].Order)
	assert.Equal(t, "setup go 1.24\n", booth[0].Content)
	assert.Empty(t, startup)
}

func TestParseInlineSegments_OrderedBoothfile(t *testing.T) {
	segs := map[string]string{
		"Boothfile--80": "setup claude-code\n",
		"Boothfile--30": "setup nodejs 20\n",
	}
	booth, startup, err := parseInlineSegments(segs)
	require.NoError(t, err)
	require.Len(t, booth, 2)
	assert.Equal(t, 30, booth[0].Order)
	assert.Contains(t, booth[0].Content, "nodejs")
	assert.Equal(t, 80, booth[1].Order)
	assert.Contains(t, booth[1].Content, "claude-code")
	assert.Empty(t, startup)
}

func TestParseInlineSegments_StartupOnly(t *testing.T) {
	segs := map[string]string{
		"startup.sh": "echo ready\n",
	}
	booth, startup, err := parseInlineSegments(segs)
	require.NoError(t, err)
	assert.Empty(t, booth)
	require.Len(t, startup, 1)
	assert.Equal(t, DefaultSegmentOrder, startup[0].Order)
	assert.Equal(t, "echo ready\n", startup[0].Content)
}

func TestParseInlineSegments_Mixed(t *testing.T) {
	segs := map[string]string{
		"Boothfile":      "setup go 1.24\n",
		"startup--10.sh": "echo starting\n",
	}
	booth, startup, err := parseInlineSegments(segs)
	require.NoError(t, err)
	require.Len(t, booth, 1)
	require.Len(t, startup, 1)
	assert.Equal(t, 10, startup[0].Order)
}

func TestParseInlineSegments_UnrecognizedKey(t *testing.T) {
	segs := map[string]string{
		"Dockerfile": "FROM ubuntu\n",
	}
	_, _, err := parseInlineSegments(segs)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unrecognized segment key")
}

// --- mergeSegments ---

func TestMergeSegments_BothEmpty(t *testing.T) {
	merged, err := mergeSegments(nil, nil)
	require.NoError(t, err)
	assert.Empty(t, merged)
}

func TestMergeSegments_FileOnly(t *testing.T) {
	file := []Segment{{Order: 30, Content: "file content"}}
	merged, err := mergeSegments(file, nil)
	require.NoError(t, err)
	assert.Equal(t, file, merged)
}

func TestMergeSegments_InlineOnly(t *testing.T) {
	inline := []Segment{{Order: 50, Content: "inline content"}}
	merged, err := mergeSegments(nil, inline)
	require.NoError(t, err)
	assert.Equal(t, inline, merged)
}

func TestMergeSegments_DifferentOrders(t *testing.T) {
	file := []Segment{{Order: 30, Content: "file early"}}
	inline := []Segment{{Order: 80, Content: "inline late"}}
	merged, err := mergeSegments(file, inline)
	require.NoError(t, err)
	require.Len(t, merged, 2)
	assert.Equal(t, 30, merged[0].Order)
	assert.Equal(t, "file early", merged[0].Content)
	assert.Equal(t, 80, merged[1].Order)
	assert.Equal(t, "inline late", merged[1].Content)
}

func TestMergeSegments_DuplicateOrderError(t *testing.T) {
	file := []Segment{{Order: 50, Content: "file"}}
	inline := []Segment{{Order: 50, Content: "inline"}}
	_, err := mergeSegments(file, inline)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "duplicate segment order 50")
}

func TestMergeSegments_MultipleSegmentsSorted(t *testing.T) {
	file := []Segment{{Order: 60, Content: "f60"}, {Order: 20, Content: "f20"}}
	inline := []Segment{{Order: 40, Content: "i40"}, {Order: 10, Content: "i10"}}
	merged, err := mergeSegments(file, inline)
	require.NoError(t, err)
	require.Len(t, merged, 4)
	assert.Equal(t, 10, merged[0].Order)
	assert.Equal(t, 20, merged[1].Order)
	assert.Equal(t, 40, merged[2].Order)
	assert.Equal(t, 60, merged[3].Order)
}

// --- Mixed source loading (file + inline segments with different orders) ---

func TestLoadRegistry_MixedBoothfileSegments(t *testing.T) {
	tmpDir := t.TempDir()
	catDir := filepath.Join(tmpDir, "mycat")
	tmplDir := filepath.Join(catDir, "mixed")
	require.NoError(t, os.MkdirAll(tmplDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(catDir, "meta.toml"),
		[]byte("display-name = \"MyCat\"\norder = 1\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "template.toml"),
		[]byte("display-name = \"Mixed\"\ndisplay-order = 1\n\n[segments]\n\"Boothfile--10\" = \"inline early\"\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "Boothfile--30"),
		[]byte("file later\n"), 0644))

	registry, err := LoadRegistry(tmpDir)
	require.NoError(t, err)

	tmpl := registry.ByName["mixed"]
	require.NotNil(t, tmpl)
	require.Len(t, tmpl.BoothfileSegments, 2)
	assert.Equal(t, 10, tmpl.BoothfileSegments[0].Order)
	assert.Equal(t, "inline early", tmpl.BoothfileSegments[0].Content)
	assert.Equal(t, 30, tmpl.BoothfileSegments[1].Order)
	assert.Equal(t, "file later\n", tmpl.BoothfileSegments[1].Content)
}

func TestLoadRegistry_DuplicateBoothfileOrderError(t *testing.T) {
	tmpDir := t.TempDir()
	catDir := filepath.Join(tmpDir, "mycat")
	tmplDir := filepath.Join(catDir, "conflict")
	require.NoError(t, os.MkdirAll(tmplDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(catDir, "meta.toml"),
		[]byte("display-name = \"MyCat\"\norder = 1\n"), 0644))
	// Both inline and file use default order 50
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "template.toml"),
		[]byte("display-name = \"Conflict\"\ndisplay-order = 1\n\n[segments]\nBoothfile = \"setup go\"\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "Boothfile"),
		[]byte("setup go\n"), 0644))

	_, err := LoadRegistry(tmpDir)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "duplicate segment order 50")
}

func TestLoadRegistry_MixedStartupSegments(t *testing.T) {
	tmpDir := t.TempDir()
	catDir := filepath.Join(tmpDir, "mycat")
	tmplDir := filepath.Join(catDir, "mixed-startup")
	require.NoError(t, os.MkdirAll(tmplDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(catDir, "meta.toml"),
		[]byte("display-name = \"MyCat\"\norder = 1\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "template.toml"),
		[]byte("display-name = \"MixedStartup\"\ndisplay-order = 1\n\n[segments]\n\"startup--20.sh\" = \"echo inline\"\n"), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(tmplDir, "startup--70.sh"),
		[]byte("echo file\n"), 0644))

	registry, err := LoadRegistry(tmpDir)
	require.NoError(t, err)

	tmpl := registry.ByName["mixed-startup"]
	require.NotNil(t, tmpl)
	require.Len(t, tmpl.StartupSegments, 2)
	assert.Equal(t, 20, tmpl.StartupSegments[0].Order)
	assert.Equal(t, 70, tmpl.StartupSegments[1].Order)
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
