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
			Path:    "ws--config.toml",
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
			"--config", "sub-folder-Cli/ws--config.toml",
		},
		TomlFiles: []TomlFile{{

			Path:    "ws--config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			// CLI config
			Path:    "sub-folder-Cli/ws--config.toml",
			Content: `variant = "from-cli-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-cli-ws" {
		t.Fatalf("expected Variant %q (CLI workspace TOML), got %q", "from-cli-ws", got)
	}
}

// Scenario D — With CLI config but the file does not exist, use default value.
func TestInitializeAppContext_ScenarioD_DefaultConfigAndCliConfig_CliConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--config", "sub-folder-Cli/ws--config.toml",
		},
		TomlFiles: []TomlFile{{
			Path:    "ws--config.toml",
			Content: `variant = "from-default-config"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "default" {
		t.Fatalf("expected Variant %q (CLI workspace TOML), got %q", "default", got)
	}
}

// Scenario E — With default config and CLI config but the CLI configfile does not exist, use default value (not default config).
func TestInitializeAppContext_ScenarioE_DefaultConfigAndCliConfig_CliConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--config", "sub-folder-Cli/ws--config.toml",
		},
		TomlFiles: []TomlFile{},
	})

	if got := res.Ctx.Variant(); got != "default" {
		t.Fatalf("expected Variant %q (CLI workspace TOML), got %q", "default", got)
	}
}

// Scenario D — With default and ENV config, the default config should win
func TestInitializeAppContext_ScenarioD_DefaultConfigAndEnvConfig_DefaultConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{
			"WS_CONFIG": "sub-folder-Env/ws--config.toml",
		},
		Args: []string{},
		TomlFiles: []TomlFile{{
			Path:    "ws--config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			Path:    "sub-folder-Env/ws--config.toml",
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
			"WS_CONFIG": "sub-folder-Env/ws--config.toml",
		},
		Args: []string{},
		TomlFiles: []TomlFile{{
			Path:    "ws--config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			Path:    "sub-folder-Env/ws--config.toml",
			Content: `variant = "from-env-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-default-config" {
		t.Fatalf("expected Variant %q (Default config), got %q", "from-default-config", got)
	}
}

// Scenario F — CLI first-pass --config sticks and determines TOML source
// We write two TOMLs: default ws--config.toml and custom.toml; --config must pick custom.toml.
func TestInitializeAppContext_ScenarioF_DefaultConfigAndEnvConfig_DefaultConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args:   []string{},
		TomlFiles: []TomlFile{{
			// Default config
			Path:    "ws--config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			// CLI config
			Path:    "sub-folder-Env/ws--config.toml",
			Content: `variant = "from-env-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-default-config" {
		t.Fatalf("expected Variant %q (Default config), got %q", "from-default-config", got)
	}
}

// Scenario G — With default workspace and CLI workspace, the CLI config on the CLI workspace should win
func TestInitializeAppContext_ScenarioG_DefaultWorkspaceAndCliWorkspace_CliConfigWins(t *testing.T) {
	res := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{},
		Args: []string{
			"--workspace", "sub-folder-Cli",
		},
		TomlFiles: []TomlFile{{
			// Default config
			Path:    "ws--config.toml",
			Content: `variant = "from-default-config"`,
		}, {
			// CLI config
			Path:    "sub-folder-Cli/ws--config.toml",
			Content: `variant = "from-cli-ws"`,
		}},
	})

	if got := res.Ctx.Variant(); got != "from-cli-ws" {
		t.Fatalf("expected Variant %q (CLI workspace TOML), got %q", "from-cli-ws", got)
	}
}
