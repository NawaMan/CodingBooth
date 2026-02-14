// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"path/filepath"
	"runtime"
	"testing"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func loadTestRegistry(t *testing.T) *tmpl.TemplateRegistry {
	t.Helper()
	_, currentFile, _, _ := runtime.Caller(0)
	testdataDir := filepath.Join(filepath.Dir(currentFile), "..", "template", "testdata", "templates")
	registry, err := tmpl.LoadRegistry(testdataDir)
	require.NoError(t, err)
	return registry
}

// --- Basic resolution ---

func TestResolve_SingleTemplate(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go"},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates, 1)
	assert.Equal(t, "go", resolved.Templates[0].Template.Name)
	assert.Equal(t, ExplicitSelect, resolved.Templates[0].SelectMode)
}

func TestResolve_MultipleTemplates(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go"},
		{Name: "python"},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates, 2)
	assert.Equal(t, "go", resolved.Templates[0].Template.Name)
	assert.Equal(t, "python", resolved.Templates[1].Template.Name)
}

// --- Param resolution ---

func TestResolve_ParamDefault(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go"},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Equal(t, "1.24", resolved.Templates[0].ParamValues["GO_VERSION"])
}

func TestResolve_ParamOverride(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go", Params: []string{"1.22"}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Equal(t, "1.22", resolved.Templates[0].ParamValues["GO_VERSION"])
}

func TestResolve_TooManyParams(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go", Params: []string{"1.22", "extra"}},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "too many parameters")
}

func TestResolve_NoParamsTemplate(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "neovim"},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Empty(t, resolved.Templates[0].ParamValues)
}

// --- Extension resolution ---

func TestResolve_ExplicitExtension(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go", Extensions: []ParsedExtension{{Name: "linter"}}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates[0].Extensions, 1)
	assert.Equal(t, "linter", resolved.Templates[0].Extensions[0].Extension.Name)
	assert.Equal(t, ExplicitSelect, resolved.Templates[0].Extensions[0].SelectMode)
}

func TestResolve_UnknownExtension(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go", Extensions: []ParsedExtension{{Name: "nonexistent"}}},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unknown extension")
}

func TestResolve_AutoSelectExtension(t *testing.T) {
	// Create a registry with an auto-select extension
	autoSelect := true
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name: "test",
				Extensions: []*tmpl.Template{
					{Name: "auto-ext", AutoSelect: &autoSelect},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test"},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates[0].Extensions, 1)
	assert.Equal(t, "auto-ext", resolved.Templates[0].Extensions[0].Extension.Name)
	assert.Equal(t, AutoSelected, resolved.Templates[0].Extensions[0].SelectMode)
}

func TestResolve_AutoSelectNotDuplicated(t *testing.T) {
	// If user explicitly selects an auto-select extension, it shouldn't appear twice
	autoSelect := true
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name: "test",
				Extensions: []*tmpl.Template{
					{Name: "auto-ext", AutoSelect: &autoSelect},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Extensions: []ParsedExtension{{Name: "auto-ext"}}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates[0].Extensions, 1)
}

// --- Exclude resolution ---

func TestResolve_ExcludeAutoSelectedExtension(t *testing.T) {
	autoSelect := true
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name: "test",
				Extensions: []*tmpl.Template{
					{Name: "credential", AutoSelect: &autoSelect},
					{Name: "other", AutoSelect: &autoSelect},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Excludes: []string{"credential"}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates[0].Extensions, 1)
	assert.Equal(t, "other", resolved.Templates[0].Extensions[0].Extension.Name)
}

func TestResolve_ExcludeAllAutoSelected(t *testing.T) {
	autoSelect := true
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name: "test",
				Extensions: []*tmpl.Template{
					{Name: "credential", AutoSelect: &autoSelect},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Excludes: []string{"credential"}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Empty(t, resolved.Templates[0].Extensions)
}

func TestResolve_ExcludeUnknownExtension(t *testing.T) {
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name:       "test",
				Extensions: []*tmpl.Template{},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Excludes: []string{"nonexistent"}},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unknown extension")
}

func TestResolve_ExcludeAndIncludeSameExtensionError(t *testing.T) {
	autoSelect := true
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name: "test",
				Extensions: []*tmpl.Template{
					{Name: "credential", AutoSelect: &autoSelect},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Extensions: []ParsedExtension{{Name: "credential"}}, Excludes: []string{"credential"}},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "both included")
}

// --- Requires validation ---

func TestResolve_RequiresSatisfied(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "python"},
		{Name: "django"},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates, 2)
}

func TestResolve_RequiresNotSatisfied(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "django"},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "requires")
	assert.Contains(t, err.Error(), "python")
}

