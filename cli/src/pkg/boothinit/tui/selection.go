// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// toggleSelection handles space-bar toggling with auto-select and dependency
// cascading. The actual mutation is deferred to requestSelect/requestDeselect,
// which may pose a y/n confirmation first instead of applying immediately.
func (m *model) toggleSelection() {
	items := m.activeItems()
	cursor := m.cursorPos()
	if len(items) == 0 || cursor < 0 || cursor >= len(items) {
		return
	}
	item := items[cursor]

	if m.selected[item.key()] {
		m.requestDeselect(item)
	} else {
		m.requestSelect(item)
	}
}

// requiresAction identifies which half of a requires-driven confirmation is
// pending: pulling something in, or taking something out.
type requiresAction int

const (
	requiresActionSelect requiresAction = iota
	requiresActionDeselect
)

// requiresPrompt captures a requires-driven cascade waiting on a y/n answer:
// selecting item would pull in `names` (still-unselected requirements it
// needs), or deselecting item would orphan `names` (currently-selected
// dependents that need it). Declining leaves item — and everything in
// `names` — exactly as it was.
type requiresPrompt struct {
	action requiresAction
	item   treeItem
	names  []string
}

// requestSelect selects item immediately if it needs nothing this session
// doesn't already have selected. Otherwise it defers behind a y/n prompt
// naming what would be pulled in — declining leaves item unselected and
// nothing else changes.
func (m *model) requestSelect(item treeItem) {
	missing := m.pendingRequires(item)
	if len(missing) == 0 {
		m.applySelectItem(item)
		return
	}
	m.confirmRequires = &requiresPrompt{action: requiresActionSelect, item: item, names: missing}
	m.notification = m.requiresPromptMessage(m.confirmRequires)
}

// requestDeselect deselects item immediately if nothing currently selected
// depends on it. Otherwise it defers behind a y/n prompt naming what would
// be orphaned — declining leaves item, and everything depending on it,
// selected.
func (m *model) requestDeselect(item treeItem) {
	if item.kind == kindTemplate {
		deps := m.dependentsOf(item.template.Name)
		if len(deps) > 0 {
			m.confirmRequires = &requiresPrompt{action: requiresActionDeselect, item: item, names: deps}
			m.notification = m.requiresPromptMessage(m.confirmRequires)
			return
		}
	}
	m.applyDeselectItem(item)
}

// handleRequiresConfirm answers a pending requires prompt: y/Enter applies
// the deferred select/deselect (with its full normal cascade — auto-select
// extensions, arch warnings, the lot), n/Esc discards it and leaves the
// model untouched.
func (m model) handleRequiresConfirm(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	p := m.confirmRequires
	switch msg.String() {
	case "enter", "y", "Y":
		m.confirmRequires = nil
		if p.action == requiresActionSelect {
			m.applySelectItem(p.item)
		} else {
			m.applyDeselectItem(p.item)
		}
	case "esc", "n", "N":
		m.confirmRequires = nil
		m.notification = ""
	}
	return m, nil
}

// requiresPromptMessage builds the y/n question for a pending prompt, e.g.
// "kind requires dind — add it too? [y/n]" or, for a deselect with several
// dependents, "kind, docker-buildx require dind — deselect them too? [y/n]".
func (m *model) requiresPromptMessage(p *requiresPrompt) string {
	itemLabel := p.item.template.DisplayName
	if p.item.kind == kindExtension {
		itemLabel = p.item.extension.DisplayName
	}

	labels := make([]string, len(p.names))
	for i, n := range p.names {
		labels[i] = m.displayNameForKey(n)
	}
	list := strings.Join(labels, ", ")
	pronoun := "it"
	if len(p.names) > 1 {
		pronoun = "them"
	}

	if p.action == requiresActionSelect {
		return fmt.Sprintf("%s requires %s — add %s too? [y/n]", itemLabel, list, pronoun)
	}

	verb := "requires"
	if len(p.names) > 1 {
		verb = "require"
	}
	return fmt.Sprintf("%s %s %s — deselect %s too? [y/n]", list, verb, itemLabel, pronoun)
}

// applySelectItem actually selects item and cascades its requirements and
// auto-select extensions — the full mutation that used to live inline in
// toggleSelection, now shared by the no-confirmation-needed path and the
// "y" answer to a requires prompt.
func (m *model) applySelectItem(item treeItem) {
	key := item.key()
	var notifications []string
	m.selected[key] = true

	if item.kind == kindExtension {
		m.initParamDefaults(key, item.extension)
		// Auto-select parent template if not selected
		if !m.selected[item.template.Name] {
			m.selected[item.template.Name] = true
			m.initParamDefaults(item.template.Name, item.template)
			notifications = append(notifications, fmt.Sprintf("Auto-selected: %s", item.template.Name))
			m.selectDependencies(item.template, &notifications)
			m.autoSelectExtensions(item.template, &notifications)
		}
		// Handle extension's own dependencies
		for _, req := range item.extension.Requires {
			if !m.selected[req] {
				m.selectTemplateByName(req, &notifications)
			}
		}
	} else {
		// Template selected
		m.initParamDefaults(key, item.template)
		// Lead with the bad news: this one cannot install on this machine's
		// architecture, so say so at the moment of choosing rather than
		// leaving it to be discovered in a booth that is missing the tool.
		if item.template.UnsupportedOn(m.hostArch) {
			notifications = append(notifications,
				fmt.Sprintf("⚠ %s has no %s build — it will NOT be installed (see the panel on the right)",
					item.template.Name, m.hostArch))
		}
		m.selectDependencies(item.template, &notifications)
		m.autoSelectExtensions(item.template, &notifications)
	}

	if len(notifications) > 0 {
		m.notification = strings.Join(notifications, " | ")
	} else {
		m.notification = ""
	}
}

