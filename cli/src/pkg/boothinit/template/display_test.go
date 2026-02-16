// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"bytes"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- computeNameWidth ---

func TestComputeNameWidth_BasicTemplates(t *testing.T) {
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				Templates: []*Template{
					{Name: "go", DisplayName: "Go"},
					{Name: "python", DisplayName: "Python"},
				},
			},
		},
	}
	nameW := computeNameWidth(registry, true)
	assert.Equal(t, 6, nameW) // "python" = 6 chars
}

func TestComputeNameWidth_WithExtensions(t *testing.T) {
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				Templates: []*Template{
					{
						Name:        "go",
						DisplayName: "Go",
						Extensions: []*Template{
							{Name: "linter", DisplayName: "Go Linter"},
						},
					},
				},
			},
		},
	}
	nameW := computeNameWidth(registry, true)
	// Extension "linter" (6 chars) + 4 indent = 10, vs "go" (2 chars). Max = 10.
	assert.Equal(t, 10, nameW)
}

func TestComputeNameWidth_EmptyRegistry(t *testing.T) {
	registry := &TemplateRegistry{}
	nameW := computeNameWidth(registry, true)
	assert.Equal(t, 0, nameW)
}

// --- FormatRegistryList ---

func TestFormatRegistryList_EmptyRegistry(t *testing.T) {
	var buf bytes.Buffer
	FormatRegistryList(&buf, &TemplateRegistry{}, true)
	assert.Empty(t, buf.String())
}

func TestFormatRegistryList_CategoryHeaders(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	assert.Contains(t, output, "Languages\n")
	assert.Contains(t, output, "Frameworks\n")
	assert.Contains(t, output, "Tools\n")
}

func TestFormatRegistryList_TemplateNames(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	// Template names should appear indented with 2 spaces
	assert.Contains(t, output, "  go")
	assert.Contains(t, output, "  python")
	assert.Contains(t, output, "  django")
	assert.Contains(t, output, "  neovim")
	assert.Contains(t, output, "  claude-code")
}

func TestFormatRegistryList_ShowsNonAutoExtensions(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	// Non-auto extensions should appear even with includeAutoExtensions=false
	assert.Contains(t, output, "    + linter")
	assert.Contains(t, output, "    + pip")
}

func TestFormatRegistryList_HidesAutoExtensions(t *testing.T) {
	autoTrue := true
	autoFalse := false
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				DisplayName: "Languages",
				Templates: []*Template{
					{
						Name:        "go",
						DisplayDesc: "Go toolchain",
						Extensions: []*Template{
							{Name: "linter", DisplayDesc: "Go linter", AutoSelect: &autoFalse},
							{Name: "vscode-ext", DisplayDesc: "Go VS Code extension", AutoSelect: &autoTrue},
						},
					},
				},
			},
		},
	}

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	// Non-auto extension should appear
	assert.Contains(t, output, "    + linter")
	// Auto-select extension should be hidden
	assert.NotContains(t, output, "vscode-ext")
}

func TestFormatRegistryList_ShowsAllExtensionsWhenEnabled(t *testing.T) {
	autoTrue := true
	autoFalse := false
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				DisplayName: "Languages",
				Templates: []*Template{
					{
						Name:        "go",
						DisplayDesc: "Go toolchain",
						Extensions: []*Template{
							{Name: "linter", DisplayDesc: "Go linter", AutoSelect: &autoFalse},
							{Name: "vscode-ext", DisplayDesc: "Go VS Code extension", AutoSelect: &autoTrue},
						},
					},
				},
			},
		},
	}

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, true)
	output := buf.String()

	// Both extensions should appear with includeAutoExtensions=true
	assert.Contains(t, output, "    + linter")
	assert.Contains(t, output, "    + vscode-ext")
	assert.Contains(t, output, "Go VS Code extension (auto)")
}

func TestFormatRegistryList_ShowsDescriptions(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	assert.Contains(t, output, "Go toolchain with gopls LSP and Delve debugger")
	assert.Contains(t, output, "Python with pip package manager and venv support")
	assert.Contains(t, output, "Anthropic Claude Code AI coding assistant")
}

func TestFormatRegistryList_NoTags(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	// Tags should NOT appear in the list output
	assert.NotContains(t, output, "[golang, backend]")
	assert.NotContains(t, output, "[python, scripting]")
}

