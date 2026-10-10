// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"strings"
	"testing"

	"github.com/BurntSushi/toml"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// A --set for a key config.toml already writes from its own field must merge into
// that field. Left in Overrides, the key is written twice, and a booth with the
// same key twice in config.toml refuses to start ("Key ... has already been defined").
func TestApplySetOverrides_FieldKeysAreNeverWrittenTwice(t *testing.T) {
	sudo := true
	cases := map[string]struct {
		cfg   output.ConfigToml
		value interface{}
	}{
		"run-args":    {output.ConfigToml{RunArgs: []string{"-v", "booth-pgdata:/var/lib/postgresql"}}, []string{"--cap-add", "SYS_PTRACE"}},
		"build-args":  {output.ConfigToml{BuildArgs: []string{"--platform", "linux/amd64"}}, []string{"--no-cache"}},
		"cmds":        {output.ConfigToml{Cmds: []string{"bash"}}, []string{"zsh"}},
		"sudo":        {output.ConfigToml{Sudo: &sudo}, false},
		"vm-memory":   {output.ConfigToml{VmMemory: "4G"}, "8G"},
		"vm-cpus":     {output.ConfigToml{VmCpus: "2"}, 4},
		"vm-shm-size": {output.ConfigToml{VmShmSize: "1G"}, "2G"},
	}
	for key, c := range cases {
		t.Run(key, func(t *testing.T) {
			cfg := c.cfg
			applySetOverrides(&cfg, map[string]interface{}{key: c.value})
			assert.Empty(t, cfg.Overrides, "%s must merge into its field", key)

			content := output.SerializeConfigToml(&cfg, "", "")
			assert.Equal(t, 1, strings.Count(content, "\n"+key+" ="), "%s written once:\n%s", key, content)
			var decoded map[string]interface{}
			_, err := toml.Decode(content, &decoded)
			require.NoError(t, err, "config.toml must stay valid TOML:\n%s", content)
		})
	}
}

func TestApplySetOverrides_RunArgsAppendAfterTemplate(t *testing.T) {
	cfg := &output.ConfigToml{RunArgs: []string{"-v", "booth-pgdata:/var/lib/postgresql"}}
	applySetOverrides(cfg, map[string]interface{}{"run-args": []string{"--device", "/dev/fuse"}})
	assert.Equal(t, []string{"-v", "booth-pgdata:/var/lib/postgresql", "--device", "/dev/fuse"}, cfg.RunArgs)
}

func TestApplySetOverrides_CmdsReplace(t *testing.T) {
	cfg := &output.ConfigToml{Cmds: []string{"bash"}}
	applySetOverrides(cfg, map[string]interface{}{"cmds": []string{"zsh"}})
	assert.Equal(t, []string{"zsh"}, cfg.Cmds)
}

func TestResolveRunArgs_UserMountReplacesTemplateMountOnSameTarget(t *testing.T) {
	got := resolveRunArgs([]string{
		"-v", "booth-pgdata-{project}:/var/lib/postgresql", // template
		"-p", "5432:5432",
		"--volume", "myproj-pgdata:/var/lib/postgresql", // user --mount
	})
	assert.Equal(t, []string{
		"-p", "5432:5432",
		"--volume", "myproj-pgdata:/var/lib/postgresql",
	}, got)
}

func TestResolveRunArgs_TargetMatchIgnoresOptions(t *testing.T) {
	got := resolveRunArgs([]string{
		"-v", "~/.aws:/etc/cb-home-seed/.aws:ro",
		"--volume", "/other/aws:/etc/cb-home-seed/.aws",
	})
	assert.Equal(t, []string{"--volume", "/other/aws:/etc/cb-home-seed/.aws"}, got)
}

// A credential extension lists one host path per platform for the same target; the
// run pipeline keeps the first that exists. Configure must keep all of them.
func TestResolveRunArgs_TemplateAlternativesOnOneTargetAllKept(t *testing.T) {
	in := []string{
		"-v", "~/.config/pip:/etc/cb-home-seed/.config/pip:ro",
		"-v", "~/Library/Application Support/pip:/etc/cb-home-seed/.config/pip:ro",
		"-v", "~/AppData/Roaming/pip:/etc/cb-home-seed/.config/pip:ro",
	}
	assert.Equal(t, in, resolveRunArgs(in))
}

// ...and a user mount on that target replaces all of them.
func TestResolveRunArgs_UserMountReplacesAllTemplateAlternatives(t *testing.T) {
	got := resolveRunArgs([]string{
		"-v", "~/.config/pip:/etc/cb-home-seed/.config/pip:ro",
		"-v", "~/AppData/Roaming/pip:/etc/cb-home-seed/.config/pip:ro",
		"--volume", "/team/pip:/etc/cb-home-seed/.config/pip:ro",
	})
	assert.Equal(t, []string{"--volume", "/team/pip:/etc/cb-home-seed/.config/pip:ro"}, got)
}

func TestResolveRunArgs_DifferentTargetsAllKept(t *testing.T) {
	in := []string{
		"-v", "booth-pgdata-{project}:/var/lib/postgresql",
		"--volume", "myproj-data:/home/coder/.mydata",
		"--pull=never",
	}
	assert.Equal(t, in, resolveRunArgs(in))
}

func TestResolveRunArgs_IdenticalPairsKeptOnce(t *testing.T) {
	got := resolveRunArgs([]string{
		"--env", "A=1",
		"-p", "3000:3000",
		"--env", "A=1",
	})
	assert.Equal(t, []string{"--env", "A=1", "-p", "3000:3000"}, got)
}

func TestResolveRunArgs_Empty(t *testing.T) {
	assert.Empty(t, resolveRunArgs(nil))
}
