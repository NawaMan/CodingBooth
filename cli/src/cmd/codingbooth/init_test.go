// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestParseInitFlags_Port(t *testing.T) {
	flags := parseInitFlags([]string{"--select", "python", "--port", "10080"})
	assert.Equal(t, []string{"python"}, flags.selectDSLs)
	assert.Equal(t, "10080", flags.port)
}

func TestBuildInitCommand_IncludesPort(t *testing.T) {
	flags := initFlags{
		selectDSL: "python",
		port:      "10080",
	}
	cmd := buildInitCommand(".", flags)
	assert.Contains(t, cmd, "--select python")
	assert.Contains(t, cmd, "--port 10080")
}

func TestBuildAdjustCommand_IncludesPortBeforeSelect(t *testing.T) {
	flags := initFlags{
		selectDSL: "python",
		port:      "10080",
	}
	cmd := buildAdjustCommand(flags)
	assert.Contains(t, cmd, "--port 10080")
	assert.Contains(t, cmd, "--select python")
	assert.Less(t, strings.Index(cmd, "--port 10080"), strings.Index(cmd, "--select python"))
}

// --set flag parsing

func TestParseInitFlags_Set(t *testing.T) {
	flags := parseInitFlags([]string{"--select", "go", "--set", "dind", "--set", "port=8080"})
	assert.Equal(t, []string{"go"}, flags.selectDSLs)
	assert.Equal(t, []string{"dind", "port=8080"}, flags.sets)
}

func TestParseInitFlags_SetCoexistsWithPort(t *testing.T) {
	flags := parseInitFlags([]string{"--select", "go", "--port", "3000", "--set", "keep-alive"})
	assert.Equal(t, "3000", flags.port)
	assert.Equal(t, []string{"keep-alive"}, flags.sets)
}

// parseSetOverrides

func TestParseSetOverrides_BareKey(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind"})
	assert.NoError(t, err)
	assert.Equal(t, true, result["dind"])
}

func TestParseSetOverrides_BooleanTrue(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind=true"})
	assert.NoError(t, err)
	assert.Equal(t, true, result["dind"])
}

func TestParseSetOverrides_BooleanFalse(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind=false"})
	assert.NoError(t, err)
	assert.Equal(t, false, result["dind"])
}

func TestParseSetOverrides_StringValue(t *testing.T) {
	result, err := parseSetOverrides([]string{"name=my-booth"})
	assert.NoError(t, err)
	assert.Equal(t, "my-booth", result["name"])
}

func TestParseSetOverrides_EmptyKey(t *testing.T) {
	_, err := parseSetOverrides([]string{"=value"})
	assert.Error(t, err)
}

func TestParseSetOverrides_InvalidKeyWithSpace(t *testing.T) {
	_, err := parseSetOverrides([]string{"bad key=value"})
	assert.Error(t, err)
}

func TestParseSetOverrides_MultipleValues(t *testing.T) {
	result, err := parseSetOverrides([]string{"dind", "keep-alive", "name=test"})
	assert.NoError(t, err)
	assert.Equal(t, true, result["dind"])
	assert.Equal(t, true, result["keep-alive"])
	assert.Equal(t, "test", result["name"])
}

// parseSetOverrides — typing against the config schema.
//
// The Go type here decides the TOML shape written to config.toml. An integer key
// carried as a string produced `idle-time = "30"`, which booth then refused to
// decode at all — the booth was unstartable until the line was removed by hand.

func TestParseSetOverrides_IntegerKeyIsAnInt(t *testing.T) {
	result, err := parseSetOverrides([]string{"idle-time=30"})
	assert.NoError(t, err)
	assert.Equal(t, 30, result["idle-time"], "an int-typed key must not be carried as a string")
}

func TestParseSetOverrides_IntegerKeyRejectsNonNumber(t *testing.T) {
	_, err := parseSetOverrides([]string{"idle-time=soon"})
	assert.Error(t, err)
}

