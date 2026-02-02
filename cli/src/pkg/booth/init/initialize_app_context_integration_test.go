// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"testing"
)

// Scenario A — Without any config, the expected variant is "default"
func TestIntegration_InitializeAppContext_ScenarioA_NoConfig(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{})

	if got := res.Ctx.Variant(); got != "default" {
		t.Fatalf("expected Variant %q, got %q", "default", got)
	}
}

// Scenario B — With a default config, the expected variant is the one in the default config
func TestIntegration_InitializeAppContext_ScenarioB_DefaultConfigOnly(t *testing.T) {
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

// Scenario C — With default config and CLI --config, the CLI config should win
func TestIntegration_InitializeAppContext_ScenarioC_DefaultAndCliConfig_CliWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--config", "sub-folder-Cli/.booth/config.toml",
		},
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			Path:    "sub-folder-Cli/.booth/config.toml",
			Content: `variant = "from-cli-config"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-cli-config" {
		t.Fatalf("expected Variant %q (CLI config), got %q", "from-cli-config", got)
	}
}

// Scenario D — With CLI --config pointing to missing file (default exists), should panic
func TestIntegration_InitializeAppContext_ScenarioD_CliConfigMissing_DefaultExists_Panics(t *testing.T) {
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

// Scenario E — With CLI --config pointing to missing file (no default), should panic
func TestIntegration_InitializeAppContext_ScenarioE_CliConfigMissing_NoDefault_Panics(t *testing.T) {
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

// Scenario F — With default config and ENV config, the default config should win (ENV ignored when default exists)
func TestIntegration_InitializeAppContext_ScenarioF_DefaultAndEnvConfig_DefaultWins(t *testing.T) {
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
			Content: `variant = "from-env-config"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-default-config" {
		t.Fatalf("expected Variant %q (default config), got %q", "from-default-config", got)
	}
}

// Scenario G — With ENV config only (no default), ENV is used as fallback
func TestIntegration_InitializeAppContext_ScenarioG_EnvConfigOnly_EnvUsedAsFallback(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{
			"CB_CONFIG": "sub-folder-Env/.booth/config.toml",
		},
		Args: []string{},
		TomlFiles: []TomlFile{{
			Path:    "sub-folder-Env/.booth/config.toml",
			Content: `variant = "from-env-config"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-env-config" {
		t.Fatalf("expected Variant %q (ENV fallback), got %q", "from-env-config", got)
	}
}

// Scenario H — With default config and CLI --code, the config in CLI code dir should win
func TestIntegration_InitializeAppContext_ScenarioH_DefaultAndCliCode_CliCodeConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--code", "sub-folder-Cli",
		},
		TomlFiles: []TomlFile{{
			Path:    ".booth/config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			Path:    "sub-folder-Cli/.booth/config.toml",
			Content: `variant = "from-cli-code-config"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-cli-code-config" {
		t.Fatalf("expected Variant %q (CLI code dir config), got %q", "from-cli-code-config", got)
	}
}
