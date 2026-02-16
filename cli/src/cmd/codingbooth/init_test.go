// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/stretchr/testify/assert"
)

func TestParseInitFlags_Port(t *testing.T) {
	flags := parseInitFlags([]string{"--select", "python", "--port", "10080"})
	assert.Equal(t, []string{"python"}, flags.selectDSLs)
	assert.Equal(t, "10080", flags.port)
}

func TestBuildInitCommand_IncludesPort(t *testing.T) {
	flags := initFlags{
		selectDSL: "python",
		port:      "10080",
	}
	cmd := buildInitCommand(".", flags)
	assert.Contains(t, cmd, "--select python")
	assert.Contains(t, cmd, "--port 10080")
}

func TestBuildAdjustCommand_IncludesPortBeforeSelect(t *testing.T) {
	flags := initFlags{
		selectDSL: "python",
		port:      "10080",
	}
	cmd := buildAdjustCommand(flags)
	assert.Contains(t, cmd, "--port 10080")
	assert.Contains(t, cmd, "--select python")
	assert.Less(t, strings.Index(cmd, "--port 10080"), strings.Index(cmd, "--select python"))
}

// --set flag parsing

func TestParseInitFlags_Set(t *testing.T) {
	flags := parseInitFlags([]string{"--select", "go", "--set", "dind", "--set", "port=8080"})
	assert.Equal(t, []string{"go"}, flags.selectDSLs)
	assert.Equal(t, []string{"dind", "port=8080"}, flags.sets)
}

func TestParseInitFlags_SetCoexistsWithPort(t *testing.T) {
	flags := parseInitFlags([]string{"--select", "go", "--port", "3000", "--set", "keep-alive"})
	assert.Equal(t, "3000", flags.port)
	assert.Equal(t, []string{"keep-alive"}, flags.sets)
}

// parseSetOverrides

func TestParseSetOverrides_BareKey(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind"})
	assert.NoError(t, err)
	assert.Equal(t, true, result["dind"])
}

func TestParseSetOverrides_BooleanTrue(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind=true"})
	assert.NoError(t, err)
	assert.Equal(t, true, result["dind"])
}

func TestParseSetOverrides_BooleanFalse(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind=false"})
	assert.NoError(t, err)
	assert.Equal(t, false, result["dind"])
}

func TestParseSetOverrides_StringValue(t *testing.T) {
	result, err := parseSetOverrides([]string{"name=my-booth"})
	assert.NoError(t, err)
	assert.Equal(t, "my-booth", result["name"])
}

func TestParseSetOverrides_EmptyKey(t *testing.T) {
	_, err := parseSetOverrides([]string{"=value"})
	assert.Error(t, err)
}

func TestParseSetOverrides_InvalidKeyWithSpace(t *testing.T) {
	_, err := parseSetOverrides([]string{"bad key=value"})
	assert.Error(t, err)
}

func TestParseSetOverrides_MultipleValues(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind", "keep-alive", "name=test"})
	assert.NoError(t, err)
	assert.Equal(t, true, result["dind"])
	assert.Equal(t, true, result["keep-alive"])
	assert.Equal(t, "test", result["name"])
}

// applySetOverrides

func TestApplySetOverrides_KnownField_Variant(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"variant": "codeserver"})
	assert.Equal(t, "codeserver", cfg.Variant)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_KnownField_Port(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"port": "8080"})
	assert.Equal(t, "8080", cfg.Port)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_KnownField_Dind(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"dind": true})
	assert.True(t, cfg.Dind)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_UnknownField(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"keep-alive": true})
	assert.True(t, cfg.Overrides["keep-alive"].(bool))
}

func TestApplySetOverrides_MixedKnownAndUnknown(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{
		"variant":    "base",
		"keep-alive": true,
		"name":       "test",
	})
	assert.Equal(t, "base", cfg.Variant)
	assert.True(t, cfg.Overrides["keep-alive"].(bool))
	assert.Equal(t, "test", cfg.Overrides["name"])
}

// buildInitCommand / buildAdjustCommand with --set

func TestBuildInitCommand_IncludesSet(t *testing.T) {
	flags := initFlags{
		selectDSL: "go",
		sets:      []string{"dind", "keep-alive"},
	}
	cmd := buildInitCommand(".", flags)
	assert.Contains(t, cmd, "--set dind")
	assert.Contains(t, cmd, "--set keep-alive")
}

func TestBuildAdjustCommand_SetBeforeSelect(t *testing.T) {
	flags := initFlags{
		selectDSL: "go",
		sets:      []string{"dind"},
	}
	cmd := buildAdjustCommand(flags)
	assert.Contains(t, cmd, "--set dind")
	assert.Contains(t, cmd, "--select go")
	assert.Less(t, strings.Index(cmd, "--set dind"), strings.Index(cmd, "--select go"))
}