func TestParseSetOverrides_UnknownKeyIsRejected(t *testing.T) {
	_, err := parseSetOverrides([]string{"totally-bogus-key=42"})
	assert.Error(t, err, "an unknown key would be written and then silently ignored forever")
}

func TestParseSetOverrides_TypoSuggestsTheRealKey(t *testing.T) {
	_, err := parseSetOverrides([]string{"persist-hom"})
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "persist-home")
}

func TestParseSetOverrides_BareKeyRejectedForNonBool(t *testing.T) {
	// "turn it on" only reads as an intent for a boolean; for a string the value
	// is missing rather than implied.
	_, err := parseSetOverrides([]string{"timezone"})
	assert.Error(t, err)
}

func TestParseSetOverrides_BooleanKeyRejectsNonBool(t *testing.T) {
	_, err := parseSetOverrides([]string{"dind=maybe"})
	assert.Error(t, err)
}

func TestParseSetOverrides_ListKeyAccumulates(t *testing.T) {
	result, err := parseSetOverrides([]string{"egress-allowlist=a.com", "egress-allowlist=b.com"})
	assert.NoError(t, err)
	assert.Equal(t, []string{"a.com", "b.com"}, result["egress-allowlist"])
}

func TestDropUnknownSets_KeepsKnownDropsStale(t *testing.T) {
	// Settings recovered from an existing booth's header are history, not intent.
	// `--set debug` was written by the config TUI for as long as it treated debug
	// as a config value, so refusing the run over it would leave those booths
	// impossible to reconfigure.
	kept := dropUnknownSets([]string{"keep-alive", "debug", "timezone=Asia/Bangkok"}, ".booth/Boothfile")
	assert.Equal(t, []string{"keep-alive", "timezone=Asia/Bangkok"}, kept)
}

func TestDropUnknownSets_DropsKeysBoothNeverReadsFromFile(t *testing.T) {
	// public/tls-cert/tls-key are real settings, but start-time only — booth does
	// not read them from a file. The config TUI offered them until that was found
	// out, so booths configured before then still record them; re-emitting the
	// line on every reconfigure would keep a setting that never takes effect.
	kept := dropUnknownSets([]string{"public", "tls-cert=/tmp/a.pem", "keep-alive"}, ".booth/Boothfile")
	assert.Equal(t, []string{"keep-alive"}, kept)
}

func TestDropUnknownSets_LeavesEmptyAlone(t *testing.T) {
	assert.Empty(t, dropUnknownSets(nil, ".booth/Boothfile"))
}

func TestParseSetOverrides_UnreadKeyIsAcceptedNotRejected(t *testing.T) {
	// `public` is tagged toml:"-" — booth never reads it from a file. It is still
	// a real setting reachable as a start-time flag, and the config TUI offers it,
	// so rejecting it would break saving. It warns instead.
	result, err := parseSetOverrides([]string{"public"})
	assert.NoError(t, err)
	assert.Equal(t, true, result["public"])
}

// applySetOverrides

func TestApplySetOverrides_KnownField_Variant(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"variant": "codeserver"})
	assert.Equal(t, "codeserver", cfg.Variant)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_KnownField_Port(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"port": "8080"})
	assert.Equal(t, "8080", cfg.Port)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_KnownField_Dind(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"dind": true})
	assert.True(t, cfg.Dind)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_UnknownField(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"keep-alive": true})
	assert.True(t, cfg.Overrides["keep-alive"].(bool))
}

func TestApplySetOverrides_CacheFiles(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"cache-files": "home/coder/.custom_history"})
	assert.Equal(t, []string{"home/coder/.custom_history"}, cfg.CacheFiles)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_CacheDirs(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"cache-dirs": "home/coder/.custom_data"})
	assert.Equal(t, []string{"home/coder/.custom_data"}, cfg.CacheDirs)
}