// applyDeselectItem actually deselects item. For a template, every
// dependent computed by dependentsOf goes down with it — a confirmed
// prompt already told the user this would happen.
func (m *model) applyDeselectItem(item treeItem) {
	if item.kind == kindTemplate {
		for _, dep := range m.dependentsOf(item.template.Name) {
			m.deselectKey(dep)
		}
		m.deselectTemplate(item.template)
	} else {
		delete(m.selected, item.key())
		m.clearParamValues(item.key(), item.extension)
	}
	// Reset param focus if we were editing this item
	if m.paramFocused {
		m.paramFocused = false
		m.paramEditing = false
	}
	m.notification = ""
}

// selectTemplateByName selects a template by name and handles its dependencies and auto-extensions.
func (m *model) selectTemplateByName(name string, notifications *[]string) {
	t, ok := m.registry.ByName[name]
	if !ok {
		return
	}
	if m.selected[name] {
		return
	}
	m.selected[name] = true
	m.initParamDefaults(name, t)
	*notifications = append(*notifications, fmt.Sprintf("Dependency: %s", name))
	m.selectDependencies(t, notifications)
	m.autoSelectExtensions(t, notifications)
}

// deselectTemplate removes a template and all its extensions from the
// selection, clearing param values for each. Shared by applyDeselectItem
// (clicking the template's own row) and anything else that needs to
// deselect a template by reference rather than by cursor position.
func (m *model) deselectTemplate(t *tmpl.Template) {
	delete(m.selected, t.Name)
	m.clearParamValues(t.Name, t)
	for _, ext := range t.Extensions {
		extKey := t.Name + "/" + ext.Name
		delete(m.selected, extKey)
		m.clearParamValues(extKey, ext)
	}
}

// deselectKey removes one selection key — "tmplName" or "tmplName/extName"
// — without touching anything else. Used to take down the dependents named
// by dependentsOf one at a time; a template key also drops its own
// extensions, same as deselectTemplate.
func (m *model) deselectKey(key string) {
	tName, extName, isExt := strings.Cut(key, "/")
	t, ok := m.registry.ByName[tName]
	if !ok {
		delete(m.selected, key)
		return
	}
	if !isExt {
		m.deselectTemplate(t)
		return
	}
	delete(m.selected, key)
	for _, ext := range t.Extensions {
		if ext.Name == extName {
			m.clearParamValues(key, ext)
			return
		}
	}
}

// selectDependencies recursively selects required templates.
func (m *model) selectDependencies(t *tmpl.Template, notifications *[]string) {
	for _, req := range t.Requires {
		if !m.selected[req] {
			m.selectTemplateByName(req, notifications)
		}
	}
}

// autoSelectExtensions selects extensions marked as auto-select.
func (m *model) autoSelectExtensions(t *tmpl.Template, notifications *[]string) {
	var autoSelected []string
	for _, ext := range t.Extensions {
		if ext.AutoSelect != nil && *ext.AutoSelect {
			extKey := t.Name + "/" + ext.Name
			if !m.selected[extKey] {
				m.selected[extKey] = true
				m.initParamDefaults(extKey, ext)
				autoSelected = append(autoSelected, ext.Name)
			}
		}
	}
	if len(autoSelected) > 0 {
		*notifications = append(*notifications, fmt.Sprintf("Auto: %s/%s", t.Name, strings.Join(autoSelected, ",")))
	}
}

// initParamDefaults populates paramValues with default values for a template/extension.
// itemKey is the selection key (e.g. "go" or "go/go-pkg").
func (m *model) initParamDefaults(itemKey string, t *tmpl.Template) {
	for name, p := range t.Params {
		pk := itemKey + ":" + name
		if _, exists := m.paramValues[pk]; !exists {
			m.paramValues[pk] = p.Default
		}
	}
}

// clearParamValues removes all param values for a given item key.
func (m *model) clearParamValues(itemKey string, t *tmpl.Template) {
	for name := range t.Params {
		delete(m.paramValues, itemKey+":"+name)
	}
}