func TestFormatRegistryList_AutoSelectIndicator(t *testing.T) {
	autoTrue := true
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				DisplayName: "Languages",
				Templates: []*Template{
					{
						Name:        "go",
						DisplayDesc: "Go toolchain",
						Extensions: []*Template{
							{Name: "vscode-ext", DisplayDesc: "Go VS Code extension", AutoSelect: &autoTrue},
						},
					},
				},
			},
		},
	}

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, true)
	output := buf.String()

	assert.Contains(t, output, "Go VS Code extension (auto)")
}

func TestFormatRegistryList_CategoryOrder(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	// Languages (order 1) before Frameworks (order 2) before Tools (order 3)
	langIdx := strings.Index(output, "Languages")
	fwIdx := strings.Index(output, "Frameworks")
	toolIdx := strings.Index(output, "Tools")

	assert.True(t, langIdx < fwIdx, "Languages should appear before Frameworks")
	assert.True(t, fwIdx < toolIdx, "Frameworks should appear before Tools")
}

func TestFormatRegistryList_TemplateOrderWithinCategory(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	// In Languages: go (order 10) before python (order 20)
	goIdx := strings.Index(output, "  go")
	pyIdx := strings.Index(output, "  python")
	assert.True(t, goIdx < pyIdx, "go should appear before python")
}

func TestFormatRegistryList_BlankLineBetweenCategories(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	// There should be a blank line between categories
	assert.Contains(t, output, "\n\nFrameworks")
	assert.Contains(t, output, "\n\nTools")
}

func TestFormatRegistryList_SingleCategory(t *testing.T) {
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				DisplayName: "TestCat",
				Templates: []*Template{
					{Name: "item1", DisplayName: "Item One", DisplayDesc: "First item"},
				},
			},
		},
	}

	var buf bytes.Buffer
	FormatRegistryList(&buf, registry, false)
	output := buf.String()

	assert.Contains(t, output, "TestCat\n")
	assert.Contains(t, output, "  item1")
	assert.Contains(t, output, "First item")
	// No leading blank line for first category
	assert.True(t, strings.HasPrefix(output, "TestCat\n"))
}

// --- FormatTemplateDetail ---

func TestFormatTemplateDetail_BasicTemplate(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	goTmpl := registry.ByName["go"]
	require.NotNil(t, goTmpl)

	var buf bytes.Buffer
	FormatTemplateDetail(&buf, goTmpl, registry, false)
	output := buf.String()

	assert.Contains(t, output, "Go (go)")
	assert.Contains(t, output, "Category:    languages")
	assert.Contains(t, output, "Description: Go toolchain with gopls LSP and Delve debugger")
	assert.Contains(t, output, "Provides a complete Go development environment")
	assert.Contains(t, output, "Parameters:")
	assert.Contains(t, output, "GO_VERSION")
	assert.Contains(t, output, "default: 1.24")
	assert.Contains(t, output, "suggests: 1.22, 1.23, 1.24")
	assert.Contains(t, output, "Extensions:")
	assert.Contains(t, output, "linter")
	assert.Contains(t, output, "Tags: golang, backend")
}

func TestFormatTemplateDetail_NoParams(t *testing.T) {
	tmpl := &Template{
		Name:         "simple",
		CategoryName: "test",
		DisplayName:  "Simple",
		DisplayDesc:  "A simple template",
	}
	registry := &TemplateRegistry{}

	var buf bytes.Buffer
	FormatTemplateDetail(&buf, tmpl, registry, false)
	output := buf.String()

	assert.Contains(t, output, "Simple (simple)")
	assert.NotContains(t, output, "Parameters:")
	assert.NotContains(t, output, "Extensions:")
	assert.Contains(t, output, "Requires: (none)")
}

func TestFormatTemplateDetail_WithRequires(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	django := registry.ByName["django"]
	require.NotNil(t, django)

	var buf bytes.Buffer
	FormatTemplateDetail(&buf, django, registry, false)
	output := buf.String()

	assert.Contains(t, output, "Requires: python")
}

func TestFormatTemplateDetail_WithDetail(t *testing.T) {
	tmpl := &Template{
		Name:          "test",
		CategoryName:  "testing",
		DisplayName:   "Test Template",
		DisplayDesc:   "Short description",
		DisplayDetail: "This is a longer detailed description of the template.",
	}
	registry := &TemplateRegistry{}

	var buf bytes.Buffer
	FormatTemplateDetail(&buf, tmpl, registry, false)
	output := buf.String()

	assert.Contains(t, output, "Description: Short description")
	assert.Contains(t, output, "This is a longer detailed description of the template.")
}