func TestApplySetOverrides_SharedFiles(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"shared-files": "home/coder/.chrome-data/Default/Bookmarks"})
	assert.Equal(t, []string{"home/coder/.chrome-data/Default/Bookmarks"}, cfg.SharedFiles)
}

func TestApplySetOverrides_SharedDirs(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{"shared-dirs": "home/coder/.config/myapp"})
	assert.Equal(t, []string{"home/coder/.config/myapp"}, cfg.SharedDirs)
	assert.Empty(t, cfg.Overrides)
}

func TestApplySetOverrides_MixedKnownAndUnknown(t *testing.T) {
	cfg := &output.ConfigToml{}
	applySetOverrides(cfg, map[string]interface{}{
		"variant":    "base",
		"keep-alive": true,
		"name":       "test",
	})
	assert.Equal(t, "base", cfg.Variant)
	assert.True(t, cfg.Overrides["keep-alive"].(bool))
	assert.Equal(t, "test", cfg.Overrides["name"])
}

// buildInitCommand / buildAdjustCommand with --set

func TestBuildInitCommand_IncludesSet(t *testing.T) {
	flags := initFlags{
		selectDSL: "go",
		sets:      []string{"dind", "keep-alive"},
	}
	cmd := buildInitCommand(".", flags)
	assert.Contains(t, cmd, "--set dind")
	assert.Contains(t, cmd, "--set keep-alive")
}

func TestBuildAdjustCommand_SetBeforeSelect(t *testing.T) {
	flags := initFlags{
		selectDSL: "go",
		sets:      []string{"dind"},
	}
	cmd := buildAdjustCommand(flags)
	assert.Contains(t, cmd, "--set dind")
	assert.Contains(t, cmd, "--select go")
	assert.Less(t, strings.Index(cmd, "--set dind"), strings.Index(cmd, "--select go"))
}

// --- applyExposeFlags / applyEnvFlags / applyMountFlags: long-form convention ---

func TestApplyEnvFlags_LongForm(t *testing.T) {
	cfg := &output.ConfigToml{}
	applyEnvFlags(cfg, []string{"FOO=bar", "BAZ=qux"})

	// Must use --env (long-form), not -e (short-form)
	assert.Equal(t, []string{"--env", "FOO=bar", "--env", "BAZ=qux"}, cfg.RunArgs)
	assert.NotContains(t, cfg.RunArgs, "-e")
}

func TestApplyExposeFlags_LongForm(t *testing.T) {
	cfg := &output.ConfigToml{}
	applyExposeFlags(cfg, []string{"8080", "9090:3000"})

	// Must use --publish (long-form), not -p (short-form)
	assert.Equal(t, []string{"--publish", "8080:8080", "--publish", "9090:3000"}, cfg.RunArgs)
	assert.NotContains(t, cfg.RunArgs, "-p")
}

func TestApplyExposeFlags_LongForm_OffsetFormat(t *testing.T) {
	cfg := &output.ConfigToml{}
	applyExposeFlags(cfg, []string{"+8080", "+3000:5000"})

	assert.Equal(t, []string{"--publish", "+8080:8080", "--publish", "+3000:5000"}, cfg.RunArgs)
	assert.NotContains(t, cfg.RunArgs, "-p")
}

func TestApplyExposeFlags_HostEnvForm(t *testing.T) {
	cfg := &output.ConfigToml{}
	applyExposeFlags(cfg, []string{
		"${APP_PORT:-3000}",
		"${SERVER_PORT:-12345}:1234",
		"${SERVER_PORT:-+300}:1234",
		"127.0.0.1:${HTTP_PORT:-8080}:80",
	})

	assert.Equal(t, []string{
		"--publish", "${APP_PORT:-3000}:${APP_PORT:-3000}",
		"--publish", "${SERVER_PORT:-12345}:1234",
		"--publish", "${SERVER_PORT:-+300}:1234",
		"--publish", "127.0.0.1:${HTTP_PORT:-8080}:80",
	}, cfg.RunArgs)
}

