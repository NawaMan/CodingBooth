// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package appctx

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/BurntSushi/toml"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// ResolveEngineValue normalizes and validates a raw "engine" setting
// ("" / "docker" / "podman" / "apple", case-insensitive) into a concrete
// engine name. "apple" is Apple's container runtime; its binary is
// `container` (see docker.EngineBinary).
//
// Empty means the caller never explicitly chose an engine (not via flag, env,
// or config file); see defaultEngine for the order it is picked in. An
// explicit "podman" always prints an unconditional experimental-support
// warning (not gated by quiet — this is a "know your risks" notice, not
// routine chatter). An explicit "apple" does the same.
func ResolveEngineValue(raw string, quiet bool) (string, error) {
	return resolveEngineValue(raw, quiet, true)
}

// ResolveEngineValueWithoutApple is ResolveEngineValue for a run that needs a
// sidecar (--dind, --egress), which Apple container cannot start: an unset
// engine skips apple and picks docker, then podman. An explicit "apple" is
// still returned, for the caller to refuse.
func ResolveEngineValueWithoutApple(raw string, quiet bool) (string, error) {
	return resolveEngineValue(raw, quiet, false)
}

func resolveEngineValue(raw string, quiet, appleOK bool) (string, error) {
	engine := strings.ToLower(strings.TrimSpace(raw))
	switch engine {
	case "":
		return defaultEngine(quiet, appleOK), nil
	case "docker":
		return "docker", nil
	case "podman":
		fmt.Fprintln(os.Stderr, "Warning: --engine podman is experimental and may not have full Docker feature parity yet. See docs/PODMAN_SUPPORT.md.")
		return "podman", nil
	case "apple":
		fmt.Fprintln(os.Stderr, "Warning: --engine apple (Apple container) is experimental and may not have full Docker feature parity yet. See docs/CONTAINER_SUPPORT.md.")
		return "apple", nil
	default:
		return "", fmt.Errorf("invalid engine %q (supported: docker, podman, apple)", raw)
	}
}

// defaultEngine picks the engine when none was chosen, in this order:
//
//  1. "apple" when `container` is on PATH and its service is running (and
//     appleOK). An installed but stopped Apple container is passed over, so
//     a Mac that also has Docker keeps working until `container system start`.
//  2. "docker" when it is on PATH.
//  3. "podman" when it is on PATH.
//  4. "apple" when `container` is the only engine installed, so its own error
//     (service not started) is the one shown.
//  5. "docker", so the exec error explains that nothing is installed.
//
// Picking anything but docker prints a one-line notice naming the engine and
// how to force Docker, suppressed when quiet is true (matching the DinD/egress
// sidecar notices elsewhere).
func defaultEngine(quiet, appleOK bool) string {
	notice := func(msg string) {
		if !quiet {
			fmt.Fprintln(os.Stderr, msg)
		}
	}
	hasApple := appleOK && onPath(docker.EngineBinary(docker.EngineApple))
	if hasApple && docker.AppleServiceRunning() {
		notice("ℹ️  Using Apple container (experimental; --engine docker to force Docker). See docs/CONTAINER_SUPPORT.md.")
		return docker.EngineApple
	}
	if onPath("docker") {
		return "docker"
	}
	if onPath("podman") {
		notice("⚠️  docker not found — using podman instead (experimental; --engine docker to force)")
		return "podman"
	}
	if hasApple {
		notice("ℹ️  Using Apple container (experimental), the only engine installed. See docs/CONTAINER_SUPPORT.md.")
		return docker.EngineApple
	}
	return "docker"
}

// ResolveEngineForPath resolves the container engine for a command that does
// not build a full AppContext (e.g. booth stop/start/restart/rm/prune/list,
// home-volume commands). It follows the same config-file-over-env-var
// precedence as the full AppConfig pipeline: engine= in
// <codeDir>/.booth/config.toml (skipped when codeDir is ""), then CB_ENGINE,
// then the default order in defaultEngine.
//
// Unlike the full pipeline, an invalid value here never aborts the command
// (a typo in config.toml shouldn't block `booth stop`) — it just falls back
// to "docker" and lets the resulting engine call surface the real problem.
func ResolveEngineForPath(codeDir string, quiet bool) string {
	engine, err := ResolveEngineValue(rawEngineForPath(codeDir), quiet)
	if err != nil {
		return "docker"
	}
	return engine
}

// ResolveEnginesForPath is ResolveEngineForPath for commands that only look
// booths up (list, stop, restart, remove, prune, message, expose list). When the
// engine was chosen explicitly (config file or CB_ENGINE) it returns just that
// one. When nothing was chosen and more than one engine is installed it returns
// every installed one — apple (Apple container, binary `container`), docker and
// podman, in the order defaultEngine prefers them — so a booth is found
// whichever engine started it. Otherwise it is the single engine
// ResolveEngineForPath would pick.
func ResolveEnginesForPath(codeDir string, quiet bool) []string {
	if strings.TrimSpace(rawEngineForPath(codeDir)) == "" {
		var installed []string
		for _, engine := range []string{docker.EngineApple, "docker", "podman"} {
			if onPath(docker.EngineBinary(engine)) {
				installed = append(installed, engine)
			}
		}
		if len(installed) > 1 {
			return installed
		}
	}
	return []string{ResolveEngineForPath(codeDir, quiet)}
}

// rawEngineForPath is the engine setting exactly as written: engine= in
// <codeDir>/.booth/config.toml (skipped when codeDir is ""), then CB_ENGINE.
func rawEngineForPath(codeDir string) string {
	raw := ""
	if codeDir != "" {
		raw = readEngineFromConfigFile(filepath.Join(codeDir, ".booth", "config.toml"))
	}
	if raw == "" {
		raw = os.Getenv("CB_ENGINE")
	}
	return raw
}

func onPath(binary string) bool {
	_, err := exec.LookPath(binary)
	return err == nil
}

func readEngineFromConfigFile(path string) string {
	if _, err := os.Stat(path); err != nil {
		return ""
	}
	var cfg struct {
		Engine string `toml:"engine"`
	}
	if _, err := toml.DecodeFile(path, &cfg); err != nil {
		return ""
	}
	return cfg.Engine
}
