// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestInit_NoProfilesByDefault(t *testing.T) {
	out := RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: `port = "12000"` + "\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})
	assert.Equal(t, "12000", out.Ctx.Port(), "base config applies")
	assert.Empty(t, out.Ctx.Profiles(), "no profiles selected without --profile")
}

func TestInit_ImplicitDefaultProfile(t *testing.T) {
	out := RunInitializeAppContext(t, TestInput{
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: `port = "12000"` + "\n"},
			{Path: ".booth/default--config.toml", Content: `port = "13000"` + "\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})
	assert.Equal(t, "13000", out.Ctx.Port(), "default profile overrides base when no --profile is given")
	require.Len(t, out.Ctx.Profiles(), 1)
	assert.Equal(t, "default", out.Ctx.Profiles()[0].Name)
}

func TestInit_ExplicitProfileSkipsDefault(t *testing.T) {
	out := RunInitializeAppContext(t, TestInput{
		Args: []string{"--profile", "dev"},
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: `port = "12000"` + "\n"},
			{Path: ".booth/default--config.toml", Content: `port = "13000"` + "\n"},
			{Path: ".booth/dev--config.toml", Content: `port = "14000"` + "\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})
	assert.Equal(t, "14000", out.Ctx.Port(), "explicit --profile dev wins; default not applied")
	require.Len(t, out.Ctx.Profiles(), 1)
	assert.Equal(t, "dev", out.Ctx.Profiles()[0].Name)
}

func TestInit_MultipleProfilesLaterWins(t *testing.T) {
	out := RunInitializeAppContext(t, TestInput{
		Args: []string{"--profile", "dev,deploy"},
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: `port = "12000"` + "\n"},
			{Path: ".booth/dev--config.toml", Content: `port = "13000"` + "\n"},
			{Path: ".booth/deploy--config.toml", Content: `port = "14000"` + "\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})
	assert.Equal(t, "14000", out.Ctx.Port(), "later profile wins for scalars")
	names := []string{out.Ctx.Profiles()[0].Name, out.Ctx.Profiles()[1].Name}
	assert.Equal(t, []string{"dev", "deploy"}, names)
}

func TestInit_BoothProfilesEnvVar(t *testing.T) {
	out := RunInitializeAppContext(t, TestInput{
		EnvMap: map[string]string{"BOOTH_PROFILES": "dev"},
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: `port = "12000"` + "\n"},
			{Path: ".booth/dev--config.toml", Content: `port = "13000"` + "\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})
	assert.Equal(t, "13000", out.Ctx.Port())
	require.Len(t, out.Ctx.Profiles(), 1)
	assert.Equal(t, "dev", out.Ctx.Profiles()[0].Name)
}

func TestInit_FlagBeatsEnvVar(t *testing.T) {
	out := RunInitializeAppContext(t, TestInput{
		Args:   []string{"--profile", "dev"},
		EnvMap: map[string]string{"BOOTH_PROFILES": "deploy"},
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: `port = "12000"` + "\n"},
			{Path: ".booth/dev--config.toml", Content: `port = "13000"` + "\n"},
			{Path: ".booth/deploy--config.toml", Content: `port = "14000"` + "\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})
	assert.Equal(t, "13000", out.Ctx.Port(), "--profile wins; BOOTH_PROFILES env ignored")
	require.Len(t, out.Ctx.Profiles(), 1)
	assert.Equal(t, "dev", out.Ctx.Profiles()[0].Name)
}

func TestInit_ProfileArrayMerge(t *testing.T) {
	out := RunInitializeAppContext(t, TestInput{
		Args: []string{"--profile", "dev"},
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: `run-args = ["--base"]` + "\n"},
			{Path: ".booth/dev--config.toml", Content: `run-args = ["--dev"]` + "\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})
	// run-args concatenate (base then dev). The builder wraps the flat
	// list of config-level run-args into a single group.
	runArgs := out.Ctx.RunArgs()
	require.Equal(t, 1, runArgs.Length(), "single group of run-args at config level")
	group := runArgs.At(0)
	assert.Equal(t, []string{"--base", "--dev"}, group.Slice(), "arrays concat in apply order")
}
