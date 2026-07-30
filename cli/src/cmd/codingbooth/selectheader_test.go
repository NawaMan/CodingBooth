// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// --- selectArg ---

func TestSelectArg_PlainDSLIsUnquoted(t *testing.T) {
	// The header of every booth without a quoted param value must not change.
	assert.Equal(t, "--select go+vscode-ext+go-pkg/claude-code+auto-accept",
		selectArg("go+vscode-ext+go-pkg/claude-code+auto-accept"))
}

func TestSelectArg_QuotedValueIsShellQuoted(t *testing.T) {
	assert.Equal(t, `--select 'go+go-pkg:"github.com/a/b@v1"/claude-code'`,
		selectArg(`go+go-pkg:"github.com/a/b@v1"/claude-code`))
}

func TestSelectArg_WhitespaceIsShellQuoted(t *testing.T) {
	assert.Equal(t, `--select 'a:"one two"'`, selectArg(`a:"one two"`))
}

// --- headerFields ---

func TestHeaderFields_PlainCommand(t *testing.T) {
	assert.Equal(t,
		[]string{"booth", "config", "--no-tui", "--select", "go/python"},
		headerFields("booth config --no-tui --select go/python"))
}

func TestHeaderFields_StripsOuterSingleQuotesKeepsDSLQuotes(t *testing.T) {
	got := headerFields(`booth config --select 'go+go-pkg:"github.com/a/b@v1"'`)
	require.Len(t, got, 4)
	assert.Equal(t, `go+go-pkg:"github.com/a/b@v1"`, got[3])
}

// A hand-written header with no outer quotes reads back unharmed: only one
// enclosing layer of single quotes goes, and there is none here.
func TestHeaderFields_HandWrittenDSLQuotesSurvive(t *testing.T) {
	got := headerFields(`booth config --select go+go-pkg:"github.com/a/b@v1"`)
	require.Len(t, got, 4)
	assert.Equal(t, `go+go-pkg:"github.com/a/b@v1"`, got[3])
}

func TestHeaderFields_QuotedWhitespaceStaysOneArgument(t *testing.T) {
	got := headerFields(`booth config --select 'a:"one two"'`)
	require.Len(t, got, 4)
	assert.Equal(t, `a:"one two"`, got[3])
}

// --- Header round trip ---

// The header is what `booth config` reads to reconfigure an existing booth, so a
// DSL that survives writing but not reading is the same bug in a different place.
func TestHeaderRoundTrip_QuotedModulePath(t *testing.T) {
	const dsl = `go+vscode-ext+go-pkg:"github.com/pocketbase/pocketbase/examples/base@latest"/claude-code+auto-accept`

	for name, build := range map[string]func(initFlags) string{
		"adjust":       buildAdjustCommand,
		"configAdjust": buildConfigAdjustCommand,
	} {
		t.Run(name, func(t *testing.T) {
			cmd := build(initFlags{selectDSL: dsl, variant: "base", port: "NEXT:22000"})
			back := parseAdjustCommand(cmd)
			// parseInitFlags collects --select values; selectDSL is joined from them later.
			assert.Equal(t, []string{dsl}, back.selectDSLs, "cmd was: %s", cmd)
			assert.Equal(t, "base", back.variant)
			assert.Equal(t, "NEXT:22000", back.port)
		})
	}
}

func TestHeaderRoundTrip_PlainDSL(t *testing.T) {
	const dsl = "go+vscode-ext+go-pkg/claude-code+auto-accept+credential+settings-cache"

	cmd := buildConfigAdjustCommand(initFlags{selectDSL: dsl})
	assert.Contains(t, cmd, "--select "+dsl) // unquoted, byte-for-byte as before
	assert.Equal(t, []string{dsl}, parseAdjustCommand(cmd).selectDSLs)
}
