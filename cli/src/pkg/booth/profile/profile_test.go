// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package profile

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func argList(items ...string) ilist.List[string] {
	return ilist.NewListFromSlice(items)
}

// ---------- Discover ----------

func TestDiscover_EmptyCodeDir(t *testing.T) {
	dir := t.TempDir()
	got, err := Discover(dir)
	require.NoError(t, err)
	assert.Empty(t, got)
}

func TestDiscover_BoothDirMissing(t *testing.T) {
	dir := t.TempDir()
	got, err := Discover(dir)
	require.NoError(t, err)
	assert.Empty(t, got)
}

func TestDiscover_ConfigOnly(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "dev--config.toml"), []byte(""), 0644))

	got, err := Discover(dir)
	require.NoError(t, err)
	require.Contains(t, got, "dev")
	assert.NotEmpty(t, got["dev"].ConfigPath)
	assert.Empty(t, got["dev"].EnvPath)
}

func TestDiscover_EnvOnly(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, ".env--deploy"), []byte(""), 0644))

	got, err := Discover(dir)
	require.NoError(t, err)
	require.Contains(t, got, "deploy")
	assert.Empty(t, got["deploy"].ConfigPath)
	assert.NotEmpty(t, got["deploy"].EnvPath)
}

func TestDiscover_BothFilesForProfile(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "dev--config.toml"), []byte(""), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, ".env--dev"), []byte(""), 0644))

	got, err := Discover(dir)
	require.NoError(t, err)
	require.Contains(t, got, "dev")
	assert.NotEmpty(t, got["dev"].ConfigPath)
	assert.NotEmpty(t, got["dev"].EnvPath)
}

func TestDiscover_IgnoresBaseFiles(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte(""), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, ".env"), []byte(""), 0644))

	got, err := Discover(dir)
	require.NoError(t, err)
	assert.Empty(t, got, "base config.toml and .env should not be treated as profiles")
}

func TestDiscover_IgnoresCommon(t *testing.T) {
	dir := t.TempDir()
	boothDir := filepath.Join(dir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "common--config.toml"), []byte(""), 0644))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, ".env--common"), []byte(""), 0644))

	got, err := Discover(dir)
	require.NoError(t, err)
	assert.NotContains(t, got, "common",
		"common is reserved — files with that name should not be discovered as a profile")
}

// ---------- Resolve ----------

func TestResolve_NoSelection_NoDefault(t *testing.T) {
	got, err := Resolve(argList(), "", map[string]Files{"dev": {}})
	require.NoError(t, err)
	assert.Empty(t, got)
}

func TestResolve_NoSelection_DefaultAvailable(t *testing.T) {
	got, err := Resolve(argList(), "", map[string]Files{"default": {}})
	require.NoError(t, err)
	assert.Equal(t, []string{"default"}, got)
}

func TestResolve_FlagSingleProfile(t *testing.T) {
	got, err := Resolve(argList("--profile", "dev"), "", map[string]Files{"dev": {}})
	require.NoError(t, err)
	assert.Equal(t, []string{"dev"}, got)
}

func TestResolve_FlagCommaSeparated(t *testing.T) {
	got, err := Resolve(argList("--profile", "dev,deploy"), "",
		map[string]Files{"dev": {}, "deploy": {}})
	require.NoError(t, err)
	assert.Equal(t, []string{"dev", "deploy"}, got)
}

func TestResolve_FlagRepeated(t *testing.T) {
	got, err := Resolve(argList("--profile", "dev", "--profile", "deploy"), "",
		map[string]Files{"dev": {}, "deploy": {}})
	require.NoError(t, err)
	assert.Equal(t, []string{"dev", "deploy"}, got)
}

func TestResolve_FlagBeatsEnv(t *testing.T) {
	got, err := Resolve(argList("--profile", "dev"), "deploy",
		map[string]Files{"dev": {}, "deploy": {}})
	require.NoError(t, err)
	assert.Equal(t, []string{"dev"}, got, "--profile must fully override BOOTH_PROFILES with no merging")
}

func TestResolve_EnvUsedWhenFlagAbsent(t *testing.T) {
	got, err := Resolve(argList(), "dev,deploy",
		map[string]Files{"dev": {}, "deploy": {}})
	require.NoError(t, err)
	assert.Equal(t, []string{"dev", "deploy"}, got)
}

func TestResolve_RejectsCommon(t *testing.T) {
	_, err := Resolve(argList("--profile", "common"), "", map[string]Files{})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "reserved")
}

func TestResolve_RejectsEmpty(t *testing.T) {
	_, err := Resolve(argList("--profile", ""), "", map[string]Files{})
	require.Error(t, err)
}

func TestResolve_RejectsDuplicate(t *testing.T) {
	_, err := Resolve(argList("--profile", "dev,dev"), "", map[string]Files{"dev": {}})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "duplicate")
}

func TestResolve_RejectsUnknown(t *testing.T) {
	_, err := Resolve(argList("--profile", "ghost"), "", map[string]Files{"dev": {}})
	require.Error(t, err)
	assert.Contains(t, err.Error(), "not found")
}

func TestResolve_FlagMissingValue(t *testing.T) {
	_, err := Resolve(argList("--profile"), "", map[string]Files{})
	require.Error(t, err)
}

func TestResolve_FlagPresenceOverridesEnvEvenIfEmpty(t *testing.T) {
	// --profile "" with no env: flag is present but empty → error.
	// Confirms presence wins over fallback to env/default.
	_, err := Resolve(argList("--profile", ""), "dev", map[string]Files{"dev": {}})
	require.Error(t, err, "explicit --profile '' should error rather than silently fall back to BOOTH_PROFILES")
}

// ---------- HasProfileFlag ----------

func TestHasProfileFlag(t *testing.T) {
	assert.False(t, HasProfileFlag(argList()))
	assert.False(t, HasProfileFlag(argList("--config", "foo.toml")))
	assert.True(t, HasProfileFlag(argList("--profile", "dev")))
	assert.True(t, HasProfileFlag(argList("--code", ".", "--profile", "dev")))
}
