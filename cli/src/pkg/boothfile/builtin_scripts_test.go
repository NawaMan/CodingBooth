// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package boothfile

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestBuiltinScripts_Embedded(t *testing.T) {
	setups, installs := BuiltinScripts()

	require.NotEmpty(t, setups, "embedded setup list must not be empty")
	require.NotEmpty(t, installs, "embedded install list must not be empty")

	// Spot-check names the Go templates rely on.
	assert.Contains(t, setups, "go")
	assert.Contains(t, setups, "go-code-extension")
	assert.Contains(t, setups, "claude-code")
	assert.Contains(t, installs, "go")
	assert.Contains(t, installs, "apt")

	// The suffixes must be stripped, not retained.
	assert.NotContains(t, setups, "go--setup.sh")
	assert.NotContains(t, installs, "go--install.sh")
}

func TestKnownBuiltinScripts_NoDirStillKnowsBuiltins(t *testing.T) {
	// An end user has no variants/base/setups/ on disk, so dir is empty. The
	// built-ins must still be known -- otherwise adding .booth/setups/ makes the
	// compiler flag every built-in as unknown.
	setups, installs := KnownBuiltinScripts("")

	embeddedSetups, embeddedInstalls := BuiltinScripts()
	assert.Equal(t, embeddedSetups, setups)
	assert.Equal(t, embeddedInstalls, installs)
}

func TestKnownBuiltinScripts_MergesSourceTree(t *testing.T) {
	dir := t.TempDir()
	// A brand-new script in a checkout, not yet in the embedded list.
	require.NoError(t, os.WriteFile(filepath.Join(dir, "brandnew--setup.sh"), []byte("#!/bin/sh\n"), 0o755))
	// A script that is already embedded must not be duplicated.
	require.NoError(t, os.WriteFile(filepath.Join(dir, "go--setup.sh"), []byte("#!/bin/sh\n"), 0o755))

	setups, _ := KnownBuiltinScripts(dir)

	assert.Contains(t, setups, "brandnew")
	assert.Equal(t, 1, countOf(setups, "go"), "go must appear exactly once")
}

// TestCustomSetups_DoNotFlagBuiltins is the regression test for the reported bug:
// a project that adds .booth/setups/ used to get "Unknown setup script 'go'" for
// every built-in, because the known-script list held only the custom scripts.
func TestCustomSetups_DoNotFlagBuiltins(t *testing.T) {
	builtinSetups, builtinInstalls := KnownBuiltinScripts("")

	content := `# syntax=codingbooth/boothfile:1
setup claude-code
setup go 1.25.7
install go golang.org/x/tools/gopls@latest
setup go-code-extension
setup mycustomtool
`
	compiler := NewCompilerWithOptions(CompilerOptions{
		CustomSetupsDir:      ".booth/setups",
		HasCustomSetups:      true,
		KnownSetupScripts:    builtinSetups,
		KnownInstallScripts:  builtinInstalls,
		CustomSetupScripts:   []string{"mycustomtool"},
		CustomInstallScripts: nil,
	})
	result := compiler.Compile(NewParser().ParseString(content))

	assert.False(t, result.HasErrors(), "errors: %v", result.Errors)
	assert.Empty(t, result.Warnings, "built-ins and custom scripts must both be recognized")
}

func countOf(list []string, want string) int {
	count := 0
	for _, s := range list {
		if s == want {
			count++
		}
	}
	return count
}
