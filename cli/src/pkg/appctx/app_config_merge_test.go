// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func writeTempToml(t *testing.T, content string) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "profile.toml")
	require.NoError(t, os.WriteFile(path, []byte(content), 0644))
	return path
}

func TestMergeProfileToml_ScalarOverwriteWhenPresent(t *testing.T) {
	cfg := &AppConfig{
		Port:        "12000",
		ProjectName: "base-project",
		Variant:     "default",
	}

	path := writeTempToml(t, `
port = "14000"
project-name = "dev-project"
`)

	err := MergeProfileToml(path, cfg)
	require.NoError(t, err)

	assert.Equal(t, "14000", cfg.Port, "port set in profile should overwrite base")
	assert.Equal(t, "dev-project", cfg.ProjectName, "project-name in profile should overwrite base")
	assert.Equal(t, "default", cfg.Variant, "variant absent from profile should retain base value")
}

func TestMergeProfileToml_ArrayConcatAndDedup(t *testing.T) {
	cfg := &AppConfig{
		RunArgs: ilist.SemicolonStringList{List: ilist.NewList("--foo", "-v", "/tmp:/tmp")},
	}

	path := writeTempToml(t, `
run-args = ["--bar", "-v", "/etc:/etc"]
`)

	err := MergeProfileToml(path, cfg)
	require.NoError(t, err)

	got := cfg.RunArgs.Slice()
	assert.Equal(t, []string{"--foo", "-v", "/tmp:/tmp", "--bar", "-v", "/etc:/etc"}, got,
		"arrays should concatenate; paired -v flags with different values both kept")
}

func TestMergeProfileToml_ArrayDedupesIdenticalPairs(t *testing.T) {
	cfg := &AppConfig{
		RunArgs: ilist.SemicolonStringList{List: ilist.NewList("-v", "/tmp:/tmp", "--bar")},
	}

	path := writeTempToml(t, `
run-args = ["-v", "/tmp:/tmp", "--baz"]
`)

	err := MergeProfileToml(path, cfg)
	require.NoError(t, err)

	got := cfg.RunArgs.Slice()
	assert.Equal(t, []string{"-v", "/tmp:/tmp", "--bar", "--baz"}, got,
		"identical -v pair should be deduped while preserving order")
}

func TestMergeProfileToml_ArrayAbsentLeavesUnchanged(t *testing.T) {
	cfg := &AppConfig{
		RunArgs: ilist.SemicolonStringList{List: ilist.NewList("--keep")},
	}

	path := writeTempToml(t, `
port = "15000"
`)

	err := MergeProfileToml(path, cfg)
	require.NoError(t, err)

	got := cfg.RunArgs.Slice()
	assert.Equal(t, []string{"--keep"}, got,
		"profile without run-args should leave accumulator's run-args unchanged")
	assert.Equal(t, "15000", cfg.Port)
}

func TestMergeProfileToml_EmptyArrayInProfileIsNoop(t *testing.T) {
	cfg := &AppConfig{
		RunArgs: ilist.SemicolonStringList{List: ilist.NewList("--keep")},
	}

	path := writeTempToml(t, `
run-args = []
`)

	err := MergeProfileToml(path, cfg)
	require.NoError(t, err)

	got := cfg.RunArgs.Slice()
	assert.Equal(t, []string{"--keep"}, got,
		"empty array in profile concatenates with accumulator and dedupes to original")
}

func TestMergeProfileToml_MissingFileReturnsError(t *testing.T) {
	cfg := &AppConfig{}
	err := MergeProfileToml("/nonexistent/path/profile.toml", cfg)
	assert.Error(t, err)
}

func TestMergeProfileToml_CmdsReplaceNotMerge(t *testing.T) {
	cfg := &AppConfig{
		Cmds: ilist.SemicolonStringList{List: ilist.NewList("echo", "FROM_BASE")},
	}

	path := writeTempToml(t, `
cmds = ["echo", "FROM_PROFILE"]
`)

	err := MergeProfileToml(path, cfg)
	require.NoError(t, err)

	assert.Equal(t, []string{"echo", "FROM_PROFILE"}, cfg.Cmds.Slice(),
		"cmds represents one command — profile must REPLACE base, not concat (which would dedup the duplicate 'echo' and yield meaningless output)")
}

func TestMergeProfileToml_CmdsAbsentLeavesBaseUnchanged(t *testing.T) {
	cfg := &AppConfig{
		Cmds: ilist.SemicolonStringList{List: ilist.NewList("echo", "FROM_BASE")},
	}

	path := writeTempToml(t, `
port = "13000"
`)

	err := MergeProfileToml(path, cfg)
	require.NoError(t, err)

	assert.Equal(t, []string{"echo", "FROM_BASE"}, cfg.Cmds.Slice(),
		"cmds absent from profile must leave the base cmds intact")
}
