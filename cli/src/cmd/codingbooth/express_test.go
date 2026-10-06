// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseExpressArgs(t *testing.T) {
	code := t.TempDir()

	tests := []struct {
		name       string
		args       []string
		wantCode   string
		wantLaunch []string
		wantPort   string
		wantSelect []string
		wantCmds   []string
		daemon     bool
	}{
		{
			name:       "the code path is mounted by express, not forwarded twice",
			args:       []string{"--code", code, "--dryrun"},
			wantCode:   code,
			wantLaunch: []string{"--dryrun"},
		},
		{
			name:       "--select is compiled and not passed to docker",
			args:       []string{"--select", "go+vscode-ext", "--expose", "8080", "--env", "FOO=1"},
			wantSelect: []string{"go+vscode-ext"},
			wantLaunch: nil,
		},
		{
			name:       "--variant and --port stay on the launch line",
			args:       []string{"--variant", "codeserver", "--port", "12000"},
			wantPort:   "12000",
			wantLaunch: []string{"--variant", "codeserver", "--port", "12000"},
		},
		{
			name:       "a docker flag and its value are forwarded one token at a time",
			args:       []string{"-e", "FOO=1", "--cpus", "1"},
			wantLaunch: []string{"-e", "FOO=1", "--cpus", "1"},
		},
		{
			name:       "arguments after -- are the command",
			args:       []string{"--port", "12000", "--", "echo", "hi"},
			wantPort:   "12000",
			wantLaunch: []string{"--port", "12000", "--", "echo", "hi"},
		},
		{
			name:       "--cmd is compiled and not forwarded",
			args:       []string{"--cmd", "echo hi"},
			wantCmds:   []string{"echo", "hi"},
			wantLaunch: nil,
		},
		{
			name:       "--daemon is recorded and still a launch flag",
			args:       []string{"--daemon", "--name", "demo-{port}"},
			wantLaunch: []string{"--daemon", "--name", "demo-{port}"},
			daemon:     true,
		},
		{
			name:       "--show-run-time keeps an optional value as the next token",
			args:       []string{"--show-run-time", "5", "--dryrun"},
			wantLaunch: []string{"--show-run-time", "5", "--dryrun"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			plan, err := parseExpressArgs(tt.args)
			require.NoError(t, err)
			assert.Equal(t, tt.wantCode, plan.code)
			assert.Equal(t, tt.wantLaunch, plan.launch)
			assert.Equal(t, tt.wantPort, plan.flags.port)
			assert.Equal(t, tt.wantSelect, plan.flags.selectDSLs)
			assert.Equal(t, tt.wantCmds, plan.flags.cmds)
			assert.Equal(t, tt.daemon, plan.daemon)
			if tt.daemon {
				assert.Equal(t, "demo-{port}", plan.name)
			}
		})
	}
}

func TestParseExpressArgsRefuses(t *testing.T) {
	tests := []struct {
		name string
		args []string
		want string
	}{
		{"--config is refused", []string{"--config"}, "--config"},
		{"--profile is refused", []string{"--profile"}, "--profile"},
		{"--booth-dir is refused", []string{"--booth-dir"}, "--booth-dir"},
		{"--select cannot be combined with --image", []string{"--select", "go", "--image", "demo:latest"}, "--select"},
		{"--apt-snapshot requires --select", []string{"--apt-snapshot", "none"}, "--select"},
		{"--set public is not a file key", []string{"--set", "public=true"}, "public"},
		{"--set cache-files is not available", []string{"--set", "cache-files=a"}, "cache-files"},
		{"--set of an unknown key is refused", []string{"--set", "not-a-real-key=1"}, "not-a-real-key"},
		{"--port without a value is refused", []string{"--port"}, "--port requires a value"},
		{"--writable-booth is refused even without a value", []string{"--writable-booth"}, "--writable-booth"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := parseExpressArgs(tt.args)
			require.Error(t, err)
			assert.Contains(t, err.Error(), tt.want)
		})
	}
}

func TestParseExpressArgsAllowsTemplatesPathWithoutSelect(t *testing.T) {
	plan, err := parseExpressArgs([]string{"--variant", "xfce", "--templates-path", "/tmp/templates"})
	require.NoError(t, err)
	assert.Empty(t, plan.flags.selectDSLs)
	assert.NotContains(t, plan.launch, "--templates-path")
}

func TestParseExpressArgsKeepsAFileKey(t *testing.T) {
	plan, err := parseExpressArgs([]string{"--set", "timezone=UTC"})
	require.NoError(t, err)
	assert.Equal(t, []string{"timezone=UTC"}, plan.flags.sets)
	assert.Empty(t, plan.launch)
}

