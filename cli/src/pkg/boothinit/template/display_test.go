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

// --- formatTags ---

func TestFormatTags_Multiple(t *testing.T) {
	assert.Equal(t, "[golang, backend]", formatTags([]string{"golang", "backend"}))
}

func TestFormatTags_Single(t *testing.T) {
	assert.Equal(t, "[go]", formatTags([]string{"go"}))
}

func TestFormatTags_Empty(t *testing.T) {
	assert.Equal(t, "[]", formatTags([]string{}))
}

func TestFormatTags_Nil(t *testing.T) {
	assert.Equal(t, "[]", formatTags(nil))
}

// --- computeColumnWidths ---

func TestComputeColumnWidths_BasicTemplates(t *testing.T) {
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
	nameW, displayW := computeColumnWidths(registry)
	assert.Equal(t, 6, nameW)  // "python" = 6 chars
	assert.Equal(t, 6, displayW) // "Python" = 6 chars
}

func TestComputeColumnWidths_WithExtensions(t *testing.T) {
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
	nameW, displayW := computeColumnWidths(registry)
	// Extension "linter" (6 chars) + 4 indent = 10, vs "go" (2 chars). Max = 10.
	assert.Equal(t, 10, nameW)
	assert.Equal(t, 9, displayW) // "Go Linter" = 9 chars
}

func TestComputeColumnWidths_EmptyRegistry(t *testing.T) {
	registry := &TemplateRegistry{}
	nameW, displayW := computeColumnWidths(registry)
	assert.Equal(t, 0, nameW)
	assert.Equal(t, 0, displayW)
}

// --- FormatRegistry ---

func TestFormatRegistry_EmptyRegistry(t *testing.T) {
	var buf bytes.Buffer
	FormatRegistry(&buf, &TemplateRegistry{})
	assert.Empty(t, buf.String())
}

func TestFormatRegistry_CategoryHeaders(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	assert.Contains(t, output, "Languages\n")
	assert.Contains(t, output, "Frameworks\n")
	assert.Contains(t, output, "Tools\n")
}

func TestFormatRegistry_TemplateNames(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	// Template names should appear indented with 2 spaces
	assert.Contains(t, output, "  go")
	assert.Contains(t, output, "  python")
	assert.Contains(t, output, "  django")
	assert.Contains(t, output, "  neovim")
	assert.Contains(t, output, "  claude-code")
}

func TestFormatRegistry_ExtensionIndent(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	// Extensions should appear with "    + " prefix
	assert.Contains(t, output, "    + linter")
	assert.Contains(t, output, "    + pip")
}

func TestFormatRegistry_DisplayNames(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	assert.Contains(t, output, "Go")
	assert.Contains(t, output, "Python")
	assert.Contains(t, output, "Django")
	assert.Contains(t, output, "Neovim")
	assert.Contains(t, output, "Claude Code")
	assert.Contains(t, output, "Go Linter")
	assert.Contains(t, output, "pip requirements")
}

func TestFormatRegistry_Tags(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	assert.Contains(t, output, "[golang, backend]")
	assert.Contains(t, output, "[python, scripting]")
	assert.Contains(t, output, "[python, web]")
	assert.Contains(t, output, "[editor, vim]")
	assert.Contains(t, output, "[ai, assistant]")
}

func TestFormatRegistry_CategoryOrder(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	// Languages (order 1) before Frameworks (order 2) before Tools (order 3)
	langIdx := strings.Index(output, "Languages")
	fwIdx := strings.Index(output, "Frameworks")
	toolIdx := strings.Index(output, "Tools")

	assert.True(t, langIdx < fwIdx, "Languages should appear before Frameworks")
	assert.True(t, fwIdx < toolIdx, "Frameworks should appear before Tools")
}

func TestFormatRegistry_TemplateOrderWithinCategory(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	// In Languages: go (order 10) before python (order 20)
	goIdx := strings.Index(output, "  go")
	pyIdx := strings.Index(output, "  python")
	assert.True(t, goIdx < pyIdx, "go should appear before python")
}

func TestFormatRegistry_BlankLineBetweenCategories(t *testing.T) {
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	// There should be a blank line between categories
	assert.Contains(t, output, "\n\nFrameworks")
	assert.Contains(t, output, "\n\nTools")
}

func TestFormatRegistry_SingleCategory(t *testing.T) {
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				DisplayName: "TestCat",
				Templates: []*Template{
					{Name: "item1", DisplayName: "Item One", Tags: []string{"a"}},
				},
			},
		},
	}

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	assert.Contains(t, output, "TestCat\n")
	assert.Contains(t, output, "  item1")
	assert.Contains(t, output, "Item One")
	assert.Contains(t, output, "[a]")
	// No leading blank line for first category
	assert.True(t, strings.HasPrefix(output, "TestCat\n"))
}

func TestFormatRegistry_EmptyTags(t *testing.T) {
	registry := &TemplateRegistry{
		Categories: []*Category{
			{
				DisplayName: "Cat",
				Templates: []*Template{
					{Name: "notags", DisplayName: "No Tags"},
				},
			},
		},
	}

	var buf bytes.Buffer
	FormatRegistry(&buf, registry)
	output := buf.String()

	assert.Contains(t, output, "[]")
}
