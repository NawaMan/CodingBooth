// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"path/filepath"
	"testing"
)

// TestConfigFileArgument tests that --config argument is properly parsed
func TestConfigFileArgument(t *testing.T) {
	// Simulate: workspace --verbose --dryrun --config test--config.toml
	input := TestInput{
		Args: []string{
			"--verbose",
			"--dryrun",
			"--config",
			"test--config.toml",
		},
		EnvMap:      map[string]string{},
		CurrentPath: "/home/nawa/dev/git/WorkSpace/tests/dryrun",
		HostUID:     "1000",
		HostGID:     "1000",
		Timezone:    "UTC",
		TomlFiles: []TomlFile{
			{
				Path:    "test--config.toml",
				Content: "",
			},
		},
	}

	outcome := RunInitializeAppContext(t, input)

	// The config file should be test--config.toml, not ws--config.toml
	expected := filepath.Join(outcome.CodeDir, "test--config.toml")
	actual := outcome.Ctx.ConfigFile()

	if actual != expected {
		t.Errorf("Config file mismatch.\nExpected: %s\nActual: %s", expected, actual)
	}
}
