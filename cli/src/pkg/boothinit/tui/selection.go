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
	if len(m.flatItems) == 0 || m.cursor < 0 || m.cursor >= len(m.flatItems) {
		return
	}
	item := m.flatItems[m.cursor]
	if item.kind == kindCategory {
		return
	}

	key := item.key()
	var notifications []string

	if m.selected[key] {
		// Deselecting
		delete(m.selected, key)
		if item.kind == kindTemplate {
			// Deselect all extensions of this template
			for _, ext := range item.template.Extensions {
				delete(m.selected, item.template.Name+"/"+ext.Name)
			}
		}
	} else {
		// Selecting
		m.selected[key] = true

		if item.kind == kindExtension {
			// Auto-select parent template if not selected
			if !m.selected[item.template.Name] {
				m.selected[item.template.Name] = true
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
				autoSelected = append(autoSelected, ext.Name)
			}
		}
	}
	if len(autoSelected) > 0 {
		*notifications = append(*notifications, fmt.Sprintf("Auto: %s/%s", t.Name, strings.Join(autoSelected, ",")))
	}
}
