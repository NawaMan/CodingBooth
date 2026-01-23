// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"testing"
)

// Scenario A — Without any config, the expected variant is "default"
func TestInitializeAppContext_ScenarioA_DefaultConfig_NoConfig(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{})

	if got := res.Ctx.Variant(); got != "default" {
		t.Fatalf("expected Variant %q, got %q", "default", got)
	}
}

// Scenario B — With a default config, the expected variant is the one in the default config
func TestInitializeAppContext_ScenarioB_DefaultConfig_WithDefaultConfig(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-default-config" {
		t.Fatalf("expected Variant %q, got %q", "from-default-config", got)
	}
}

// Scenario C — With default config and CLI config, the CLI config should win
func TestInitializeAppContext_ScenarioC_DefaultConfigAndCliConfig_CliConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--config", "sub-folder-Cli/.booth/config.toml",
		},
		TomlFiles: []TomlFile{{

			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			// CLI config
			Path:    "sub-folder-Cli/.booth/config.toml",
			Content: `variant = "from-cli-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-cli-ws" {
		t.Fatalf("expected Variant %q (CLI booth TOML), got %q", "from-cli-ws", got)
	}
}

// Scenario D — With CLI config but the file does not exist, should panic.
func TestInitializeAppContext_ScenarioD_DefaultConfigAndCliConfig_CliConfigWins(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic when CLI-specified config file doesn't exist, but didn't panic")
		}
	}()

	_ = RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--config", "sub-folder-Cli/.booth/config.toml",
		},
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}},
	})
}

// Scenario E — With CLI config but the file does not exist, should panic.
func TestInitializeAppContext_ScenarioE_DefaultConfigAndCliConfig_CliConfigWins(t *testing.T) {
	defer func() {
		if r := recover(); r == nil {
			t.Fatal("expected panic when CLI-specified config file doesn't exist, but didn't panic")
		}
	}()

	_ = RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--config", "sub-folder-Cli/.booth/config.toml",
		},
		TomlFiles: []TomlFile{},
	})
}

// Scenario D — With default and ENV config, the default config should win
func TestInitializeAppContext_ScenarioD_DefaultConfigAndEnvConfig_DefaultConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{
			"CB_CONFIG": "sub-folder-Env/.booth/config.toml",
		},
		Args: []string{},
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			Path:    "sub-folder-Env/.booth/config.toml",
			Content: `variant = "from-env-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-default-config" {
		t.Fatalf("expected Variant %q (Default config), got %q", "from-default-config", got)
	}
}

// Scenario E — With ENV config, the ENV config should win. -- That is ENV config is ignored.
func TestInitializeAppContext_ScenarioE_EnvConfig_DefaultConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{
			"CB_CONFIG": "sub-folder-Env/.booth/config.toml",
		},
		Args: []string{},
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			Path:    "sub-folder-Env/.booth/config.toml",
			Content: `variant = "from-env-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-default-config" {
		t.Fatalf("expected Variant %q (Default config), got %q", "from-default-config", got)
	}
}

// Scenario F — CLI first-pass --config sticks and determines TOML source
// We write two TOMLs: default .booth/config.toml and custom.toml; --config must pick custom.toml.
func TestInitializeAppContext_ScenarioF_DefaultConfigAndEnvConfig_DefaultConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args:   []string{},
		TomlFiles: []TomlFile{{
			// Default config
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			// CLI config
			Path:    "sub-folder-Env/.booth/config.toml",
			Content: `variant = "from-env-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-default-config" {
		t.Fatalf("expected Variant %q (Default config), got %q", "from-default-config", got)
	}
}

// Scenario G — With default code dir and CLI code dir, the CLI config on the CLI code dir should win
func TestInitializeAppContext_ScenarioG_DefaultCodeAndCliCode_CliConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--code", "sub-folder-Cli",
		},
		TomlFiles: []TomlFile{{
			// Default config
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			// CLI config
			Path:    "sub-folder-Cli/.booth/config.toml",
			Content: `variant = "from-cli-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-cli-ws" {
		t.Fatalf("expected Variant %q (CLI booth TOML), got %q", "from-cli-ws", got)
	}
}
