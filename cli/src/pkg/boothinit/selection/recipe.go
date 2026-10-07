// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package selection

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
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

// ProjectRecipe is one file in <project>/.booth/recipes.
// Name is what follows @ on a --select flag (desk.recipe is "desk").
type ProjectRecipe struct {
	Name string
	Body string
}

// LoadProjectRecipes reads the top-level *.recipe files in the project recipes
// directory. A missing directory is an empty list. Subdirectories stay
// addressable as @team/api on the command line and are not listed here.
func LoadProjectRecipes(projectRoot string) ([]ProjectRecipe, error) {
	dir := ProjectRecipesDir(projectRoot)
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, fmt.Errorf("reading recipes directory: %w", err)
	}

	var out []ProjectRecipe
	for _, entry := range entries {
		name := entry.Name()
		if entry.IsDir() || strings.HasPrefix(name, ".") || !strings.HasSuffix(name, ".recipe") {
			continue
		}
		data, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return nil, fmt.Errorf("reading recipe %q: %w", name, err)
		}
		out = append(out, ProjectRecipe{Name: recipeSelectName(name), Body: string(data)})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out, nil
}

// recipeSelectName is the @ argument that resolveRecipePath maps back to filename.
// desk.recipe → desk. A stem that already contains a dot keeps the filename,
// because a dot suppresses the .recipe suffix.
func recipeSelectName(filename string) string {
	if strings.HasSuffix(filename, ".recipe") {
		stem := strings.TrimSuffix(filename, ".recipe")
		if stem != "" && !strings.Contains(stem, ".") {
			return stem
		}
	}
	return filename
}

// FindProjectRecipe looks up ref as written after @. @desk and @desk.recipe
// both find the recipe named desk.
func FindProjectRecipe(recipes []ProjectRecipe, ref string) (ProjectRecipe, bool) {
	ref = strings.TrimSpace(ref)
	for _, recipe := range recipes {
		if recipe.Name == ref || recipe.Name+".recipe" == ref {
			return recipe, true
		}
	}
	return ProjectRecipe{}, false
}

// resolveRecipePath maps a bare recipe name to <project>/.booth/recipes/<name>.recipe.
func resolveRecipePath(name, projectRoot string) string {
	return filepath.Join(ProjectRecipesDir(projectRoot), ensureRecipeSuffix(name))
}

// OpenExternalSelect reads a path or URL recipe. A bare @name and plain DSL
// return external=false so the caller can keep @name for the Recipes tab.
// @/tmp/file, @./file, @~/file, and @@url are external. @desk/htop is not:
// the slash there separates a project recipe from another template.
func OpenExternalSelect(value, projectRoot string) (body string, external bool, err error) {
	value = strings.TrimSpace(value)
	if strings.HasPrefix(value, "@@") {
		body, err = ReadSelectInputWithProject(value, projectRoot)
		return body, true, err
	}
	if strings.HasPrefix(value, "@") {
		ref := strings.TrimSpace(strings.TrimPrefix(value, "@"))
		if isPathShaped(ref) {
			body, err = readRecipeRef(ref, projectRoot)
			return body, true, err
		}
	}
	return "", false, nil
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
