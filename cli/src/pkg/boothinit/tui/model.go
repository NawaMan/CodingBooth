// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// treeItem is a flattened tree node: template or extension.
type itemKind int

const (
	kindTemplate  itemKind = iota
	kindExtension
)

type treeItem struct {
	kind      itemKind
	template  *tmpl.Template
	extension *tmpl.Template // non-nil for extensions
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
	registry *tmpl.TemplateRegistry
	selected map[string]bool // key: "tmplName" or "tmplName/extName"
	width    int
	height   int

	// Tabs — one per category, sorted by category order
	tabNames       []string     // display names
	tabItems       [][]treeItem // items per tab
	activeTab      int
	tabCursors     []int // cursor per tab
	tabScrollOffs  []int // scroll offset per tab

	notification string
	confirmed    bool
	quitting     bool // true when showing quit confirmation
	focus        focusArea

	// Config fields
	variant     string
	variantIdx  int
	port        string
	portEditing bool
	portCursor  int
}

func newModel(registry *tmpl.TemplateRegistry, pre *PreSelection) model {
	m := model{
		registry: registry,
		selected: make(map[string]bool),
		port:     "10000",
	}

	// Build per-tab item lists (categories already sorted by Order in registry)
	for _, cat := range registry.Categories {
		var items []treeItem
		for _, t := range cat.Templates {
			items = append(items, treeItem{kind: kindTemplate, template: t})
			for _, ext := range t.Extensions {
				items = append(items, treeItem{kind: kindExtension, template: t, extension: ext})
			}
		}
		m.tabNames = append(m.tabNames, cat.DisplayName)
		m.tabItems = append(m.tabItems, items)
	}

	m.tabCursors = make([]int, len(m.tabItems))
	m.tabScrollOffs = make([]int, len(m.tabItems))

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

	return m
}

// activeItems returns the items for the currently active tab.
func (m *model) activeItems() []treeItem {
	if m.activeTab < 0 || m.activeTab >= len(m.tabItems) {
		return nil
	}
	return m.tabItems[m.activeTab]
}

// activeCursor returns a pointer to the current tab's cursor.
func (m *model) cursorPos() int {
	return m.tabCursors[m.activeTab]
}

func (m *model) setCursor(v int) {
	m.tabCursors[m.activeTab] = v
}

func (m *model) scrollOffset() int {
	return m.tabScrollOffs[m.activeTab]
}

func (m *model) setScrollOffset(v int) {
	m.tabScrollOffs[m.activeTab] = v
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

		// Tab switching: Ctrl+1 through Ctrl+9
		if handled, result := m.handleTabSwitch(msg); handled {
			return result, nil
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

// handleTabSwitch checks for Ctrl+1..Ctrl+9 and left/right arrow tab switching.
func (m *model) handleTabSwitch(msg tea.KeyMsg) (bool, tea.Model) {
	numTabs := len(m.tabItems)
	if numTabs == 0 {
		return false, m
	}

	key := msg.String()

	// Ctrl+1 through Ctrl+9
	// Note: terminals often send these as alt+1..alt+9 or special sequences.
	// Bubbletea may report them differently depending on terminal.
	// We handle both common representations.
	for i := 0; i < numTabs && i < 9; i++ {
		digit := fmt.Sprintf("%d", i+1)
		if key == digit {
			m.activeTab = i
			return true, m
		}
	}

	// Left/Right arrows switch tabs when in tree focus
	if m.focus == focusTree {
		switch key {
		case "left":
			if m.activeTab > 0 {
				m.activeTab--
			}
			return true, m
		case "right":
			if m.activeTab < numTabs-1 {
				m.activeTab++
			}
			return true, m
		}
	}

	return false, m
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
		m.setCursor(0)
	case "end":
		items := m.activeItems()
		if len(items) > 0 {
			m.setCursor(len(items) - 1)
		}
	case " ":
		m.toggleSelection()
	}

	m.adjustScroll()
	return m, nil
}

func (m *model) moveCursor(delta int) {
	items := m.activeItems()
	if len(items) == 0 {
		return
	}
	cur := m.cursorPos() + delta
	if cur < 0 {
		cur = 0
	}
	if cur >= len(items) {
		cur = len(items) - 1
	}
	m.setCursor(cur)
}

func (m *model) adjustScroll() {
	h := m.contentHeight()
	if h <= 0 {
		return
	}
	cur := m.cursorPos()
	off := m.scrollOffset()
	if cur < off {
		off = cur
	}
	if cur >= off+h {
		off = cur - h + 1
	}
	m.setScrollOffset(off)
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
	h := m.height - 8 // header(1) + config(1) + tabs(1) + sep(2) + footer-message(1) + footer-hints(1) + pad(1)
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
