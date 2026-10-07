// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/nawaman/codingbooth/src/pkg/boothinit/selection"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// isRecipesTab reports whether the Recipes tab is showing.
func (m model) isRecipesTab() bool {
	return m.recipesTab >= 0 && m.activeTab == m.recipesTab
}

func (m model) firstCategoryTab() int {
	for i := range m.tabNames {
		if i == 0 || i == m.recipesTab {
			continue
		}
		return i
	}
	return -1
}

func (m model) recipeByName(name string) (selection.ProjectRecipe, bool) {
	return selection.FindProjectRecipe(m.recipes, name)
}

// visibleRecipes is the Recipes tab list, narrowed by the search query.
func (m model) visibleRecipes() []selection.ProjectRecipe {
	if m.searchQuery == "" {
		return m.recipes
	}
	query := strings.ToLower(m.searchQuery)
	var out []selection.ProjectRecipe
	for _, recipe := range m.recipes {
		if strings.Contains(strings.ToLower(recipe.Name), query) || strings.Contains(strings.ToLower(recipe.Body), query) {
			out = append(out, recipe)
		}
	}
	return out
}

// applyRecipe merges one recipe into the template checkboxes and marks it so a
// later save can keep @name. A recipe that names an unknown template, or that
// tries to include another recipe, is left unmarked and nothing is selected
// from it.
func (m *model) applyRecipe(name string) {
	recipe, ok := m.recipeByName(name)
	if !ok {
		m.notification = fmt.Sprintf("No recipe %q", name)
		return
	}
	parsed, err := selection.ParseSelectDSL(recipe.Body)
	if err != nil {
		m.notification = fmt.Sprintf("@%s: %v", name, err)
		return
	}
	if msg := recipeApplyError(parsed, m.registry); msg != "" {
		m.notification = fmt.Sprintf("@%s: %s", name, msg)
		return
	}
	for _, item := range parsed.Items {
		m.applyRecipeItem(item)
	}
	if !containsString(m.applied, name) {
		m.applied = append(m.applied, name)
	}
	m.notification = "Applied @" + name
}

// recipeApplyError is empty when every item can be selected.
func recipeApplyError(parsed *selection.ParsedSelection, registry *tmpl.TemplateRegistry) string {
	if parsed == nil || len(parsed.Items) == 0 {
		return "recipe selects nothing"
	}
	for _, item := range parsed.Items {
		if strings.HasPrefix(item.Name, "@") {
			return "a recipe cannot include another recipe"
		}
		t, ok := registry.ByName[item.Name]
		if !ok {
			return fmt.Sprintf("unknown template %q", item.Name)
		}
		known := map[string]bool{}
		for _, ext := range t.Extensions {
			known[ext.Name] = true
		}
		for _, ext := range item.Extensions {
			if !known[ext.Name] {
				return fmt.Sprintf("unknown extension %q", ext.Name)
			}
		}
	}
	return ""
}

func (m *model) applyRecipeItem(item selection.ParsedItem) {
	t := m.registry.ByName[item.Name]
	if !m.selected[t.Name] {
		m.applySelectItem(treeItem{kind: kindTemplate, template: t})
	}
	m.setPositionalParams(t.Name, t, item.Params)

	excluded := map[string]bool{}
	for _, name := range item.Excludes {
		excluded[name] = true
	}
	explicit := map[string]selection.ParsedExtension{}
	for _, ext := range item.Extensions {
		explicit[ext.Name] = ext
	}
	for _, ext := range t.Extensions {
		key := t.Name + "/" + ext.Name
		if excluded[ext.Name] {
			delete(m.selected, key)
			m.clearParamValues(key, ext)
			continue
		}
		if _, ok := explicit[ext.Name]; ok || (ext.AutoSelect != nil && *ext.AutoSelect) {
			if !m.selected[key] {
				m.selected[key] = true
				m.initParamDefaults(key, ext)
			}
		}
		if spec, ok := explicit[ext.Name]; ok {
			m.setPositionalParams(key, ext, spec.Params)
		}
	}
}

