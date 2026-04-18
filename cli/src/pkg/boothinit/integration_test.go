// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothinit_test

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/compiler"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func testdataDir(t *testing.T) string {
	t.Helper()
	_, currentFile, _, _ := runtime.Caller(0)
	return filepath.Join(filepath.Dir(currentFile), "template", "testdata", "templates")
}

func loadRegistry(t *testing.T) *tmpl.TemplateRegistry {
	t.Helper()
	registry, err := tmpl.LoadRegistry(testdataDir(t))
	require.NoError(t, err)
	return registry
}

// pipeline runs the full pipeline: parse DSL → resolve → compile → write
func pipeline(t *testing.T, dsl string) (*output.BoothOutput, string) {
	t.Helper()
	registry := loadRegistry(t)

	parsed, err := selection.ParseSelectDSL(dsl)
	require.NoError(t, err)

	resolved, err := selection.Resolve(parsed, registry)
	require.NoError(t, err)

	out, err := compiler.Compile(resolved)
	require.NoError(t, err)

	targetDir := t.TempDir()
	err = output.WriteOutput(out, targetDir)
	require.NoError(t, err)

	return out, targetDir
}

// --- Basic: single template ---

func TestIntegration_Basic_SingleGo(t *testing.T) {
	out, targetDir := pipeline(t, "go")

	// Config
	require.NotNil(t, out.Config)
	assert.Equal(t, []string{"-e", "GOPROXY=https://proxy.golang.org,direct"}, out.Config.RunArgs)

	// Boothfile generated with ARG and segment
	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "arg GO_VERSION=1.24")
	assert.Contains(t, out.Boothfile.Content, "setup go ${GO_VERSION}")

	// No startup from go template alone
	assert.Empty(t, out.Startups)

	// Files written to disk
	boothfilePath := filepath.Join(targetDir, ".booth", "Boothfile")
	boothfileBytes, err := os.ReadFile(boothfilePath)
	require.NoError(t, err)
	assert.Contains(t, string(boothfileBytes), "# syntax=codingbooth/boothfile:1")
	assert.Contains(t, string(boothfileBytes), "arg GO_VERSION=1.24")

	configPath := filepath.Join(targetDir, ".booth", "config.toml")
	configBytes, err := os.ReadFile(configPath)
	require.NoError(t, err)
	assert.Contains(t, string(configBytes), "GOPROXY")
}

func TestIntegration_Basic_SinglePython(t *testing.T) {
	out, targetDir := pipeline(t, "python")

	// Config
	assert.Equal(t, []string{"-e", "PYTHONDONTWRITEBYTECODE=1"}, out.Config.RunArgs)

	// Boothfile
	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "arg PYTHON_VERSION=3.12")
	assert.Contains(t, out.Boothfile.Content, "setup python ${PYTHON_VERSION}")

	// Startup from python
	require.NotEmpty(t, out.Startups)
	var startupContent string
	for _, s := range out.Startups {
		startupContent += s.Content
	}
	assert.Contains(t, startupContent, "Python environment ready")

	// Home-seed files
	require.Len(t, out.HomeSeed, 1)
	assert.Equal(t, ".python_history", out.HomeSeed[0].RelPath)

	// Startups written to disk
	startupsDir := filepath.Join(targetDir, ".booth", "startups")
	entries, err := os.ReadDir(startupsDir)
	require.NoError(t, err)
	require.NotEmpty(t, entries)
	startupBytes, err := os.ReadFile(filepath.Join(startupsDir, entries[0].Name()))
	require.NoError(t, err)
	assert.Contains(t, string(startupBytes), "#!/bin/bash")
	assert.Contains(t, string(startupBytes), "set -e")
	assert.Contains(t, string(startupBytes), "Python environment ready")

	// Home-seed copied
	homeSeedPath := filepath.Join(targetDir, ".booth", "home-seed", ".python_history")
	_, err = os.Stat(homeSeedPath)
	assert.NoError(t, err)
}

