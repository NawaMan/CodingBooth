// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// treeItem is a flattened tree node: category header, template, or extension.
type itemKind int

const (
	kindCategory  itemKind = iota
	kindTemplate
	kindExtension
)

type treeItem struct {
	kind         itemKind
	categoryName string // display name for category headers
	template     *tmpl.Template
	extension    *tmpl.Template // non-nil for extensions
}

func (ti treeItem) key() string {
	switch ti.kind {
	case kindTemplate:
		return ti.template.Name
	case kindExtension:
		return ti.template.Name + "/" + ti.extension.Name
	}
	return ""
}

// focusArea tracks which part of the TUI has focus.
type focusArea int

const (
	focusTree    focusArea = iota
	focusVariant
	focusPort
)

var variants = []string{"", "base", "notebook", "codeserver", "desktop-xfce", "desktop-kde", "terminal"}

type model struct {
	registry     *tmpl.TemplateRegistry
	flatItems    []treeItem
	selected     map[string]bool // key: "tmplName" or "tmplName/extName"
	cursor       int
	scrollOffset int
	width        int
	height       int
	notification string
	confirmed    bool
	quitting     bool // true when showing quit confirmation
	focus        focusArea

	// Config fields
	variant      string
	variantIdx   int
	port         string
	portEditing  bool
	portCursor   int
}

func newModel(registry *tmpl.TemplateRegistry, pre *PreSelection) model {
	m := model{
		registry: registry,
		selected: make(map[string]bool),
		port:     "10000",
	}

	// Flatten the tree: category headers + templates + extensions
	for _, cat := range registry.Categories {
		m.flatItems = append(m.flatItems, treeItem{
			kind:         kindCategory,
			categoryName: cat.DisplayName,
		})
		for _, t := range cat.Templates {
			m.flatItems = append(m.flatItems, treeItem{
				kind:     kindTemplate,
				template: t,
			})
			for _, ext := range t.Extensions {
				m.flatItems = append(m.flatItems, treeItem{
					kind:      kindExtension,
					template:  t,
					extension: ext,
				})
			}
		}
	}

	// Apply pre-selections
	if pre != nil {
		if pre.Variant != "" {
			m.variant = pre.Variant
			for i, v := range variants {
				if v == pre.Variant {
					m.variantIdx = i
					break
				}
			}
		}
		if pre.Port != "" {
			m.port = pre.Port
		}
		for tName := range pre.SelectedTemplates {
			m.selected[tName] = true
		}
		for tName, exts := range pre.SelectedExts {
			for eName := range exts {
				m.selected[tName+"/"+eName] = true
			}
		}
	}

	// Start cursor on first selectable item (skip category headers)
	for i, item := range m.flatItems {
		if item.kind != kindCategory {
			m.cursor = i
			break
		}
	}

	return m
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		return m, nil

	case tea.KeyMsg:
		// Quit confirmation mode
		if m.quitting {
			switch msg.String() {
			case "enter":
				return m, tea.Quit
			case "escape":
				m.quitting = false
				m.notification = ""
				return m, nil
			}
			return m, nil
		}

		// Port editing mode
		if m.portEditing {
			return m.handlePortEdit(msg)
		}

		switch msg.String() {
		case "ctrl+c", "ctrl+q":
			m.quitting = true
			m.notification = "Quit without saving? Enter: confirm  │  Esc: cancel"
			return m, nil

		case "ctrl+s":
			m.confirmed = true
			return m, tea.Quit

		case "tab":
			m.focus = (m.focus + 1) % 3
			return m, nil

		case "shift+tab":
			m.focus = (m.focus + 2) % 3 // go backward
			return m, nil
		}

		switch m.focus {
		case focusTree:
			return m.handleTreeKey(msg)
		case focusVariant:
			return m.handleVariantKey(msg)
		case focusPort:
			return m.handlePortKey(msg)
		}
	}
	return m, nil
}