// templateImpliesDind reports whether any currently selected template or
// extension carries dind = true as a config default (e.g. the "dind" tool
// itself, or an extension like aws-sam-cli's "Docker-in-Docker for sam
// local"). Those set Dind as a side effect of being selected, with no --set
// of their own to round-trip through a Boothfile header — so the Container
// section's "Docker-in-Docker" checkbox has to be derived from the live
// selection to stay honest instead of only reflecting an explicit --set,
// both while selecting in this session and when reopening a booth whose
// config.toml got dind = true this way.
func (m model) templateImpliesDind() bool {
	if m.registry == nil {
		return false
	}
	for key, on := range m.selected {
		if !on {
			continue
		}
		tName, extName, isExt := strings.Cut(key, "/")
		t, ok := m.registry.ByName[tName]
		if !ok {
			continue
		}
		if !isExt {
			if t.Dind != nil && *t.Dind {
				return true
			}
			continue
		}
		for _, ext := range t.Extensions {
			if ext.Name == extName && ext.Dind != nil && *ext.Dind {
				return true
			}
		}
	}
	return false
}

// setDindSelected is the mirror image of templateImpliesDind: ticking the
// Container section's "Docker-in-Docker" box selects the "dind" tool in the
// catalog, same as picking it there directly (requires/auto-select/prompt
// all included); unticking it deselects the tool the same way its catalog
// row would. The two are the same setting shown on two different tabs, so
// acting on one has to act on the other.
func (m *model) setDindSelected(on bool) {
	if m.registry == nil {
		return
	}
	t, ok := m.registry.ByName["dind"]
	if !ok {
		return
	}
	item := treeItem{kind: kindTemplate, template: t}
	if on {
		if m.selected["dind"] {
			return
		}
		m.requestSelect(item)
		return
	}
	if !m.selected["dind"] {
		return
	}
	m.requestDeselect(item)
}

// selectionRequires returns the immediate requires of one selection key —
// "tmplName" (the template's own Requires) or "tmplName/extName" (that
// extension's own Requires; extensions are never themselves a requires
// target, only a source).
func (m *model) selectionRequires(key string) []string {
	if m.registry == nil {
		return nil
	}
	tName, extName, isExt := strings.Cut(key, "/")
	t, ok := m.registry.ByName[tName]
	if !ok {
		return nil
	}
	if !isExt {
		return t.Requires
	}
	for _, ext := range t.Extensions {
		if ext.Name == extName {
			return ext.Requires
		}
	}
	return nil
}

// transitiveRequiresOf returns every template name directly or indirectly
// required by the given selection key, following each required template's
// own Requires in turn.
func (m *model) transitiveRequiresOf(key string) []string {
	seen := make(map[string]bool)
	var order []string
	var walk func(names []string)
	walk = func(names []string) {
		for _, n := range names {
			if seen[n] {
				continue
			}
			seen[n] = true
			order = append(order, n)
			if t, ok := m.registry.ByName[n]; ok {
				walk(t.Requires)
			}
		}
	}
	walk(m.selectionRequires(key))
	return order
}

// pendingRequires returns the names of currently-unselected templates that
// selecting item would pull in via the requires graph — NOT the parent
// template an unselected extension always silently pulls in on its own
// (that's a structural extension-of-a-template relationship, not a
// requires choice, and stays as automatic as it's always been). What it
// does count is the transitive requires closure of item, and — since
// selecting the extension is about to select that parent too — the
// parent's own requires closure as well. Empty when selecting item needs
// nothing new.
func (m *model) pendingRequires(item treeItem) []string {
	need := make(map[string]bool)
	add := func(key string) {
		for _, req := range m.transitiveRequiresOf(key) {
			if !m.selected[req] {
				need[req] = true
			}
		}
	}

	switch item.kind {
	case kindTemplate:
		add(item.template.Name)
	case kindExtension:
		if !m.selected[item.template.Name] {
			add(item.template.Name)
		}
		add(item.template.Name + "/" + item.extension.Name)
	}

	names := make([]string, 0, len(need))
	for n := range need {
		names = append(names, n)
	}
	sort.Strings(names)
	return names
}

// dependentsOf returns every other currently-selected key (template or
// extension) that would be left requiring something no longer selected if
// the template `name` were deselected — expanded transitively, so removing
// a link partway down a requires chain takes the rest of that chain's
// dependents with it too.
func (m *model) dependentsOf(name string) []string {
	removed := map[string]bool{name: true}
	for changed := true; changed; {
		changed = false
		for key, on := range m.selected {
			if !on || removed[key] {
				continue
			}
			for _, req := range m.transitiveRequiresOf(key) {
				if removed[req] {
					removed[key] = true
					changed = true
					break
				}
			}
		}
	}
	delete(removed, name)

	names := make([]string, 0, len(removed))
	for k := range removed {
		names = append(names, k)
	}
	sort.Strings(names)
	return names
}

// displayNameForKey resolves a selection key ("tmplName" or
// "tmplName/extName") to the label shown for it in the catalog, falling
// back to the raw key if the registry doesn't have it (shouldn't happen for
// anything that reached dependentsOf/pendingRequires, but a prompt is the
// wrong place to panic over it).
func (m *model) displayNameForKey(key string) string {
	if m.registry == nil {
		return key
	}
	tName, extName, isExt := strings.Cut(key, "/")
	t, ok := m.registry.ByName[tName]
	if !ok {
		return key
	}
	if !isExt {
		return t.DisplayName
	}
	for _, ext := range t.Extensions {
		if ext.Name == extName {
			return ext.DisplayName
		}
	}
	return key
}