// setPositionalParams writes a recipe's positional params over the defaults.
func (m *model) setPositionalParams(itemKey string, t *tmpl.Template, positional []string) {
	names := orderedParamNames(t)
	if len(names) == 0 || len(positional) == 0 {
		return
	}
	lastVariadic := t.Params[names[len(names)-1]].Variadic
	for i, name := range names {
		if i == len(names)-1 && lastVariadic {
			if i < len(positional) {
				m.paramValues[itemKey+":"+name] = selection.CanonicalizeVariadic(positional[i:])
			}
			return
		}
		if i < len(positional) && positional[i] != "" {
			m.paramValues[itemKey+":"+name] = positional[i]
		}
	}
}

// markedRecipes is the applied recipes whose templates still match the
// checkboxes, skipping one that would select a template an earlier recipe
// already covers. That is the list a save writes as @name.
func (m model) markedRecipes() []string {
	covered := map[string]bool{}
	var out []string
	for _, name := range m.applied {
		parsed, ok := m.matchingRecipe(name)
		if !ok {
			continue
		}
		overlap := false
		for _, item := range parsed.Items {
			if covered[item.Name] {
				overlap = true
				break
			}
		}
		if overlap {
			continue
		}
		for _, item := range parsed.Items {
			covered[item.Name] = true
		}
		out = append(out, name)
	}
	return out
}

func (m model) recipeIsMarked(name string) bool {
	for _, marked := range m.markedRecipes() {
		if marked == name {
			return true
		}
	}
	return false
}

// matchingRecipe parses name and reports whether the checkboxes still equal it.
func (m model) matchingRecipe(name string) (*selection.ParsedSelection, bool) {
	recipe, ok := m.recipeByName(name)
	if !ok {
		return nil, false
	}
	parsed, err := selection.ParseSelectDSL(recipe.Body)
	if err != nil || recipeApplyError(parsed, m.registry) != "" {
		return nil, false
	}
	for _, item := range parsed.Items {
		if !m.recipeItemMatches(item) {
			return nil, false
		}
	}
	return parsed, true
}

func (m model) recipeItemMatches(item selection.ParsedItem) bool {
	t, ok := m.registry.ByName[item.Name]
	if !ok || !m.selected[item.Name] {
		return false
	}
	if !m.paramsMatch(item.Name, t, item.Params) {
		return false
	}
	explicit := map[string]selection.ParsedExtension{}
	for _, ext := range item.Extensions {
		explicit[ext.Name] = ext
	}
	excluded := map[string]bool{}
	for _, name := range item.Excludes {
		excluded[name] = true
	}
	for _, ext := range t.Extensions {
		key := item.Name + "/" + ext.Name
		auto := ext.AutoSelect != nil && *ext.AutoSelect
		_, named := explicit[ext.Name]
		should := named || (auto && !excluded[ext.Name])
		if m.selected[key] != should {
			return false
		}
		if named {
			if !m.paramsMatch(key, ext, explicit[ext.Name].Params) {
				return false
			}
			continue
		}
		if should && !m.paramsMatch(key, ext, nil) {
			return false
		}
	}
	return true
}

// paramsMatch reports whether the live param values equal positional overlaid
// on the template defaults. An empty positional list means "all defaults".
func (m model) paramsMatch(itemKey string, t *tmpl.Template, positional []string) bool {
	names := orderedParamNames(t)
	if len(names) == 0 {
		return true
	}
	want := map[string]string{}
	for _, name := range names {
		want[name] = t.Params[name].Default
	}
	lastVariadic := t.Params[names[len(names)-1]].Variadic
	for i, name := range names {
		if i == len(names)-1 && lastVariadic {
			if i < len(positional) {
				want[name] = selection.CanonicalizeVariadic(positional[i:])
			}
			break
		}
		if i < len(positional) && positional[i] != "" {
			want[name] = positional[i]
		}
	}
	for _, name := range names {
		got, ok := m.paramValues[itemKey+":"+name]
		if !ok || got == "" {
			got = t.Params[name].Default
		}
		if got != want[name] {
			return false
		}
	}
	return true
}