// --- Extension param resolution ---

func TestResolve_ExtensionParams(t *testing.T) {
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"deno": {
				Name: "deno",
				Extensions: []*tmpl.Template{
					{
						Name:   "pkg",
						Params: map[string]tmpl.Param{"DENO_PKGS": {Default: "", Variadic: true}},
						ParamOrder: []string{"DENO_PKGS"},
					},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "deno", Extensions: []ParsedExtension{{Name: "pkg", Params: []string{"cowsay", "figlet"}}}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates[0].Extensions, 1)
	assert.Equal(t, "cowsay,figlet", resolved.Templates[0].Extensions[0].ParamValues["DENO_PKGS"])
}

func TestResolve_ExtensionParamsDefault(t *testing.T) {
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"java": {
				Name: "java",
				Extensions: []*tmpl.Template{
					{
						Name:   "maven",
						Params: map[string]tmpl.Param{"MAVEN_VERSION": {Default: "3.9"}},
						ParamOrder: []string{"MAVEN_VERSION"},
					},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "java", Extensions: []ParsedExtension{{Name: "maven"}}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Equal(t, "3.9", resolved.Templates[0].Extensions[0].ParamValues["MAVEN_VERSION"])
}

func TestResolve_ExtensionParamsOverride(t *testing.T) {
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"java": {
				Name: "java",
				Extensions: []*tmpl.Template{
					{
						Name:   "maven",
						Params: map[string]tmpl.Param{"MAVEN_VERSION": {Default: "3.9"}},
						ParamOrder: []string{"MAVEN_VERSION"},
					},
				},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "java", Extensions: []ParsedExtension{{Name: "maven", Params: []string{"4.0"}}}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Equal(t, "4.0", resolved.Templates[0].Extensions[0].ParamValues["MAVEN_VERSION"])
}

// --- Variadic param resolution ---

func TestResolve_VariadicParam(t *testing.T) {
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name:       "test",
				Params:     map[string]tmpl.Param{"PKGS": {Default: "", Variadic: true}},
				ParamOrder: []string{"PKGS"},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Params: []string{"a", "b", "c"}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Equal(t, "a,b,c", resolved.Templates[0].ParamValues["PKGS"])
}

func TestResolve_VariadicParamWithPrecedingParams(t *testing.T) {
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name: "test",
				Params: map[string]tmpl.Param{
					"FLAGS": {Default: ""},
					"PKGS":  {Default: "", Variadic: true},
				},
				ParamOrder: []string{"FLAGS", "PKGS"},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Params: []string{"-Agf", "cowsay", "figlet"}},
	}}

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	assert.Equal(t, "-Agf", resolved.Templates[0].ParamValues["FLAGS"])
	assert.Equal(t, "cowsay,figlet", resolved.Templates[0].ParamValues["PKGS"])
}

func TestResolve_NonVariadicTooManyParamsStillErrors(t *testing.T) {
	registry := &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{
			"test": {
				Name:       "test",
				Params:     map[string]tmpl.Param{"VERSION": {Default: "1.0"}},
				ParamOrder: []string{"VERSION"},
			},
		},
	}
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "test", Params: []string{"1.0", "extra"}},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "too many parameters")
}

// --- Error cases ---

func TestResolve_UnknownTemplate(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "nonexistent"},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unknown template")
}

func TestResolve_DuplicateSelection(t *testing.T) {
	registry := loadTestRegistry(t)
	parsed := &ParsedSelection{Items: []ParsedItem{
		{Name: "go"},
		{Name: "go"},
	}}

	_, err := Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "more than once")
}

// --- End-to-end parse + resolve ---

func TestParseAndResolve_EndToEnd(t *testing.T) {
	registry := loadTestRegistry(t)

	parsed, err := ParseSelectDSL("go:1.22+linter/python/claude-code")
	require.NoError(t, err)

	resolved, err := Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates, 3)

	// go with overridden param and linter extension
	assert.Equal(t, "go", resolved.Templates[0].Template.Name)
	assert.Equal(t, "1.22", resolved.Templates[0].ParamValues["GO_VERSION"])
	require.Len(t, resolved.Templates[0].Extensions, 1)
	assert.Equal(t, "linter", resolved.Templates[0].Extensions[0].Extension.Name)

	// python with default params
	assert.Equal(t, "python", resolved.Templates[1].Template.Name)
	assert.Equal(t, "3.12", resolved.Templates[1].ParamValues["PYTHON_VERSION"])

	// claude-code with no params
	assert.Equal(t, "claude-code", resolved.Templates[2].Template.Name)
}
