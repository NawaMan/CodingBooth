// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package template

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func loadSearchRegistry(t *testing.T) *TemplateRegistry {
	t.Helper()
	registry, err := LoadRegistry(testdataDir())
	require.NoError(t, err)
	return registry
}

// --- matchesPrefix ---

func TestMatchesPrefix_ByName(t *testing.T) {
	tmpl := &Template{Name: "go", DisplayName: "Go", Tags: []string{"golang"}}
	assert.True(t, matchesPrefix(tmpl, "go"))
}

func TestMatchesPrefix_ByDisplayName(t *testing.T) {
	tmpl := &Template{Name: "claude-code", DisplayName: "Claude Code", Tags: []string{"ai"}}
	assert.True(t, matchesPrefix(tmpl, "cl"))
}

func TestMatchesPrefix_ByTag(t *testing.T) {
	tmpl := &Template{Name: "go", DisplayName: "Go", Tags: []string{"golang", "backend"}}
	assert.True(t, matchesPrefix(tmpl, "back"))
}

func TestMatchesPrefix_CaseInsensitive_DisplayName(t *testing.T) {
	// "Claude Code" display name should match lowercase "cl" term
	tmpl := &Template{Name: "claude-code", DisplayName: "Claude Code", Tags: []string{"ai"}}
	assert.True(t, matchesPrefix(tmpl, "claude"))
}

func TestMatchesPrefix_NoMatch(t *testing.T) {
	tmpl := &Template{Name: "go", DisplayName: "Go", Tags: []string{"golang"}}
	assert.False(t, matchesPrefix(tmpl, "py"))
}

func TestMatchesPrefix_EmptyTerm(t *testing.T) {
	tmpl := &Template{Name: "go", DisplayName: "Go", Tags: []string{"golang"}}
	assert.True(t, matchesPrefix(tmpl, ""))
}

func TestMatchesPrefix_NoTags(t *testing.T) {
	tmpl := &Template{Name: "go", DisplayName: "Go"}
	assert.True(t, matchesPrefix(tmpl, "go"))
	assert.False(t, matchesPrefix(tmpl, "xyz"))
}

// --- Search ---

func TestSearch_ByTemplateName(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("go")

	// "go" matches the go template by name
	require.Len(t, result.Categories, 1)
	assert.Equal(t, "Languages", result.Categories[0].DisplayName)
	require.Len(t, result.Categories[0].Templates, 1)
	assert.Equal(t, "go", result.Categories[0].Templates[0].Name)
}

func TestSearch_ByTemplateName_IncludesAllExtensions(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("go")

	// When parent matches, all extensions are included
	goTmpl := result.Categories[0].Templates[0]
	require.Len(t, goTmpl.Extensions, 1)
	assert.Equal(t, "linter", goTmpl.Extensions[0].Name)
}

func TestSearch_ByDisplayName(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("Cl")

	// "Cl" matches "Claude Code" display-name
	require.Len(t, result.Categories, 1)
	assert.Equal(t, "Tools", result.Categories[0].DisplayName)
	require.Len(t, result.Categories[0].Templates, 1)
	assert.Equal(t, "claude-code", result.Categories[0].Templates[0].Name)
}

func TestSearch_ByTag(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("back")

	// "back" matches go's "backend" tag
	require.Len(t, result.Categories, 1)
	assert.Equal(t, "Languages", result.Categories[0].DisplayName)
	require.Len(t, result.Categories[0].Templates, 1)
	assert.Equal(t, "go", result.Categories[0].Templates[0].Name)
}

func TestSearch_CaseInsensitive(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("GO")

	require.Len(t, result.Categories, 1)
	require.Len(t, result.Categories[0].Templates, 1)
	assert.Equal(t, "go", result.Categories[0].Templates[0].Name)
}

func TestSearch_MultipleMatches(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("python")

	// "python" matches:
	// - python template (name and tag)
	// - django template (tag "python")
	// - pip extension (tag "python")
	// Since python parent matches, it includes all extensions.
	// Since django matches directly by tag, it's also included.
	require.Len(t, result.Categories, 2)

	assert.Equal(t, "Languages", result.Categories[0].DisplayName)
	require.Len(t, result.Categories[0].Templates, 1)
	assert.Equal(t, "python", result.Categories[0].Templates[0].Name)

	assert.Equal(t, "Frameworks", result.Categories[1].DisplayName)
	require.Len(t, result.Categories[1].Templates, 1)
	assert.Equal(t, "django", result.Categories[1].Templates[0].Name)
}

func TestSearch_NoMatch(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("xyz")

	assert.Empty(t, result.Categories)
	assert.Empty(t, result.ByName)
}

func TestSearch_EmptyTerm_ReturnsAll(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("")

	// Empty term matches everything (every string has prefix "")
	assert.Equal(t, len(registry.Categories), len(result.Categories))
}

func TestSearch_ExtensionMatch_OnlyMatchingExtensions(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("lint")

	// "lint" matches the "linter" extension name under go
	// Parent go doesn't match "lint", so only the linter extension is included
	require.Len(t, result.Categories, 1)
	assert.Equal(t, "Languages", result.Categories[0].DisplayName)
	require.Len(t, result.Categories[0].Templates, 1)

	goTmpl := result.Categories[0].Templates[0]
	assert.Equal(t, "go", goTmpl.Name)
	require.Len(t, goTmpl.Extensions, 1)
	assert.Equal(t, "linter", goTmpl.Extensions[0].Name)
}

func TestSearch_ExtensionMatchByTag(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("pip")

	// "pip" matches the pip extension's tag "pip"
	// Python parent also matches? Let's check: python name starts with "py" not "pip".
	// Python tags: ["python", "scripting"]. Neither starts with "pip".
	// So only the pip extension matches.
	found := false
	for _, cat := range result.Categories {
		for _, tmpl := range cat.Templates {
			if tmpl.Name == "python" {
				found = true
				// Only pip extension should be included
				require.Len(t, tmpl.Extensions, 1)
				assert.Equal(t, "pip", tmpl.Extensions[0].Name)
			}
		}
	}
	assert.True(t, found, "python template should appear due to pip extension match")
}

func TestSearch_CategoriesPreserveOrder(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("python")

	// Languages (order 1) should come before Frameworks (order 2)
	require.Len(t, result.Categories, 2)
	assert.Equal(t, "Languages", result.Categories[0].DisplayName)
	assert.Equal(t, "Frameworks", result.Categories[1].DisplayName)
}

func TestSearch_ByNameInByNameMap(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("go")

	_, exists := result.ByName["go"]
	assert.True(t, exists)
}

func TestSearch_ByTag_Assistant(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("assistant")

	// "assistant" tag on claude-code
	require.Len(t, result.Categories, 1)
	assert.Equal(t, "Tools", result.Categories[0].DisplayName)
	require.Len(t, result.Categories[0].Templates, 1)
	assert.Equal(t, "claude-code", result.Categories[0].Templates[0].Name)
}

func TestSearch_ByTag_Editor(t *testing.T) {
	registry := loadSearchRegistry(t)
	result := registry.Search("editor")

	// "editor" tag on neovim
	require.Len(t, result.Categories, 1)
	assert.Equal(t, "Tools", result.Categories[0].DisplayName)
	require.Len(t, result.Categories[0].Templates, 1)
	assert.Equal(t, "neovim", result.Categories[0].Templates[0].Name)
}
