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
)

// ResolveEngineValue normalizes and validates a raw "engine" setting
// ("" / "docker" / "podman", case-insensitive) into a concrete binary name.
//
// Empty means the caller never explicitly chose an engine (not via flag, env,
// or config file). In that case: use "docker" if it's on PATH; otherwise fall
// back to "podman" if that's on PATH instead, printing a one-line notice
// (suppressed when quiet is true, matching the DinD/egress sidecar notices
// elsewhere); otherwise keep "docker" and let the real exec error explain
// what's missing. An explicit "podman" always prints an unconditional
// experimental-support warning (not gated by quiet — this is a "know your
// risks" notice, not routine chatter).
func ResolveEngineValue(raw string, quiet bool) (string, error) {
	engine := strings.ToLower(strings.TrimSpace(raw))
	switch engine {
	case "":
		if _, err := exec.LookPath("docker"); err == nil {
			return "docker", nil
		}
		if _, err := exec.LookPath("podman"); err == nil {
			if !quiet {
				fmt.Fprintln(os.Stderr, "⚠️  docker not found — using podman instead (experimental; --engine docker to force)")
			}
			return "podman", nil
		}
		return "docker", nil
	case "docker":
		return "docker", nil
	case "podman":
		fmt.Fprintln(os.Stderr, "Warning: --engine podman is experimental and may not have full Docker feature parity yet. See docs/PODMAN_SUPPORT.md.")
		return "podman", nil
	default:
		return "", fmt.Errorf("invalid engine %q (supported: docker, podman)", raw)
	}
}

// ResolveEngineForPath resolves the container engine for a command that does
// not build a full AppContext (e.g. booth stop/start/restart/rm/prune/list,
// home-volume commands). It follows the same config-file-over-env-var
// precedence as the full AppConfig pipeline: engine= in
// <codeDir>/.booth/config.toml (skipped when codeDir is ""), then CB_ENGINE,
// then the docker->podman PATH fallback in ResolveEngineValue.
//
// Unlike the full pipeline, an invalid value here never aborts the command
// (a typo in config.toml shouldn't block `booth stop`) — it just falls back
// to "docker" and lets the resulting engine call surface the real problem.
func ResolveEngineForPath(codeDir string, quiet bool) string {
	raw := ""
	if codeDir != "" {
		raw = readEngineFromConfigFile(filepath.Join(codeDir, ".booth", "config.toml"))
	}
	if raw == "" {
		raw = os.Getenv("CB_ENGINE")
	}
	engine, err := ResolveEngineValue(raw, quiet)
	if err != nil {
		return "docker"
	}
	return engine
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
