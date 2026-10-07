// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func recipeRegistry() *tmpl.TemplateRegistry {
	python := &tmpl.Template{
		Name:        "python",
		DisplayName: "Python",
		Primary:     true,
		Params:      map[string]tmpl.Param{"PYTHON_VERSION": {Default: "3.13"}},
		ParamOrder:  []string{"PYTHON_VERSION"},
	}
	htop := &tmpl.Template{Name: "htop", DisplayName: "htop", Primary: true}
	return &tmpl.TemplateRegistry{
		ByName: map[string]*tmpl.Template{"python": python, "htop": htop},
		Categories: []*tmpl.Category{{
			Name: "languages", DisplayName: "Languages", Order: 1,
			Templates: []*tmpl.Template{python, htop},
		}},
	}
}

func TestRecipesTab_ApplyKeepsAtName(t *testing.T) {
	m := newModel(recipeRegistry(), &PreSelection{
		Recipes: []selection.ProjectRecipe{{
			Name: "desk",
			Body: "# comment\npython:3.12\n",
		}},
	})
	require.Equal(t, 1, m.recipesTab, "Recipes sits beside Config")
	assert.Equal(t, "Recipes", m.tabNames[1])
	assert.NotEqual(t, m.recipesTab, m.activeTab, "the TUI still opens on a category")

	m.applyRecipe("desk")
	assert.True(t, m.selected["python"])
	assert.Equal(t, "3.12", m.paramValues["python:PYTHON_VERSION"])
	assert.Equal(t, "@desk", m.buildSelectDSL())
	assert.True(t, m.recipeIsMarked("desk"))

	m.selected["htop"] = true
	assert.Equal(t, "@desk/htop", m.buildSelectDSL())

	m.paramValues["python:PYTHON_VERSION"] = "3.11"
	assert.Equal(t, "python:3.11/htop", m.buildSelectDSL())
	assert.False(t, m.recipeIsMarked("desk"))
}

func TestRecipesTab_OpenMarksRecipeFromHeader(t *testing.T) {
	m := newModel(recipeRegistry(), &PreSelection{
		Recipes: []selection.ProjectRecipe{{
			Name: "desk",
			Body: "python:3.12\n",
		}},
		AppliedRecipes:    []string{"desk"},
		SelectedTemplates: map[string]bool{"python": true},
		ParamValues:       map[string]string{"python:PYTHON_VERSION": "3.12"},
	})
	assert.True(t, m.recipeIsMarked("desk"))
	assert.Equal(t, "@desk", m.buildSelectDSL())
}

func TestRecipesTab_UnknownTemplateDoesNotApply(t *testing.T) {
	m := newModel(recipeRegistry(), &PreSelection{
		Recipes: []selection.ProjectRecipe{{
			Name: "desk",
			Body: "python\nmissing\n",
		}},
	})
	m.applyRecipe("desk")
	assert.False(t, m.selected["python"])
	assert.False(t, m.recipeIsMarked("desk"))
	assert.Contains(t, m.notification, "unknown template")
	assert.Equal(t, "", m.buildSelectDSL())
}

func TestRecipesTab_IncludeIsRefused(t *testing.T) {
	m := newModel(recipeRegistry(), &PreSelection{
		Recipes: []selection.ProjectRecipe{{
			Name: "desk",
			Body: "@base\npython\n",
		}},
	})
	m.applyRecipe("desk")
	assert.False(t, m.selected["python"])
	assert.Contains(t, m.notification, "cannot include")
}