func TestIntegration_Basic_SingleNeovim(t *testing.T) {
	out, targetDir := pipeline(t, "neovim")

	// No params, no boothfile segments, no startup
	assert.Nil(t, out.Boothfile)
	assert.Empty(t, out.Startups)

	// Home files
	require.Len(t, out.Home, 1)
	assert.Equal(t, ".config/nvim/init.lua", out.Home[0].RelPath)

	// Home file copied
	homePath := filepath.Join(targetDir, ".booth", "home", ".config", "nvim", "init.lua")
	homeBytes, err := os.ReadFile(homePath)
	require.NoError(t, err)
	assert.Contains(t, string(homeBytes), "vim.opt.number = true")
}

// --- Basic: with param override ---

func TestIntegration_Basic_GoParamOverride(t *testing.T) {
	out, _ := pipeline(t, "go:1.22")

	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "arg GO_VERSION=1.22")
	assert.Contains(t, out.Boothfile.Content, "setup go ${GO_VERSION}")
}

// --- Basic: with extension ---

func TestIntegration_Basic_GoWithLinter(t *testing.T) {
	out, targetDir := pipeline(t, "go+linter")

	require.NotNil(t, out.Boothfile)
	content := out.Boothfile.Content
	assert.Contains(t, content, "arg GO_VERSION=1.24")
	assert.Contains(t, content, "setup go ${GO_VERSION}")
	assert.Contains(t, content, "install go golangci-lint")

	// Verify segment ordering: go segment (order 50) before linter (order 50, tiebreak "go" < "go+linter")
	goIdx := strings.Index(content, "setup go ${GO_VERSION}")
	linterIdx := strings.Index(content, "install go golangci-lint")
	assert.Greater(t, linterIdx, goIdx, "go segment should come before linter segment")

	// Written to disk
	boothfileBytes, err := os.ReadFile(filepath.Join(targetDir, ".booth", "Boothfile"))
	require.NoError(t, err)
	assert.Contains(t, string(boothfileBytes), "install go golangci-lint")
}

// --- Complex: multiple templates ---

func TestIntegration_Complex_GoAndPython(t *testing.T) {
	out, _ := pipeline(t, "go/python")

	// Both params present
	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "arg GO_VERSION=1.24")
	assert.Contains(t, out.Boothfile.Content, "arg PYTHON_VERSION=3.12")

	// Both segments present
	assert.Contains(t, out.Boothfile.Content, "setup go ${GO_VERSION}")
	assert.Contains(t, out.Boothfile.Content, "setup python ${PYTHON_VERSION}")

	// Segment ordering: go < python alphabetically at same order
	goIdx := strings.Index(out.Boothfile.Content, "setup go")
	pyIdx := strings.Index(out.Boothfile.Content, "setup python")
	assert.Greater(t, pyIdx, goIdx)

	// RunArgs combined and deduped
	assert.Contains(t, out.Config.RunArgs, "-e")
	assert.Contains(t, out.Config.RunArgs, "GOPROXY=https://proxy.golang.org,direct")
	assert.Contains(t, out.Config.RunArgs, "PYTHONDONTWRITEBYTECODE=1")

	// Startup from python only
	require.NotEmpty(t, out.Startups)
	var startupContent2 string
	for _, s := range out.Startups {
		startupContent2 += s.Content
	}
	assert.Contains(t, startupContent2, "Python environment ready")

	// Home-seed from python
	require.Len(t, out.HomeSeed, 1)
}