func (m model) handleTreeKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "up":
		m.moveCursor(-1)
	case "down":
		m.moveCursor(1)
	case "pgup":
		m.moveCursor(-m.contentHeight())
	case "pgdown":
		m.moveCursor(m.contentHeight())
	case "home":
		m.cursor = 0
		m.moveCursor(0) // skip category headers
	case "end":
		m.cursor = len(m.flatItems) - 1
	case " ":
		m.toggleSelection()
	}

	// Adjust scroll
	m.adjustScroll()
	return m, nil
}

func (m *model) moveCursor(delta int) {
	if len(m.flatItems) == 0 {
		return
	}
	m.cursor += delta
	if m.cursor < 0 {
		m.cursor = 0
	}
	if m.cursor >= len(m.flatItems) {
		m.cursor = len(m.flatItems) - 1
	}
	// Skip category headers
	if m.flatItems[m.cursor].kind == kindCategory {
		if delta >= 0 {
			m.cursor++
		} else {
			m.cursor--
		}
	}
	if m.cursor < 0 {
		m.cursor = 0
	}
	if m.cursor >= len(m.flatItems) {
		m.cursor = len(m.flatItems) - 1
	}
}

func (m *model) adjustScroll() {
	h := m.contentHeight()
	if h <= 0 {
		return
	}
	if m.cursor < m.scrollOffset {
		m.scrollOffset = m.cursor
	}
	if m.cursor >= m.scrollOffset+h {
		m.scrollOffset = m.cursor - h + 1
	}
}

func (m model) handleVariantKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "left":
		if m.variantIdx > 0 {
			m.variantIdx--
		}
	case "right":
		if m.variantIdx < len(variants)-1 {
			m.variantIdx++
		}
	}
	m.variant = variants[m.variantIdx]
	return m, nil
}

func (m model) handlePortKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter":
		m.portEditing = true
		m.portCursor = len(m.port)
	}
	return m, nil
}

func (m model) handlePortEdit(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter", "escape":
		m.portEditing = false
	case "backspace":
		if m.portCursor > 0 && len(m.port) > 0 {
			m.port = m.port[:m.portCursor-1] + m.port[m.portCursor:]
			m.portCursor--
		}
	case "left":
		if m.portCursor > 0 {
			m.portCursor--
		}
	case "right":
		if m.portCursor < len(m.port) {
			m.portCursor++
		}
	default:
		ch := msg.String()
		if len(ch) == 1 && ((ch[0] >= '0' && ch[0] <= '9') || ch[0] >= 'A') {
			m.port = m.port[:m.portCursor] + ch + m.port[m.portCursor:]
			m.portCursor++
		}
	}
	return m, nil
}

func (m model) contentHeight() int {
	h := m.height - 7 // header(1) + config(1) + sep(2) + footer-message(1) + footer-hints(1) + pad(1)
	if h < 1 {
		return 1
	}
	return h
}

func (m model) buildSelectDSL() string {
	var parts []string

	for _, cat := range m.registry.Categories {
		for _, t := range cat.Templates {
			if !m.selected[t.Name] {
				continue
			}
			item := t.Name

			// Collect selected extensions
			var exts []string
			for _, ext := range t.Extensions {
				extKey := t.Name + "/" + ext.Name
				if m.selected[extKey] {
					// Skip auto-selected ones (they'll be included automatically)
					isAutoSelect := ext.AutoSelect != nil && *ext.AutoSelect
					if !isAutoSelect {
						exts = append(exts, ext.Name)
					}
				}
			}

			// Collect excluded auto-select extensions
			var excludes []string
			for _, ext := range t.Extensions {
				extKey := t.Name + "/" + ext.Name
				isAutoSelect := ext.AutoSelect != nil && *ext.AutoSelect
				if isAutoSelect && !m.selected[extKey] {
					excludes = append(excludes, ext.Name)
				}
			}

			if len(exts) > 0 {
				item += "+" + strings.Join(exts, "+")
			}
			if len(excludes) > 0 {
				item += "~" + strings.Join(excludes, "~")
			}

			parts = append(parts, item)
		}
	}

	return strings.Join(parts, "/")
}
