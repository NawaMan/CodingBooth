// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"strings"
	"testing"

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