// buildSelectDSL writes the selection a save records. Marked recipes stay as
// @name. Templates they do not cover are appended from the checkboxes.
func (m model) buildSelectDSL() string {
	checkbox := m.checkboxDSL()
	marked := m.markedRecipes()
	if len(marked) == 0 {
		return checkbox
	}
	parsed, err := selection.ParseSelectDSL(checkbox)
	if err != nil {
		return checkbox
	}
	covered := map[string]bool{}
	for _, name := range marked {
		body, _ := m.matchingRecipe(name)
		for _, item := range body.Items {
			covered[item.Name] = true
		}
	}
	parts := make([]string, 0, len(marked)+len(parsed.Items))
	for _, name := range marked {
		parts = append(parts, "@"+name)
	}
	for _, item := range parsed.Items {
		if covered[item.Name] {
			continue
		}
		parts = append(parts, selection.SerializeItem(item))
	}
	return strings.Join(parts, "/")
}

func (m model) handleRecipeKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	recipes := m.visibleRecipes()
	switch msg.String() {
	case "up":
		m.moveRecipeCursor(-1, len(recipes))
	case "down":
		m.moveRecipeCursor(1, len(recipes))
	case "pgup":
		m.moveRecipeCursor(-m.contentHeight(), len(recipes))
	case "pgdown":
		m.moveRecipeCursor(m.contentHeight(), len(recipes))
	case "home":
		m.setCursor(0)
	case "end":
		if len(recipes) > 0 {
			m.setCursor(len(recipes) - 1)
		}
	case " ", "enter":
		if cur := m.cursorPos(); cur >= 0 && cur < len(recipes) {
			m.applyRecipe(recipes[cur].Name)
		}
	}
	m.adjustRecipeScroll(len(recipes))
	return m, nil
}

func (m *model) moveRecipeCursor(delta, n int) {
	if n == 0 {
		return
	}
	cur := m.cursorPos() + delta
	if cur < 0 {
		cur = 0
	}
	if cur >= n {
		cur = n - 1
	}
	m.setCursor(cur)
}

func (m *model) adjustRecipeScroll(n int) {
	h := m.contentHeight()
	if h <= 0 || n == 0 {
		return
	}
	off := m.scrollOffset()
	cur := m.cursorPos()
	if cur < off {
		off = cur
	}
	if cur >= off+h {
		off = cur - h + 1
	}
	if off > n-h {
		off = n - h
	}
	if off < 0 {
		off = 0
	}
	m.setScrollOffset(off)
}

func (m model) clickRecipeLeft(line, x int) (tea.Model, tea.Cmd) {
	m.searchFocused = false
	recipes := m.visibleRecipes()
	idx := m.scrollOffset() + line
	if idx < 0 || idx >= len(recipes) {
		return m, nil
	}
	m.setCursor(idx)
	if x >= 0 && x <= 2 {
		m.applyRecipe(recipes[idx].Name)
	}
	m.adjustRecipeScroll(len(recipes))
	return m, nil
}

func (m *model) scrollRecipeBy(delta int) {
	recipes := m.visibleRecipes()
	h := m.contentHeight()
	if len(recipes) == 0 || h <= 0 {
		return
	}
	maxOff := len(recipes) - h
	if maxOff < 0 {
		maxOff = 0
	}
	off := m.scrollOffset() + delta
	if off < 0 {
		off = 0
	}
	if off > maxOff {
		off = maxOff
	}
	m.setScrollOffset(off)
	cur := m.cursorPos()
	if cur < off {
		cur = off
	}
	if cur > off+h-1 {
		cur = off + h - 1
	}
	if cur >= len(recipes) {
		cur = len(recipes) - 1
	}
	m.setCursor(cur)
}

func containsString(list []string, want string) bool {
	for _, item := range list {
		if item == want {
			return true
		}
	}
	return false
}
