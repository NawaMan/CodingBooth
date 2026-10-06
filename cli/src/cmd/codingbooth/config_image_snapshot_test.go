// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bytes"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// clearImageEnv unsets every variable boothImageFor falls back to, so a value set
// in the developer's shell cannot decide a test.
func clearImageEnv(t *testing.T) {
	t.Helper()
	for _, name := range []string{"CB_IMAGE", "CB_PREBUILD_REPO", "CB_VARIANT", "CB_VERSION", "CB_ENGINE"} {
		t.Setenv(name, "")
	}
}

// stubImageLabel stands in for the engine: every image carries label value.
// It returns a pointer to the number of times the engine was asked.
func stubImageLabel(t *testing.T, value string) *int {
	t.Helper()
	calls := 0
	original := readImageLabel
	readImageLabel = func(engine, ref, label string) string {
		calls++
		return value
	}
	t.Cleanup(func() { readImageLabel = original })
	return &calls
}

func TestBoothImageFor_FollowsTheRunsRule(t *testing.T) {
	clearImageEnv(t)
	docker := map[string]string{"engine": "docker"}
	with := func(extra map[string]string) map[string]string {
		settings := map[string]string{"engine": "docker"}
		for k, v := range extra {
			settings[k] = v
		}
		return settings
	}

	for _, tc := range []struct {
		name     string
		settings map[string]string
		want     string
	}{
		{"no variant is base, at the booth's pinned version", docker, "nawaman/codingbooth:base-0.80.0"},
		{"an alias names its variant's image", with(map[string]string{"variant": "xfce"}), "nawaman/codingbooth:desktop-xfce-0.80.0"},
		{"default is base", with(map[string]string{"variant": "default"}), "nawaman/codingbooth:base-0.80.0"},
		{"config.toml's version wins over the pinned one", with(map[string]string{"version": "0.79.0"}), "nawaman/codingbooth:base-0.79.0"},
	} {
		image, ok := boothImageFor(tc.settings, "0.80.0")
		require.True(t, ok, tc.name)
		assert.Equal(t, tc.want, image.Ref, tc.name)
		assert.Equal(t, "docker", image.Engine, tc.name)
	}
}

func TestBoothImageFor_EnvFillsWhatConfigLeavesUnset(t *testing.T) {
	clearImageEnv(t)
	t.Setenv("CB_VARIANT", "notebook")
	t.Setenv("CB_PREBUILD_REPO", "example.com/mirror/codingbooth")
	t.Setenv("CB_ENGINE", "podman")

	image, ok := boothImageFor(map[string]string{}, "0.80.0")
	require.True(t, ok)
	assert.Equal(t, boothImage{Ref: "example.com/mirror/codingbooth:notebook-0.80.0", Engine: "podman"}, image)

	image, ok = boothImageFor(map[string]string{"variant": "codeserver", "engine": "docker"}, "0.80.0")
	require.True(t, ok)
	assert.Equal(t, boothImage{Ref: "example.com/mirror/codingbooth:codeserver-0.80.0", Engine: "docker"}, image,
		"config.toml's value wins over the variable, as in a run")
}

func TestBoothImageFor_UnknownWhenItCannotBeNamed(t *testing.T) {
	clearImageEnv(t)
	for name, settings := range map[string]map[string]string{
		"an image override":  {"engine": "docker", "image": "my/own:image"},
		"an unknown variant": {"engine": "docker", "variant": "bogus"},
		"an unknown engine":  {"engine": "lxc"},
	} {
		_, ok := boothImageFor(settings, "0.80.0")
		assert.False(t, ok, name)
	}

	t.Setenv("CB_PREBUILD_REPO", "bad repo; rm -rf")
	_, ok := boothImageFor(map[string]string{"engine": "docker"}, "0.80.0")
	assert.False(t, ok, "a malformed CB_PREBUILD_REPO")
}

func TestOlderThanImageWarning(t *testing.T) {
	ref := "nawaman/codingbooth:base-0.80.0"
	assert.Empty(t, olderThanImageWarning("", ref, "20261004T000000Z"), "no freeze")
	assert.Empty(t, olderThanImageWarning("20250101T000000Z", ref, ""), "image snapshot unknown")
	assert.Empty(t, olderThanImageWarning("20261004T000000Z", ref, "20261004T000000Z"), "the image's own")
	assert.Empty(t, olderThanImageWarning("20261010T000000Z", ref, "20261004T000000Z"), "newer")

	assert.Equal(t,
		"Warning: apt snapshot 20250101T000000Z is older than this booth's image (nawaman/codingbooth:base-0.80.0, built at 20261004T000000Z).\n"+
			"  `install apt` can fail on a package needing an exact version of one the image already has newer.\n"+
			"  To use the image's: booth config --apt-snapshot 20261004T000000Z",
		olderThanImageWarning("20250101T000000Z", ref, "20261004T000000Z"))
}

func TestWarnAptSnapshotOlderThanImage(t *testing.T) {
	clearImageEnv(t)
	generated := func(snapshot string) *output.BoothOutput {
		return &output.BoothOutput{
			Config:    &output.ConfigToml{Variant: "xfce", Overrides: map[string]interface{}{"engine": "docker"}},
			Boothfile: &output.BoothfileContent{Content: "env APT_SNAPSHOT=" + snapshot + "\n\nsetup go\n"},
		}
	}

	stubImageLabel(t, "20261004T000000Z")
	var stderr bytes.Buffer
	warnAptSnapshotOlderThanImage(&stderr, generated("20250101T000000Z"), t.TempDir(), "0.80.0")
	assert.Contains(t, stderr.String(), "older than this booth's image (nawaman/codingbooth:desktop-xfce-0.80.0, built at 20261004T000000Z)")
	assert.Contains(t, stderr.String(), "booth config --apt-snapshot 20261004T000000Z")

	for name, snapshot := range map[string]string{"no freeze": "", "newer": "20261010T000000Z"} {
		stderr.Reset()
		warnAptSnapshotOlderThanImage(&stderr, generated(snapshot), t.TempDir(), "0.80.0")
		assert.Empty(t, stderr.String(), name)
	}

	// The image is not on this machine (or predates the label): no claim.
	stubImageLabel(t, "")
	stderr.Reset()
	warnAptSnapshotOlderThanImage(&stderr, generated("20250101T000000Z"), t.TempDir(), "0.80.0")
	assert.Empty(t, stderr.String())

	stubImageLabel(t, "not-a-snapshot")
	warnAptSnapshotOlderThanImage(&stderr, generated("20250101T000000Z"), t.TempDir(), "0.80.0")
	assert.Empty(t, stderr.String(), "a label that is not a snapshot id is not a basis to warn")
}

// The TUI asks on every redraw; the engine should be asked once per image.
func TestImageSnapshotLookup_AsksTheEngineOncePerImage(t *testing.T) {
	clearImageEnv(t)
	calls := stubImageLabel(t, "20261004T000000Z")
	lookup := imageSnapshotLookup("0.80.0")

	for range 3 {
		ref, snapshot := lookup(map[string]string{"engine": "docker", "variant": "base"})
		assert.Equal(t, "nawaman/codingbooth:base-0.80.0", ref)
		assert.Equal(t, "20261004T000000Z", snapshot)
	}
	assert.Equal(t, 1, *calls)

	ref, _ := lookup(map[string]string{"engine": "docker", "variant": "kde"})
	assert.Equal(t, "nawaman/codingbooth:desktop-kde-0.80.0", ref, "a variant change is a different image")
	assert.Equal(t, 2, *calls)
}
