// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
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

func TestMergeProfileToml_BoolCanBeResetToFalse(t *testing.T) {
	cfg := &AppConfig{KeepAlive: true, Daemon: true}

	path := writeTempToml(t, `
keep-alive = false
`)

	require.NoError(t, MergeProfileToml(path, cfg))

	assert.False(t, cfg.KeepAlive, "an explicit false in the profile must override a true base")
	assert.True(t, cfg.Daemon, "a bool absent from the profile keeps the base value")
}

// egress-allowlist is a plain []string, not one of the concat-and-dedup lists,
// so a profile that sets it REPLACES the base list. This pins that behavior as
// documented in docs/BOOTH_PROFILES.md; changing it to a union is a deliberate
// decision, and this test is where that change should show up.
func TestMergeProfileToml_EgressAllowlistReplacesNotMerges(t *testing.T) {
	cfg := &AppConfig{EgressAllowlist: []string{"base.example.com"}}

	path := writeTempToml(t, `
egress-allowlist = ["dev.example.com"]
`)

	require.NoError(t, MergeProfileToml(path, cfg))

	assert.Equal(t, []string{"dev.example.com"}, cfg.EgressAllowlist,
		"egress-allowlist set in a profile replaces the base list")
}

func TestMergeProfileToml_EgressAllowlistAbsentLeavesBaseUnchanged(t *testing.T) {
	cfg := &AppConfig{EgressAllowlist: []string{"base.example.com"}}

	path := writeTempToml(t, `
port = "14000"
`)

	require.NoError(t, MergeProfileToml(path, cfg))

	assert.Equal(t, []string{"base.example.com"}, cfg.EgressAllowlist)
}

// Every list-typed config key must have a declared profile-merge rule.
//
// MergeProfileToml unions the docker-arg lists by field name; anything else
// that decodes from TOML silently REPLACES. That is right for cmds (one
// logical command) but easy to get wrong by accident when a new list key is
// added. This test fails on any list-typed key that is in neither set below,
// so adding one forces a decision — and a matching update to
// docs/BOOTH_PROFILES.md.
func TestMergeProfileToml_EveryListKeyHasADeclaredRule(t *testing.T) {
	unioned := map[string]bool{ // concat-and-dedup in MergeProfileToml
		"common-args": true,
		"build-args":  true,
		"run-args":    true,
	}
	replaced := map[string]bool{ // later profile wins outright
		"cmds":             true,
		"egress-allowlist": true,
	}

	semicolonList := reflect.TypeOf(ilist.SemicolonStringList{})
	typ := reflect.TypeOf(AppConfig{})
	for i := 0; i < typ.NumField(); i++ {
		field := typ.Field(i)
		if field.Type.Kind() != reflect.Slice && field.Type != semicolonList {
			continue
		}
		key := strings.Split(field.Tag.Get("toml"), ",")[0]
		if key == "" || key == "-" {
			continue // not readable from a profile config.toml
		}
		assert.Truef(t, unioned[key] || replaced[key],
			"list-typed config key %q (AppConfig.%s) has no declared profile-merge rule: "+
				"union it in MergeProfileToml, or add it to `replaced` here, and document it in docs/BOOTH_PROFILES.md",
			key, field.Name)
	}
}
