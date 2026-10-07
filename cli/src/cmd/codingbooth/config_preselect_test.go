// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// The TUI used to parse @/tmp/lamp-desk.recipe as selection text. "/" split it
// into "@", "tmp", and "lamp-desk.recipe", so lamp-init stayed unchecked and
// the footer said "@ is not a file in .booth/recipes". --no-tui already opened
// the file first.

func preselectRegistry() *tmpl.TemplateRegistry {
	lamp := &tmpl.Template{Name: "lamp-init", DisplayName: "LAMP demo", Primary: true}
	htop := &tmpl.Template{Name: "htop", DisplayName: "htop", Primary: true}
	return &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{"lamp-init": lamp, "htop": htop},
	}
}

func TestBuildPreSelection_PathRecipeChecksItsTemplates(t *testing.T) {
	filePath := filepath.Join(t.TempDir(), "lamp-desk.recipe")
	require.NoError(t, os.WriteFile(filePath, []byte("# lamp desk — this line is a comment\nlamp-init\n"), 0o644))

	pre := buildPreSelection(preselectRegistry(), initFlags{selectDSLs: []string{"@" + filePath}}, nil, nil, t.TempDir())

	assert.True(t, pre.SelectedTemplates["lamp-init"])
	assert.Empty(t, pre.AppliedRecipes)
	assert.Empty(t, pre.RecipeNote)
}

func TestBuildPreSelection_PathRecipeWithAtLineSelectsNothing(t *testing.T) {
	filePath := filepath.Join(t.TempDir(), "nested.recipe")
	require.NoError(t, os.WriteFile(filePath, []byte("@other\nlamp-init\n"), 0o644))

	pre := buildPreSelection(preselectRegistry(), initFlags{selectDSLs: []string{"@" + filePath}}, nil, nil, t.TempDir())

	assert.Empty(t, pre.SelectedTemplates)
	assert.Contains(t, pre.RecipeNote, "cannot include")
	assert.NotContains(t, pre.RecipeNote, "is not a file in .booth/recipes")
}

func TestBuildPreSelection_MissingPathRecipeNamesTheFile(t *testing.T) {
	filePath := filepath.Join(t.TempDir(), "missing.recipe")

	pre := buildPreSelection(preselectRegistry(), initFlags{selectDSLs: []string{"@" + filePath}}, nil, nil, t.TempDir())

	assert.Empty(t, pre.SelectedTemplates)
	assert.Contains(t, pre.RecipeNote, "reading selection file")
	assert.NotContains(t, pre.RecipeNote, "is not a file in .booth/recipes")
}

func TestBuildPreSelection_BareRecipeStaysMarked(t *testing.T) {
	recipes := []selection.ProjectRecipe{{Name: "lamp", Body: "# comment\nlamp-init\n"}}

	pre := buildPreSelection(preselectRegistry(), initFlags{selectDSLs: []string{"@lamp/htop"}}, nil, recipes, t.TempDir())

	assert.True(t, pre.SelectedTemplates["lamp-init"])
	assert.True(t, pre.SelectedTemplates["htop"])
	assert.Equal(t, []string{"lamp"}, pre.AppliedRecipes)
	assert.Empty(t, pre.RecipeNote)
}
