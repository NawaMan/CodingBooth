// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/kelseyhightower/envconfig"
	"github.com/nawaman/workspace/src/pkg/appctx"
	"github.com/nawaman/workspace/src/pkg/ilist"
	"github.com/nawaman/workspace/src/pkg/nillable"
)

type TomlFile struct {
	Path    string // Relative to the temp direction.
	Content string
}

// TestInput describes one InitializeAppContext test scenario.
type TestInput struct {
	// Env vars to set for this run. Any keys not present here will be UNSET
	// (important for bool parsing with envconfig).
	EnvMap map[string]string

	// Args passed to InitializeAppContext. If nil, helper uses []string{"workspace"}.
	// NOTE: InitializeAppContext expects argv0 to be included.
	Args []string

	// If non-empty, helper writes TOML content into the config file before running.
	// If empty string, helper does NOT create a TOML file.
	TomlFiles []TomlFile

	// Timezone to use for the test
	Timezone string

	// CurrentPath to use for the test
	CurrentPath string

	// HostUID to use for the test
	HostUID string

	// HostGID to use for the test
	HostGID string
}

// TestOutcome is what the helper returns.
type TestOutcome struct {
	WorkspaceDir string            // the temp dir the helper chdir'd into
	Ctx          appctx.AppContext // result of InitializeAppContext
	FinalConfig  appctx.AppConfig  // snapshot of bootstrap workspace/config (best effort)
}

// RunInitializeAppContext sets up env/CWD/config file and runs InitializeAppContext.
// It also returns FinalConfig snapshot (because AppContext may not expose workspace/config path).
func RunInitializeAppContext(test *testing.T, input TestInput) TestOutcome {
	test.Helper()

	// Temp workspace dir + chdir
	ws := test.TempDir()
	oldWD, err := os.Getwd()
	if err != nil {
		test.Fatalf("Getwd: %v", err)
	}
	if err := os.Chdir(ws); err != nil {
		test.Fatalf("Chdir(%q): %v", ws, err)
	}
	test.Cleanup(func() { _ = os.Chdir(oldWD) })

	// Env handling: save & clear ALL WS_* variables to avoid leakage between tests
	type savedEnv struct {
		key    string
		val    string
		exists bool
	}

	saved := []savedEnv{}

	for _, kv := range os.Environ() {
		// kv is "KEY=value"
		eq := -1
		for i := 0; i < len(kv); i++ {
			if kv[i] == '=' {
				eq = i
				break
			}
		}
		if eq < 0 {
			continue
		}

		key := kv[:eq]
		if !strings.HasPrefix(key, "WS_") {
			continue
		}

		val, ok := os.LookupEnv(key)
		saved = append(saved, savedEnv{
			key:    key,
			val:    val,
			exists: ok,
		})
		_ = os.Unsetenv(key)
	}

	test.Cleanup(func() {
		for _, savedEnv := range saved {
			if savedEnv.exists {
				_ = os.Setenv(savedEnv.key, savedEnv.val)
			} else {
				_ = os.Unsetenv(savedEnv.key)
			}
		}
	})

	// Apply test env vars (only those provided)
	for key, value := range input.EnvMap {
		if err := os.Setenv(key, value); err != nil {
			test.Fatalf("Setenv(%s): %v", key, err)
		}
	}

	// Build argv for InitializeAppContext (must include argv0)
	args := input.ArgList()
	if args.Length() == 0 {
		args = ilist.NewListFromSlice([]string{"workspace"})
	} else if args.Length() > 0 && len(args.At(0)) > 0 && args.At(0)[0] == '-' {
		// If user passed only flags, prepend argv0
		args = ilist.NewListFromSlice(append([]string{"workspace"}, args.Slice()...))
	}

	// --- Determine where to write TOML (bootstrap-equivalent inference) ---
	//
	// Bootstrap stickiness model:
	// - Workspace/Config are set by first-pass CLI scan or defaults.
	// - ENV must NOT override them once set by CLI scan/defaults.
	//
	// So for TOML writing we mirror that:
	// 1) Determine workspace from CLI --workspace; else default = ws (CWD set above).
	// 2) Determine config from CLI --config; else default = <workspace>/ws--config.toml.
	//
	workspace := ws
	var config string

	for i := 0; i < args.Length(); i++ {
		switch args.At(i) {
		case "--workspace":
			if i+1 < args.Length() {
				workspace = args.At(i + 1)
				i++
			}
		case "--config":
			if i+1 < args.Length() {
				config = args.At(i + 1)
				i++
			}
		}
	}

	if config == "" {
		// default derived from workspace
		config = filepath.Join(workspace, "ws--config.toml")
	}

	// If config is relative, interpret it relative to current working directory (ws).
	// This matches typical CLI behavior and keeps tests portable.
	if !filepath.IsAbs(config) {
		config = filepath.Join(ws, config)
	}

	// Write TOML file if content provided
	for _, tf := range input.TomlFiles {
		path := tf.Path

		// Force relative paths under ws
		if !filepath.IsAbs(path) {
			path = filepath.Join(ws, path)
		} else {
			// Optional: disallow absolute paths in tests
			test.Fatalf("TomlFile.Path must be relative, got %q", tf.Path)
		}

		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			test.Fatalf("MkdirAll(%q): %v", filepath.Dir(path), err)
		}
		if err := os.WriteFile(path, []byte(tf.Content), 0o644); err != nil {
			test.Fatalf("WriteFile(%q): %v", path, err)
		}
	}

	// Run
	ctx := InitializeAppContext("latest", input)

	// Best-effort snapshot (bootstrap workspace/config inferred)
	final := appctx.AppConfig{}
	final.Workspace = nillable.NewNillableString(workspace)
	final.Config = nillable.NewNillableString(config)

	return TestOutcome{
		WorkspaceDir: ws,
		Ctx:          ctx,
		FinalConfig:  final,
	}
}

func (input TestInput) ArgList() ilist.List[string] {
	args := input.Args
	if args == nil {
		args = []string{}
	}
	return ilist.NewListFromSlice(append([]string{"workspace"}, args...))
}

func (input TestInput) PopulateAppConfigFromEnvVars(config *appctx.AppConfig) error {
	return envconfig.Process("", config)
}

func (input TestInput) DetectTimezone() string {
	return input.Timezone
}

func (input TestInput) GetCurrentPath() string {
	return input.CurrentPath
}

func (input TestInput) GetHostUID() string {
	return input.HostUID
}

func (input TestInput) GetHostGID() string {
	return input.HostGID
}