func TestIntegration_Complex_GoLinterPythonClaudeCode(t *testing.T) {
	out, _ := pipeline(t, "go:1.22+linter/python/claude-code")

	require.NotNil(t, out.Boothfile)
	content := out.Boothfile.Content

	// ARG lines (sorted alphabetically)
	assert.Contains(t, content, "arg GO_VERSION=1.22")
	assert.Contains(t, content, "arg PYTHON_VERSION=3.12")

	// Segments from all sources
	assert.Contains(t, content, "setup go ${GO_VERSION}")
	assert.Contains(t, content, "setup python ${PYTHON_VERSION}")
	assert.Contains(t, content, "install go golangci-lint")
	assert.Contains(t, content, "setup nodejs 20")
	assert.Contains(t, content, "npm install -g @anthropic-ai/claude-code")

	// claude-code's ordered segments: Boothfile--30 before Boothfile--80
	nodejsIdx := strings.Index(content, "setup nodejs 20")
	npmIdx := strings.Index(content, "npm install -g @anthropic-ai/claude-code")
	assert.Greater(t, npmIdx, nodejsIdx, "claude-code segment at order 30 before order 80")

	// Startups from python and claude-code as individual files
	require.NotEmpty(t, out.Startups)
	var allStartupContent string
	for _, s := range out.Startups {
		allStartupContent += s.Content
	}
	assert.Contains(t, allStartupContent, "Setting up Claude Code...")
	assert.Contains(t, allStartupContent, "Python environment ready")
	assert.Contains(t, allStartupContent, "Claude Code ready")

	// Verify ordering: files sorted by order number in filename
	// claude-code startup--10 (order 10) before python (order 50) before claude-code startup--90
	require.GreaterOrEqual(t, len(out.Startups), 3)
	assert.Contains(t, out.Startups[0].RelPath, "10-")
	assert.Contains(t, out.Startups[1].RelPath, "50-")
	assert.Contains(t, out.Startups[2].RelPath, "90-")

	// Config
	assert.True(t, out.Config.Dind, "claude-code enables dind")

	// RunArgs combined
	assert.Contains(t, out.Config.RunArgs, "GOPROXY=https://proxy.golang.org,direct")
	assert.Contains(t, out.Config.RunArgs, "PYTHONDONTWRITEBYTECODE=1")
}

func TestIntegration_Complex_PythonDjango(t *testing.T) {
	out, targetDir := pipeline(t, "python/django")

	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "setup python ${PYTHON_VERSION}")
	assert.Contains(t, out.Boothfile.Content, "install pip django")

	// Django setup files
	require.Len(t, out.Setups, 1)
	assert.Equal(t, "django--setup.sh", out.Setups[0].RelPath)

	// Setup file copied to disk
	setupPath := filepath.Join(targetDir, ".booth", "setups", "django--setup.sh")
	setupBytes, err := os.ReadFile(setupPath)
	require.NoError(t, err)
	assert.Contains(t, string(setupBytes), "django-admin startproject")
}

func TestIntegration_Complex_NeovimWithHome(t *testing.T) {
	out, targetDir := pipeline(t, "go/neovim")

	// Neovim home files present
	require.Len(t, out.Home, 1)
	assert.Equal(t, ".config/nvim/init.lua", out.Home[0].RelPath)

	// Go boothfile
	require.NotNil(t, out.Boothfile)
	assert.Contains(t, out.Boothfile.Content, "setup go ${GO_VERSION}")

	// Home file on disk
	initLua := filepath.Join(targetDir, ".booth", "home", ".config", "nvim", "init.lua")
	_, err := os.Stat(initLua)
	assert.NoError(t, err)
}

// --- Dryrun: output model structure checks ---

func TestIntegration_Dryrun_EmptyConfigWhenNoScalars(t *testing.T) {
	out, _ := pipeline(t, "go")

	// Config exists but scalars are empty (go has no variant/port/timezone)
	require.NotNil(t, out.Config)
	assert.Empty(t, out.Config.Variant)
	assert.Empty(t, out.Config.Port)
	assert.Empty(t, out.Config.Timezone)
	assert.False(t, out.Config.Dind)
}

func TestIntegration_Dryrun_DindFromClaudeCode(t *testing.T) {
	out, _ := pipeline(t, "claude-code")
	assert.True(t, out.Config.Dind)
}

func TestIntegration_Dryrun_RunArgsDeduped(t *testing.T) {
	out, _ := pipeline(t, "go/python")

	// Each -e + value is a distinct pair; go and python have different values so both appear
	count := 0
	for _, arg := range out.Config.RunArgs {
		if arg == "-e" {
			count++
		}
	}
	assert.Equal(t, 2, count, "-e should appear once per distinct flag-value pair")
}

