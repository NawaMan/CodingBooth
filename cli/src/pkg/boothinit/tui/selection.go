// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"
	"strings"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// toggleSelection handles space-bar toggling with auto-select and dependency cascading.
func (m *model) toggleSelection() {
	items := m.activeItems()
	cursor := m.cursorPos()
	if len(items) == 0 || cursor < 0 || cursor >= len(items) {
		return
	}
	item := items[cursor]

	key := item.key()
	var notifications []string

	if m.selected[key] {
		// Deselecting
		delete(m.selected, key)
		if item.kind == kindTemplate {
			// Deselect all extensions of this template and clean up params
			m.clearParamValues(item.template.Name, item.template)
			for _, ext := range item.template.Extensions {
				extKey := item.template.Name + "/" + ext.Name
				delete(m.selected, extKey)
				m.clearParamValues(extKey, ext)
			}
		} else {
			m.clearParamValues(key, item.extension)
		}
		// Reset param focus if we were editing this item
		if m.paramFocused {
			m.paramFocused = false
			m.paramEditing = false
		}
	} else {
		// Selecting
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
			m.selectDependencies(item.template, &notifications)
			m.autoSelectExtensions(item.template, &notifications)
		}
	}

	if len(notifications) > 0 {
		m.notification = strings.Join(notifications, " | ")
	} else {
		m.notification = ""
	}
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
