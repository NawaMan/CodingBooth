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

var variants = []string{"", "base", "notebook", "codeserver", "desktop-xfce", "desktop-kde", "terminal"}

// configField identifies a field in the Config tab.
type configField int

const (
	fieldVariant configField = iota
	fieldPort
	configFieldCount // sentinel
)

type model struct {
	registry *tmpl.TemplateRegistry
	selected map[string]bool // key: "tmplName" or "tmplName/extName"
	width    int
	height   int

	// Tabs — tab 0 is Config, tabs 1..N are categories (sorted by order)
	tabNames      []string     // display names (index 0 = "Config")
	tabItems      [][]treeItem // items per tab (index 0 = nil for Config tab)
	activeTab     int
	tabCursors    []int // cursor per tab (tab 0: config field index)
	tabScrollOffs []int // scroll offset per tab (tab 0: unused)

	notification string
	confirmed    bool
	quitting     bool // true when showing quit confirmation

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

	// Tab 0: Config
	m.tabNames = append(m.tabNames, "Config")
	m.tabItems = append(m.tabItems, nil) // no tree items for config tab

	// Tabs 1..N: categories (already sorted by Order in registry)
	for _, cat := range registry.Categories {
		// Sort templates by name
		sortedTemplates := make([]*tmpl.Template, len(cat.Templates))
		copy(sortedTemplates, cat.Templates)
		sort.Slice(sortedTemplates, func(i, j int) bool {
			return sortedTemplates[i].Name < sortedTemplates[j].Name
		})

		var items []treeItem
		for _, t := range sortedTemplates {
			items = append(items, treeItem{kind: kindTemplate, template: t})

			// Sort extensions by name
			sortedExts := make([]*tmpl.Template, len(t.Extensions))
			copy(sortedExts, t.Extensions)
			sort.Slice(sortedExts, func(i, j int) bool {
				return sortedExts[i].Name < sortedExts[j].Name
			})
			for _, ext := range sortedExts {
				items = append(items, treeItem{kind: kindExtension, template: t, extension: ext})
			}
		}
		m.tabNames = append(m.tabNames, cat.DisplayName)
		m.tabItems = append(m.tabItems, items)
	}

	m.tabCursors = make([]int, len(m.tabItems))
	m.tabScrollOffs = make([]int, len(m.tabItems))

	// Default to tab 1 (first category)
	m.activeTab = 1
	if len(m.tabItems) <= 1 {
		m.activeTab = 0
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

	return m
}

// isConfigTab returns true if the active tab is the Config tab (tab 0).
func (m *model) isConfigTab() bool {
	return m.activeTab == 0
}

// activeItems returns the items for the currently active tab.
func (m *model) activeItems() []treeItem {
	if m.activeTab < 0 || m.activeTab >= len(m.tabItems) {
		return nil
	}
	return m.tabItems[m.activeTab]
}

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
			case "esc":
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
		}

		// Tab switching
		if handled, result := m.handleTabSwitch(msg); handled {
			return result, nil
		}

		// Route to active tab handler
		if m.isConfigTab() {
			return m.handleConfigKey(msg)
		}
		return m.handleTreeKey(msg)
	}
	return m, nil
}

// handleTabSwitch checks for digit keys and left/right arrow tab switching.
func (m *model) handleTabSwitch(msg tea.KeyMsg) (bool, tea.Model) {
	numTabs := len(m.tabItems)
	if numTabs == 0 {
		return false, m
	}

	key := msg.String()

	// 0 through 9
	for i := 0; i < numTabs && i <= 9; i++ {
		digit := fmt.Sprintf("%d", i)
		if key == digit {
			m.activeTab = i
			return true, m
		}
	}

	// Left/Right arrows switch tabs
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

	return false, m
}

// handleConfigKey handles keys when the Config tab is active.
func (m model) handleConfigKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	cursor := m.cursorPos()
	field := configField(cursor)

	switch msg.String() {
	case "up":
		if cursor > 0 {
			m.setCursor(cursor - 1)
		}
	case "down":
		if cursor < int(configFieldCount)-1 {
			m.setCursor(cursor + 1)
		}
	case " ", "enter":
		// For variant: cycle forward
		if field == fieldVariant {
			m.variantIdx = (m.variantIdx + 1) % len(variants)
			m.variant = variants[m.variantIdx]
		}
		// For port: enter editing mode
		if field == fieldPort {
			m.portEditing = true
			m.portCursor = len(m.port)
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

func (m model) handlePortEdit(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter", "esc":
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
	h := m.height - 7 // header(1) + search(1) + tabs(1) + sep(2) + footer-message(1) + footer-hints(1)
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
