// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"io"
	"os"
	"strings"
	"sync"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/booth"
	"github.com/nawaman/codingbooth/src/pkg/boothfile"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/aptsnapshot"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/output"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// The image a booth builds FROM records the archive snapshot its own packages
// came from (docker-build.sh's com.codingbooth.apt-snapshot label). A booth
// pinned to an older one can fail to install packages that need an exact
// version of one the image already has newer — apt will not downgrade it.
// apt--install.sh fails with the fix when that happens; `booth config` warns
// before it does, when it can read the image's label: the image has to be on
// this machine already, so a first configure before any pull says nothing.

// imageSnapshotLabel is the label docker-build.sh puts on every catalog image.
const imageSnapshotLabel = "com.codingbooth.apt-snapshot"

// boothImage is the prebuilt image a booth builds FROM, and the engine to ask.
type boothImage struct {
	Ref    string
	Engine string
}

// boothImageFor names the image a booth with these settings builds FROM, by the
// rule a booth run uses (ensure_docker_image.go): <repo>:<variant>-<version>.
// settings holds the config.toml values that bear on it — variant, version,
// engine, image, dind, egress — and an empty one falls back to its CB_*
// variable, as a run does. lockVersion is the booth's pinned binary version,
// which is the image version when config.toml names none.
//
// ok is false when the image cannot be named with confidence: an `image`
// override (a booth that does not build FROM a catalog image), a malformed
// CB_PREBUILD_REPO, an unknown variant or engine.
func boothImageFor(settings map[string]string, lockVersion string) (boothImage, bool) {
	value := func(key, env string) string {
		if v := strings.TrimSpace(settings[key]); v != "" {
			return v
		}
		return strings.TrimSpace(os.Getenv(env))
	}

	if value("image", "CB_IMAGE") != "" {
		return boothImage{}, false
	}
	repo, err := boothfile.RepoFromEnv()
	if err != nil {
		return boothImage{}, false
	}
	if repo == "" {
		repo = boothfile.DefaultRepo
	}
	variant, ok := booth.CanonicalVariant(value("variant", "CB_VARIANT"))
	if !ok {
		return boothImage{}, false
	}
	version := value("version", "CB_VERSION")
	if version == "" {
		version = lockVersion
	}
	if version == "" {
		return boothImage{}, false
	}

	// An engine named outright is used as named; only an unset one is picked the
	// way a run picks it. Resolving a named podman or apple through
	// ResolveEngineValue would print its experimental-support warning here, in
	// the middle of configuring.
	engine := strings.ToLower(value("engine", "CB_ENGINE"))
	switch engine {
	case "docker", "podman", "apple":
	case "":
		resolve := appctx.ResolveEngineValue
		if settings["dind"] == "true" || settings["egress"] == "true" {
			resolve = appctx.ResolveEngineValueWithoutApple
		}
		if engine, err = resolve("", true); err != nil {
			return boothImage{}, false
		}
	default:
		return boothImage{}, false
	}

	return boothImage{Ref: fmt.Sprintf("%s:%s-%s", repo, variant, version), Engine: engine}, true
}

// readImageLabel reads one label off a local image; "" when the image is not
// on this machine, has no such label, or the engine cannot be asked. A var so
// tests can stand in for the engine.
var readImageLabel = func(engine, ref, label string) string {
	out, err := docker.DockerOutput(docker.DockerFlags{Engine: engine, Silent: true}, "image", ilist.NewList(
		ilist.NewList("inspect"),
		ilist.NewList("--format", `{{index .Config.Labels "`+label+`"}}`),
		ilist.NewList(ref),
	))
	value := strings.TrimSpace(out)
	if err != nil || value == "<no value>" {
		return ""
	}
	return value
}

// imageAptSnapshot is the snapshot image was built at, or "" when it is not known.
// A label that is not a snapshot id counts as not known.
func imageAptSnapshot(image boothImage) string {
	value := readImageLabel(image.Engine, image.Ref, imageSnapshotLabel)
	if id, err := aptsnapshot.Parse(value); err != nil || id != value || id == "" {
		return ""
	}
	return value
}

// imageSnapshotLookup returns a cached imageAptSnapshot keyed by settings — for
// the TUI, which asks on every redraw of the Apt Snapshot field, while the
// variant (and so the image) can change under it.
func imageSnapshotLookup(lockVersion string) func(settings map[string]string) (ref, snapshot string) {
	var mu sync.Mutex
	cache := map[boothImage]string{}
	return func(settings map[string]string) (string, string) {
		image, ok := boothImageFor(settings, lockVersion)
		if !ok {
			return "", ""
		}
		mu.Lock()
		defer mu.Unlock()
		snapshot, seen := cache[image]
		if !seen {
			snapshot = imageAptSnapshot(image)
			cache[image] = snapshot
		}
		return image.Ref, snapshot
	}
}

// olderThanImageWarning is the warning for a booth frozen to chosen on an image
// built at imageSnap, or "" when there is nothing to warn about: no freeze, an
// unknown image snapshot, or one not newer than chosen.
func olderThanImageWarning(chosen, imageRef, imageSnap string) string {
	if chosen == "" || imageSnap == "" || chosen >= imageSnap {
		return ""
	}
	return fmt.Sprintf("Warning: apt snapshot %s is older than this booth's image (%s, built at %s).\n"+
		"  `install apt` can fail on a package needing an exact version of one the image already has newer.\n"+
		"  To use the image's: booth config --apt-snapshot %s", chosen, imageRef, imageSnap, imageSnap)
}

// configImageSettings pulls the image-relevant settings out of a generated config.
func configImageSettings(cfg *output.ConfigToml) map[string]string {
	settings := map[string]string{}
	if cfg == nil {
		return settings
	}
	settings["variant"] = cfg.Variant
	if cfg.Dind {
		settings["dind"] = "true"
	}
	for _, key := range []string{"version", "engine", "image", "egress"} {
		if v, ok := cfg.Overrides[key]; ok {
			settings[key] = fmt.Sprint(v)
		}
	}
	return settings
}

// generatedAptSnapshot is the id a generated Boothfile freezes apt to; "" for none.
func generatedAptSnapshot(out *output.BoothOutput) string {
	if out == nil || out.Boothfile == nil {
		return ""
	}
	for _, line := range strings.Split(out.Boothfile.Content, "\n") {
		if rest, found := strings.CutPrefix(strings.TrimSpace(line), "env APT_SNAPSHOT="); found {
			return strings.TrimSpace(rest)
		}
	}
	return ""
}

// warnAptSnapshotOlderThanImage prints olderThanImageWarning for what this run
// generated. It never blocks: the image on this machine may not be the one the
// booth ends up built on, and an older snapshot is not always a failure.
func warnAptSnapshotOlderThanImage(w io.Writer, out *output.BoothOutput, targetPath, cliVersion string) {
	chosen := generatedAptSnapshot(out)
	if chosen == "" {
		return
	}
	image, ok := boothImageFor(configImageSettings(out.Config), readLockFileVersion(targetPath, cliVersion))
	if !ok {
		return
	}
	if warning := olderThanImageWarning(chosen, image.Ref, imageAptSnapshot(image)); warning != "" {
		fmt.Fprintln(w, warning)
	}
}
