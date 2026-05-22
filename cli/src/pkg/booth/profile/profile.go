// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package profile implements BOOTH_PROFILES — named overlays of
// config.toml and .env on top of the common base under .booth/.
//
// Layout (flat, tagged):
//
//	.booth/config.toml          # common base (always applied)
//	.booth/.env                 # common base (always applied)
//	.booth/<name>--config.toml  # profile overlay (prefix tag)
//	.booth/.env--<name>         # profile overlay (suffix tag preserves dotfile)
//
// Selection (highest first):
//
//	--profile <list>     (repeatable; comma-separated values inside each value)
//	BOOTH_PROFILES=<list> env var — ignored if --profile is given
//	implicit "default"   (only if .booth/default--config.toml or .env--default exists)
//	none                 (only the common base loads)
package profile

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

const (
	// ReservedCommon is the name reserved for the implicit common base.
	// Users cannot select it via --profile (it is always applied).
	ReservedCommon = "common"

	// ImplicitDefault is the profile name applied automatically when no
	// explicit selection is made AND a profile by this name exists.
	ImplicitDefault = "default"

	configSuffix = "--config.toml"
	envPrefix    = ".env--"
)

// Files identifies the on-disk files for a single profile. Either or
// both may be empty if the corresponding file is absent.
type Files struct {
	ConfigPath string
	EnvPath    string
}

// Discover scans .booth/ under codeDir and returns the available profiles.
// Returns an empty map (not nil) if .booth/ is missing or contains no
// profile files.
func Discover(codeDir string) (map[string]Files, error) {
	boothDir := filepath.Join(codeDir, ".booth")
	info, err := os.Stat(boothDir)
	if err != nil {
		if os.IsNotExist(err) {
			return map[string]Files{}, nil
		}
		return nil, err
	}
	if !info.IsDir() {
		return map[string]Files{}, nil
	}

	entries, err := os.ReadDir(boothDir)
	if err != nil {
		return nil, err
	}

	out := map[string]Files{}
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		name := e.Name()

		switch {
		case strings.HasSuffix(name, configSuffix):
			profile := strings.TrimSuffix(name, configSuffix)
			if profile == "" || profile == ReservedCommon {
				continue
			}
			f := out[profile]
			f.ConfigPath = filepath.Join(boothDir, name)
			out[profile] = f

		case strings.HasPrefix(name, envPrefix):
			profile := strings.TrimPrefix(name, envPrefix)
			if profile == "" || profile == ReservedCommon {
				continue
			}
			f := out[profile]
			f.EnvPath = filepath.Join(boothDir, name)
			out[profile] = f
		}
	}
	return out, nil
}

// Resolve produces the ordered list of profile names to apply for this run.
//
// Precedence (highest first):
//  1. --profile from args (repeatable, comma-separated)
//  2. BOOTH_PROFILES from envValue (comma-separated) — ignored if --profile is given
//  3. Implicit "default" — only if available contains it
//  4. Empty list
//
// Validation: "common" is rejected, empty names are rejected, duplicates
// are rejected, names not in available are rejected.
func Resolve(args ilist.List[string], envValue string, available map[string]Files) ([]string, error) {
	flagNames, flagPresent, err := parseFlag(args)
	if err != nil {
		return nil, err
	}

	switch {
	case flagPresent:
		return validate(flagNames, "--profile", available)

	case strings.TrimSpace(envValue) != "":
		envNames := splitList(envValue)
		return validate(envNames, "BOOTH_PROFILES", available)

	default:
		if _, ok := available[ImplicitDefault]; ok {
			return []string{ImplicitDefault}, nil
		}
		return nil, nil
	}
}

// HasProfileFlag reports whether --profile appears anywhere in args.
// Used by mutual-exclusion checks before full parsing.
func HasProfileFlag(args ilist.List[string]) bool {
	for i := 0; i < args.Length(); i++ {
		if args.At(i) == "--profile" {
			return true
		}
	}
	return false
}

func parseFlag(args ilist.List[string]) ([]string, bool, error) {
	var collected []string
	present := false
	for i := 0; i < args.Length(); {
		if args.At(i) != "--profile" {
			i++
			continue
		}
		present = true
		if i+1 >= args.Length() {
			return nil, false, fmt.Errorf("--profile requires a value")
		}
		collected = append(collected, splitList(args.At(i+1))...)
		i += 2
	}
	return collected, present, nil
}

func splitList(s string) []string {
	parts := strings.Split(s, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		out = append(out, strings.TrimSpace(p))
	}
	return out
}

func validate(names []string, source string, available map[string]Files) ([]string, error) {
	if len(names) == 0 {
		return nil, fmt.Errorf("%s: at least one profile required", source)
	}
	seen := map[string]bool{}
	for _, n := range names {
		if n == "" {
			return nil, fmt.Errorf("%s: empty profile name in list", source)
		}
		if n == ReservedCommon {
			return nil, fmt.Errorf("%s: %q is reserved (the common base is always applied)", source, n)
		}
		if seen[n] {
			return nil, fmt.Errorf("%s: duplicate profile %q", source, n)
		}
		seen[n] = true
		if _, ok := available[n]; !ok {
			return nil, fmt.Errorf("%s: profile %q not found under .booth/ (looked for %s--config.toml and .env--%s)", source, n, n, n)
		}
	}
	return names, nil
}