func TestExpressPersistsForDaemonKeepAliveAndEnv(t *testing.T) {
	assert.False(t, expressPersists(expressPlan{}))
	assert.True(t, expressPersists(expressPlan{daemon: true}))
	assert.True(t, expressPersists(expressPlan{keepAlive: true}))

	t.Setenv("CB_KEEP_ALIVE", "true")
	assert.True(t, expressPersists(expressPlan{}))
	t.Setenv("CB_KEEP_ALIVE", "false")
	t.Setenv("CB_DAEMON", "1")
	assert.True(t, expressPersists(expressPlan{}))
}

func TestExpressCacheDirReusesTheSameCodeAndName(t *testing.T) {
	root := t.TempDir()
	first, err := expressCacheDir(root, "/work/demo", "demo-{port}")
	require.NoError(t, err)
	second, err := expressCacheDir(root, "/work/demo", "demo-{port}")
	require.NoError(t, err)
	assert.Equal(t, first, second)

	other, err := expressCacheDir(root, "/work/demo", "other")
	require.NoError(t, err)
	assert.NotEqual(t, first, other)
	assert.True(t, strings.HasPrefix(first, filepath.Join(root, "codingbooth", "express")))
}

func TestRemoveExpressTempSpecLeavesOtherDirectories(t *testing.T) {
	tempSpec, err := os.MkdirTemp("", "codingbooth-express-")
	require.NoError(t, err)
	boothDir := filepath.Join(tempSpec, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	removeExpressTempSpec(boothDir)
	_, statErr := os.Stat(tempSpec)
	assert.True(t, os.IsNotExist(statErr), "a foreground express spec is removed")

	cache := t.TempDir()
	cacheSpec, err := expressCacheDir(cache, "/work/demo", "demo")
	require.NoError(t, err)
	cacheBooth := filepath.Join(cacheSpec, ".booth")
	require.NoError(t, os.MkdirAll(cacheBooth, 0755))
	removeExpressTempSpec(cacheBooth)
	_, statErr = os.Stat(cacheSpec)
	assert.NoError(t, statErr, "a cache spec is kept")

	other := filepath.Join(t.TempDir(), "codingbooth-express-nested")
	require.NoError(t, os.MkdirAll(filepath.Join(other, ".booth"), 0755))
	removeExpressTempSpec(filepath.Join(other, ".booth"))
	_, statErr = os.Stat(other)
	assert.NoError(t, statErr, "a nested directory with the temp prefix is kept")
}

func TestCompileExpressSpecSelectWritesTheSpecNotTheProject(t *testing.T) {
	project := t.TempDir()
	require.NoError(t, os.WriteFile(filepath.Join(project, "keep.txt"), []byte("stay"), 0644))
	spec := t.TempDir()

	plan := expressPlan{
		code: project,
		flags: initFlags{
			selectDSLs:    []string{"go"},
			templatesPath: expressTestTemplates(t),
		},
	}
	wroteConfig, wroteBoothfile, err := compileExpressSpec(plan, spec, "test")
	require.NoError(t, err)
	assert.True(t, wroteConfig)
	assert.True(t, wroteBoothfile)
	_, err = os.Stat(filepath.Join(spec, ".booth", "Boothfile"))
	assert.NoError(t, err)
	_, err = os.Stat(filepath.Join(spec, ".booth", "config.toml"))
	assert.NoError(t, err)
	_, err = os.Stat(filepath.Join(project, ".booth"))
	assert.True(t, os.IsNotExist(err), "the project .booth stays absent")
	kept, err := os.ReadFile(filepath.Join(project, "keep.txt"))
	require.NoError(t, err)
	assert.Equal(t, "stay", string(kept))
}

func TestCompileExpressSpecWithoutSelectDoesNotWriteAnEmptyBoothfile(t *testing.T) {
	spec := t.TempDir()
	plan := expressPlan{flags: initFlags{envs: []string{"FOO=1"}, variant: "codeserver", port: "12000"}}
	wroteConfig, wroteBoothfile, err := compileExpressSpec(plan, spec, "test")
	require.NoError(t, err)
	assert.True(t, wroteConfig)
	assert.False(t, wroteBoothfile)
	_, err = os.Stat(filepath.Join(spec, ".booth", "Boothfile"))
	assert.True(t, os.IsNotExist(err))

	empty := t.TempDir()
	wroteConfig, wroteBoothfile, err = compileExpressSpec(expressPlan{flags: initFlags{variant: "base"}}, empty, "test")
	require.NoError(t, err)
	assert.False(t, wroteConfig)
	assert.False(t, wroteBoothfile)
}

func expressTestTemplates(t *testing.T) string {
	t.Helper()
	abs, err := filepath.Abs("../../../../templates")
	require.NoError(t, err)
	info, err := os.Stat(filepath.Join(abs, "languages", "go", "template.toml"))
	require.NoError(t, err)
	require.False(t, info.IsDir())
	return abs
}