func TestValidateExpose_HostEnvForm(t *testing.T) {
	ok := []string{
		"${APP_PORT}",
		"${APP_PORT:-3000}",
		"${SERVER_PORT:-12345}:1234",
		"${SERVER_PORT:-+300}:1234",       // booth-relative fallback, explicit container
		"127.0.0.1:${HTTP_PORT:-+300}:80", // booth-relative fallback with IP
		"${HTTP_PORT}:80",
		"127.0.0.1:${HTTP_PORT:-8080}:80",
		// existing forms still accepted
		"8080",
		"9090:3000",
		"127.0.0.1:18080:8080",
		"+8080",
		"+3000:5000",
	}
	for _, v := range ok {
		assert.NoError(t, validateExpose(v), "expected valid: %q", v)
	}

	bad := []string{
		"${APP_PORT:-abc}",             // default must be digits
		"${APP_PORT:-}",                // empty default
		"${APP_PORT:-+}",               // "+" with no offset digits
		"${SERVER_PORT:-+300}",         // relative fallback needs an explicit :CONTAINER
		"${1PORT:-3000}",               // name must start with letter or _
		"8080:${APP_PORT:-3000}",       // env on container side
		"8080:${APP_PORT:-+300}",       // relative env on container side
		"127.0.0.1:${HTTP_PORT:-8080}", // IP without container
		"${APP_PORT:-3000}:",           // empty container
		"${APP_PORT:-3000}:80:extra",   // extra segment
		"$APP_PORT",                    // braces required
		"${APP_PORT:-3000",             // unclosed
	}
	for _, v := range bad {
		assert.Error(t, validateExpose(v), "expected invalid: %q", v)
	}
}

func TestApplyMountFlags_LongForm(t *testing.T) {
	cfg := &output.ConfigToml{}
	applyMountFlags(cfg, []string{"/host/a:/container/a", "/host/b:/container/b"})

	// Must use --volume (long-form), not -v (short-form)
	assert.Equal(t, []string{"--volume", "/host/a:/container/a", "--volume", "/host/b:/container/b"}, cfg.RunArgs)
	assert.NotContains(t, cfg.RunArgs, "-v")
}

// --- Round-trip test: applyFlags -> write config.toml -> extractUserRunArgs ---

func TestRoundTrip_ApplyFlags_WriteConfig_ExtractUserRunArgs(t *testing.T) {
	// Step 1: Apply flags to create a ConfigToml with long-form run-args
	cfg := &output.ConfigToml{}
	applyEnvFlags(cfg, []string{"MY_VAR=hello"})
	applyExposeFlags(cfg, []string{"8080", "+3000"})
	applyMountFlags(cfg, []string{"/data:/data"})

	// Also add some template-contributed short-form args
	cfg.RunArgs = append([]string{"-e", "TEMPLATE_VAR=1", "-p", "5000:5000", "-v", "/tmpl:/tmpl"}, cfg.RunArgs...)

	// Step 2: Serialize to TOML and write to a temp config.toml
	content := output.SerializeConfigToml(cfg, "", "")
	tmpDir := t.TempDir()
	boothDir := filepath.Join(tmpDir, ".booth")
	require.NoError(t, os.MkdirAll(boothDir, 0755))
	require.NoError(t, os.WriteFile(filepath.Join(boothDir, "config.toml"), []byte(content), 0644))

	// Step 3: Extract user run-args back from the written config.toml
	var flags initFlags
	extractUserRunArgs(tmpDir, &flags)

	// Only user-set long-form values should come back; template short-form values should be absent
	assert.Equal(t, []string{"MY_VAR=hello"}, flags.envs,
		"only long-form --env values should be extracted")
	assert.Equal(t, []string{"8080", "+3000"}, flags.exposes,
		"only long-form --publish values should be extracted, reversed back to expose form")
	assert.Equal(t, []string{"/data:/data"}, flags.mounts,
		"only long-form --volume values should be extracted")
}
