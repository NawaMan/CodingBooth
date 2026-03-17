// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import "strings"

// AssembleImageName constructs a full image reference from registry, name, and tag.
// If registry is empty, returns "name:tag".
// If registry is set, returns "registry/name:tag".
func AssembleImageName(registry, name, tag string) string {
	if registry == "" {
		return name + ":" + tag
	}
	return strings.TrimRight(registry, "/") + "/" + name + ":" + tag
}

// ExtractRegistryHost extracts the hostname from a registry string.
// For example, "ghcr.io/myteam" returns "ghcr.io".
// This is used to suggest the correct docker login command on auth failures.
func ExtractRegistryHost(registry string) string {
	parts := strings.SplitN(registry, "/", 2)
	return parts[0]
}
