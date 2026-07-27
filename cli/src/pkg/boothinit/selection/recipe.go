// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ProjectRecipesDir returns <projectRoot>/.booth/recipes.
func ProjectRecipesDir(projectRoot string) string {
	if projectRoot == "" {
		projectRoot = "."
	}
	return filepath.Join(projectRoot, ".booth", "recipes")
}

// isPathShaped reports whether ref should be treated as a filesystem path or URL
// rather than a bare project recipe name.
//
// Path-shaped:
//   - absolute Unix path (/…)
//   - relative path starting with . (./…, ../…)
//   - home path (~ or ~/…)
//   - Windows drive path (C:\…, D:/…)
//   - URL (contains ://)
func isPathShaped(ref string) bool {
	if ref == "" {
		return false
	}
	if strings.Contains(ref, "://") {
		return true
	}
	if strings.HasPrefix(ref, "/") || strings.HasPrefix(ref, ".") || strings.HasPrefix(ref, "~") {
		return true
	}
	// Windows absolute: "C:\" or "C:/"
	if len(ref) >= 3 {
		drive := ref[0]
		if (drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z') {
			if ref[1] == ':' && (ref[2] == '/' || ref[2] == '\\') {
				return true
			}
		}
	}
	return false
}

// expandHome expands a leading ~ or ~/ to the current user's home directory.
// ~otheruser is not supported and is left unchanged (will fail on open).
func expandHome(path string) (string, error) {
	if path == "~" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("expanding ~: %w", err)
		}
		return home, nil
	}
	if strings.HasPrefix(path, "~/") || strings.HasPrefix(path, `~\`) {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", fmt.Errorf("expanding ~: %w", err)
		}
		return filepath.Join(home, path[2:]), nil
	}
	return path, nil
}

// normalizeRecipeURL ensures a URL has a scheme. Bare host/path gets https://.
func normalizeRecipeURL(u string) string {
	u = strings.TrimSpace(u)
	if u == "" {
		return u
	}
	if strings.Contains(u, "://") {
		return u
	}
	return "https://" + u
}

// ensureRecipeSuffix appends .recipe when the name has no extension.
func ensureRecipeSuffix(name string) string {
	if name == "" {
		return name
	}
	base := filepath.Base(name)
	if strings.Contains(base, ".") {
		return name
	}
	return name + ".recipe"
}

// resolveRecipePath maps a bare recipe name to <project>/.booth/recipes/<name>.recipe.
func resolveRecipePath(name, projectRoot string) string {
	return filepath.Join(ProjectRecipesDir(projectRoot), ensureRecipeSuffix(name))
}

// readRecipeRef resolves the part after a single @ to recipe file content.
func readRecipeRef(ref, projectRoot string) (string, error) {
	ref = strings.TrimSpace(ref)
	if ref == "" {
		return "", fmt.Errorf("empty recipe reference after @")
	}

	// URL form on a single @: @https://example.com/a.recipe
	if strings.Contains(ref, "://") {
		return fetchURL(ref)
	}

	if isPathShaped(ref) {
		path, err := expandHome(ref)
		if err != nil {
			return "", err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return "", fmt.Errorf("reading selection file %q: %w", path, err)
		}
		return string(data), nil
	}

	// Bare name → project .booth/recipes/
	path := resolveRecipePath(ref, projectRoot)
	data, err := os.ReadFile(path)
	if err != nil {
		return "", fmt.Errorf("recipe %q not found at %s", ref, path)
	}
	return string(data), nil
}
