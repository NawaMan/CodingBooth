// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestSerializeOwnerPermission(t *testing.T) {
	got := SerializeOwnerPermission([]OwnerPerm{{
		Path: "/opt/pip-cache", User: "coder", Group: "coder", Mode: "1777",
	}}, "", "booth config --no-tui --overwrite --select python+pip-cache")
	assert.Contains(t, got, "# Configured by: booth config --no-tui --overwrite --select python+pip-cache\n")
	assert.Contains(t, got, "- path: \"/opt/pip-cache\"\n")
	assert.Contains(t, got, "  user: \"coder\"\n")
	assert.Contains(t, got, "  group: \"coder\"\n")
	assert.Contains(t, got, "  mode: \"1777\"\n")

	assert.Empty(t, SerializeOwnerPermission(nil, "", ""))
}

func TestWriteOutput_OwnerPermissionRoundTripFile(t *testing.T) {
	dir := t.TempDir()
	err := WriteOutput(&BoothOutput{
		AdjustCommand: "booth config --no-tui --overwrite --select python+pip-cache",
		Config:        &ConfigToml{},
		OwnerPerms: []OwnerPerm{{
			Path: "/opt/pip-cache", User: "coder", Group: "coder", Mode: "1777",
		}},
	}, dir)
	require.NoError(t, err)
	data, err := os.ReadFile(filepath.Join(dir, ".booth", OwnerPermissionName))
	require.NoError(t, err)
	assert.Contains(t, string(data), "path: \"/opt/pip-cache\"")
	assert.Empty(t, Drifted(dir))
}
