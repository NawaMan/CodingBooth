// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestInit_BoothDirIgnoresProjectConfigProfilesAndEnv(t *testing.T) {
	spec := t.TempDir()
	out := RunInitializeAppContext(t, TestInput{
		Args: []string{"booth", "--booth-dir", spec},
		EnvMap: map[string]string{
			"BOOTH_PROFILES": "dev",
		},
		TomlFiles: []TomlFile{
			{Path: ".booth/config.toml", Content: "port = \"12000\"\nvariant = \"codeserver\"\n"},
			{Path: ".booth/default--config.toml", Content: "port = \"13000\"\n"},
			{Path: ".booth/dev--config.toml", Content: "port = \"14000\"\n"},
		},
		HostUID: "1000", HostGID: "1000",
	})

	assert.Equal(t, "NEXT", out.Ctx.Port(), "the project port is not loaded")
	assert.Equal(t, "default", out.Ctx.Variant(), "the project variant is not loaded")
	assert.Empty(t, out.Ctx.Profiles(), "profiles and BOOTH_PROFILES are not applied")
	assert.Equal(t, spec, out.Ctx.ExplicitBoothDir())
	assert.NotEqual(t, filepath.Join(out.CodeDir, ".booth"), out.Ctx.ExplicitBoothDir())
	require.NotContains(t, out.Ctx.Port(), "12000")
}
