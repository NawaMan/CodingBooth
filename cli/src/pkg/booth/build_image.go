// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"regexp"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/docker"
)

// AssembleImageName constructs a full image reference from registry, name, and tag.
// If registry is empty, returns "name:tag".
// If registry is set, returns "registry/name:tag".
func AssembleImageName(registry, name, tag string) string {
	if registry == "" {
		return name + ":" + tag
	}
	return strings.TrimRight(registry, "/") + "/" + name + ":" + tag
}

var (
	repoNameInvalidChar = regexp.MustCompile(`[^a-z0-9._-]`)
	repoNameSeparators  = regexp.MustCompile(`[._-]+`)
)

// SanitizeRepoName turns a name derived from the project (its folder or its configured
// booth name) into a valid Docker repository path component: lowercase, and made only of
// [a-z0-9] runs joined by one of ".", "_", "__" or "-+". A folder like "NPQAA238" or
// "My App" would otherwise give a reference Docker refuses with "repository name must be
// lowercase" before building anything. Names that are already valid come back unchanged.
// Only defaulted names go through this; an explicit --name is used as typed.
func SanitizeRepoName(name string) string {
	s := repoNameInvalidChar.ReplaceAllString(strings.ToLower(name), "-")
	s = repoNameSeparators.ReplaceAllStringFunc(s, func(sep string) string {
		switch {
		case sep == "." || sep == "_" || sep == "__" || strings.Trim(sep, "-") == "":
			return sep
		default:
			return "-"
		}
	})
	s = strings.Trim(s, "._-")
	if s == "" {
		return "booth"
	}
	return s
}

// ExtractRegistryHost extracts the hostname from a registry string.
// For example, "ghcr.io/myteam" returns "ghcr.io".
// This is used to suggest the correct login command on auth failures.
func ExtractRegistryHost(registry string) string {
	parts := strings.SplitN(registry, "/", 2)
	return parts[0]
}

// RegistryLoginCommand is the command that logs the engine in to host:
// `docker login` / `podman login`, and `container registry login` on Apple
// container, which has no top-level login.
func RegistryLoginCommand(engine, host string) string {
	if engine == docker.EngineApple {
		return "container registry login " + host
	}
	return docker.EngineBinary(engine) + " login " + host
}