func TestIntegration_Dryrun_ConfigTomlContent(t *testing.T) {
	out, targetDir := pipeline(t, "claude-code")

	configPath := filepath.Join(targetDir, ".booth", "config.toml")
	configBytes, err := os.ReadFile(configPath)
	require.NoError(t, err)
	configStr := string(configBytes)

	assert.Contains(t, configStr, "dind = true")
	_ = out
}

func TestIntegration_Dryrun_BoothfileHeader(t *testing.T) {
	_, targetDir := pipeline(t, "go")

	boothfileBytes, err := os.ReadFile(filepath.Join(targetDir, ".booth", "Boothfile"))
	require.NoError(t, err)
	lines := strings.Split(string(boothfileBytes), "\n")
	assert.Equal(t, "# syntax=codingbooth/boothfile:1", lines[0])
}

func TestIntegration_Dryrun_StartupFileHeader(t *testing.T) {
	_, targetDir := pipeline(t, "python")

	startupsDir := filepath.Join(targetDir, ".booth", "startups")
	entries, err := os.ReadDir(startupsDir)
	require.NoError(t, err)
	require.NotEmpty(t, entries)

	startupBytes, err := os.ReadFile(filepath.Join(startupsDir, entries[0].Name()))
	require.NoError(t, err)
	lines := strings.Split(string(startupBytes), "\n")
	assert.Equal(t, "#!/bin/bash", lines[0])
	assert.Equal(t, "set -e", lines[1])
}

func TestIntegration_Dryrun_NoBoothDirExists(t *testing.T) {
	_, targetDir := pipeline(t, "neovim")

	// .booth/ directory always created
	info, err := os.Stat(filepath.Join(targetDir, ".booth"))
	require.NoError(t, err)
	assert.True(t, info.IsDir())
}

// --- Error cases ---

func TestIntegration_Error_UnknownTemplate(t *testing.T) {
	registry := loadRegistry(t)
	parsed, err := selection.ParseSelectDSL("nonexistent")
	require.NoError(t, err)

	_, err = selection.Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unknown template")
}

func TestIntegration_MissingRequires_AutoSelectsDependency(t *testing.T) {
	registry := loadRegistry(t)
	parsed, err := selection.ParseSelectDSL("django")
	require.NoError(t, err)

	resolved, err := selection.Resolve(parsed, registry)
	require.NoError(t, err)
	require.Len(t, resolved.Templates, 2)
	assert.Equal(t, "django", resolved.Templates[0].Template.Name)
	assert.Equal(t, selection.ExplicitSelect, resolved.Templates[0].SelectMode)
	assert.Equal(t, "python", resolved.Templates[1].Template.Name)
	assert.Equal(t, selection.DependencySelect, resolved.Templates[1].SelectMode)
}

func TestIntegration_Error_TooManyParams(t *testing.T) {
	registry := loadRegistry(t)
	parsed, err := selection.ParseSelectDSL("go:1.24,extra")
	require.NoError(t, err)

	_, err = selection.Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "too many parameters")
}

func TestIntegration_Error_DuplicateTemplate(t *testing.T) {
	registry := loadRegistry(t)
	parsed, err := selection.ParseSelectDSL("go/go")
	require.NoError(t, err)

	_, err = selection.Resolve(parsed, registry)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "more than once")
}

// --- Inline files ---

func TestIntegration_InlineFiles_ClaudeCodeAcceptEdits(t *testing.T) {
	out, targetDir := pipeline(t, "claude-code+accept-edits")

	// Inline home-seed file from accept-edits extension
	require.Len(t, out.HomeSeed, 1)
	assert.Equal(t, ".claude/settings.json", out.HomeSeed[0].RelPath)
	assert.Contains(t, out.HomeSeed[0].Content, "Edit")
	assert.Contains(t, out.HomeSeed[0].Content, "Write")

	// File written to disk
	settingsPath := filepath.Join(targetDir, ".booth", "home-seed", ".claude", "settings.json")
	data, err := os.ReadFile(settingsPath)
	require.NoError(t, err)
	assert.Contains(t, string(data), "Edit")
	assert.Contains(t, string(data), "Write")
}
