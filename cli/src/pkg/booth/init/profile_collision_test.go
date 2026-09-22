// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func overlayFile(t *testing.T, name, content string) appctx.ProfileEntry {
	t.Helper()
	path := filepath.Join(t.TempDir(), name+"--config.toml")
	require.NoError(t, os.WriteFile(path, []byte(content), 0644))
	return appctx.ProfileEntry{Name: name, ConfigPath: path}
}

func listOf(items ...string) ilist.SemicolonStringList {
	return ilist.SemicolonStringList{List: ilist.NewListFromSlice(items)}
}

func TestCheckProfileCollisions_OverlayAgainstBase(t *testing.T) {
	base := &appctx.AppConfig{RunArgs: listOf("-e", "LOG=info", "-v", "/etc:/cfg")}
	dev := overlayFile(t, "dev", `run-args = ["-e", "LOG=debug", "-v", "/usr:/cfg"]`)

	err := checkProfileCollisions(dev, base)

	require.Error(t, err)
	msg := err.Error()
	for _, want := range []string{
		`profile "dev"`, "dev--config.toml",
		"run-args: environment variable LOG", "earlier: -e LOG=info", "dev: -e LOG=debug",
		"run-args: mount target /cfg", "earlier: -v /etc:/cfg", "dev: -v /usr:/cfg",
		"docs/BOOTH_PROFILES.md",
	} {
		assert.Contains(t, msg, want)
	}
}

func TestCheckProfileCollisions_NoCollisionIsFine(t *testing.T) {
	base := &appctx.AppConfig{RunArgs: listOf("-e", "TZ=UTC", "-v", "/etc:/cfg", "-p", "39200:80")}
	dev := overlayFile(t, "dev", `run-args = ["-e", "LOG=debug", "-v", "/usr:/data", "-p", "39300:81"]`)

	assert.NoError(t, checkProfileCollisions(dev, base))
}

func TestCheckProfileCollisions_IdenticalEntryIsRedundant(t *testing.T) {
	base := &appctx.AppConfig{RunArgs: listOf("-e", "TZ=UTC")}
	dev := overlayFile(t, "dev", `run-args = ["-e", "TZ=UTC"]`)

	assert.NoError(t, checkProfileCollisions(dev, base), "repeating an entry exactly is redundant, not a collision")
}

func TestCheckProfileCollisions_PublishedPorts(t *testing.T) {
	base := &appctx.AppConfig{RunArgs: listOf("-p", "39200:80")}

	moved := overlayFile(t, "moved", `run-args = ["-p", "39300:80"]`)
	err := checkProfileCollisions(moved, base)
	require.Error(t, err, "an overlay 'moving' a port would really publish both")
	assert.Contains(t, err.Error(), "container port 80/tcp")

	taken := overlayFile(t, "taken", `run-args = ["-p", "39200:81"]`)
	err = checkProfileCollisions(taken, base)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "host port 39200/tcp")
}

func TestCheckProfileCollisions_BuildAndCommonArgs(t *testing.T) {
	base := &appctx.AppConfig{
		BuildArgs:  listOf("--build-arg", "NODE=18"),
		CommonArgs: listOf("-e", "REGION=eu"),
	}
	dev := overlayFile(t, "dev", `
build-args  = ["--build-arg", "NODE=20"]
common-args = ["-e", "REGION=us"]
`)

	err := checkProfileCollisions(dev, base)
	require.Error(t, err)
	assert.Contains(t, err.Error(), "build-args: build arg NODE")
	assert.Contains(t, err.Error(), "common-args: environment variable REGION")
}

// With --profile a,b the "earlier layer" for b is the base plus a — so b can
// collide with a profile, not just with the base.
func TestCheckProfileCollisions_LaterProfileAgainstEarlierProfile(t *testing.T) {
	cfg := &appctx.AppConfig{RunArgs: listOf("-e", "TZ=UTC")}
	a := overlayFile(t, "a", `run-args = ["-e", "LOG=debug"]`)
	b := overlayFile(t, "b", `run-args = ["-e", "LOG=trace"]`)

	require.NoError(t, checkProfileCollisions(a, cfg))
	require.NoError(t, appctx.MergeProfileToml(a.ConfigPath, cfg))

	err := checkProfileCollisions(b, cfg)
	require.Error(t, err)
	assert.Contains(t, err.Error(), `profile "b"`)
	assert.Contains(t, err.Error(), "earlier: -e LOG=debug")
	assert.Contains(t, err.Error(), "b: -e LOG=trace")
}

func TestCheckProfileCollisions_OverlayWithoutListsAndNonCollidingScalars(t *testing.T) {
	base := &appctx.AppConfig{RunArgs: listOf("-e", "LOG=info"), Port: "9000"}
	dev := overlayFile(t, "dev", `port = "9100"`)

	assert.NoError(t, checkProfileCollisions(dev, base), "scalars override by design; they are not collisions")
}

// A decode problem is reported by MergeProfileToml in its usual way, not here.
func TestCheckProfileCollisions_UnreadableOverlayIsLeftToTheMerge(t *testing.T) {
	base := &appctx.AppConfig{RunArgs: listOf("-e", "LOG=info")}
	broken := overlayFile(t, "broken", `run-args = [ this is not toml`)

	assert.NoError(t, checkProfileCollisions(broken, base))
}
