// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
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
	tabScrollOffs []int // scroll offset per tab

	notification string
	confirmed    bool
	quitting     bool // true when showing quit confirmation

	// Config fields (generic)
	stringFields map[string]string // values for string/cycle fields
	boolFields   map[string]bool   // values for bool fields
	cycleIndices map[string]int    // current index for cycle fields
	editing      bool              // true when editing a string field
	editCursor   int               // cursor position within the edited string
}

func newModel(registry *tmpl.TemplateRegistry, pre *PreSelection) model {
	m := model{
		registry:     registry,
		selected:     make(map[string]bool),
		stringFields: make(map[string]string),
		boolFields:   defaultBoolValues(),
		cycleIndices: make(map[string]int),
	}

	// Set string field defaults
	m.stringFields["port"] = "10000"

	// Tab 0: Config
	m.tabNames = append(m.tabNames, "Config")
	m.tabItems = append(m.tabItems, nil)

	// Tabs 1..N: categories
	for _, cat := range registry.Categories {
		sortedTemplates := make([]*tmpl.Template, len(cat.Templates))
		copy(sortedTemplates, cat.Templates)
		sort.Slice(sortedTemplates, func(i, j int) bool {
			return sortedTemplates[i].Name < sortedTemplates[j].Name
		})

		var items []treeItem
		for _, t := range sortedTemplates {
			items = append(items, treeItem{kind: kindTemplate, template: t})

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
		for k, v := range pre.StringFields {
			if v != "" {
				m.stringFields[k] = v
			}
		}
		for k, v := range pre.BoolFields {
			m.boolFields[k] = v
		}
		// Sync cycle indices with string values
		for _, f := range allConfigFields {
			if f.Kind == fieldKindCycle {
				val := m.stringFields[f.Key]
				for i, opt := range f.Options {
					if opt == val {
						m.cycleIndices[f.Key] = i
						break
					}
				}
			}
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

// currentConfigField returns the config field definition at the current cursor position.
func (m *model) currentConfigField() *configFieldDef {
	idx := m.cursorPos()
	if idx >= 0 && idx < len(allConfigFields) {
		return &allConfigFields[idx]
	}
	return nil
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

		// String field editing mode
		if m.editing {
			return m.handleStringEdit(msg)
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

func (m *model) handleTabSwitch(msg tea.KeyMsg) (bool, tea.Model) {
	numTabs := len(m.tabItems)
	if numTabs == 0 {
		return false, m
	}

	key := msg.String()

	// 0 through 9
	for i := 0; i < numTabs && i <= 9; i++ {
		digit := string(rune('0' + i))
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
	maxIdx := len(allConfigFields) - 1

	switch msg.String() {
	case "up":
		cur := m.cursorPos()
		if cur > 0 {
			m.setCursor(cur - 1)
		}
	case "down":
		cur := m.cursorPos()
		if cur < maxIdx {
			m.setCursor(cur + 1)
		}
	case "pgup":
		cur := m.cursorPos() - m.contentHeight()
		if cur < 0 {
			cur = 0
		}
		m.setCursor(cur)
	case "pgdown":
		cur := m.cursorPos() + m.contentHeight()
		if cur > maxIdx {
			cur = maxIdx
		}
		m.setCursor(cur)
	case "home":
		m.setCursor(0)
	case "end":
		m.setCursor(maxIdx)
	case " ", "enter":
		f := m.currentConfigField()
		if f == nil {
			break
		}
		switch f.Kind {
		case fieldKindBool:
			m.boolFields[f.Key] = !m.boolFields[f.Key]
		case fieldKindCycle:
			idx := m.cycleIndices[f.Key]
			idx = (idx + 1) % len(f.Options)
			m.cycleIndices[f.Key] = idx
			m.stringFields[f.Key] = f.Options[idx]
		case fieldKindString:
			m.editing = true
			m.editCursor = len(m.stringFields[f.Key])
		}
	}

	m.adjustConfigScroll()
	return m, nil
}

func (m *model) adjustConfigScroll() {
	h := m.contentHeight()
	if h <= 0 {
		return
	}

	// Build a mapping from field index to rendered line index (accounting for group headers)
	lineIdx := 0
	fieldLinePos := make([]int, len(allConfigFields))
	lastGroup := ""
	for i, f := range allConfigFields {
		if f.Group != lastGroup {
			lineIdx++ // group header takes a line
			lastGroup = f.Group
		}
		fieldLinePos[i] = lineIdx
		lineIdx++
	}

	cur := m.cursorPos()
	if cur < 0 || cur >= len(fieldLinePos) {
		return
	}

	curLine := fieldLinePos[cur]
	off := m.tabScrollOffs[0]
	offLine := 0
	if off >= 0 && off < len(fieldLinePos) {
		offLine = fieldLinePos[off]
		// Include group header above if present
		if off > 0 && allConfigFields[off].Group != allConfigFields[off-1].Group {
			offLine--
		}
	}

	// Scroll up: cursor above visible area
	if curLine < offLine {
		// Find the field index whose line position puts cursor at top
		for i, lp := range fieldLinePos {
			// Account for group header above this field
			startLine := lp
			if i == 0 || allConfigFields[i].Group != allConfigFields[i-1].Group {
				startLine--
			}
			if startLine < 0 {
				startLine = 0
			}
			if lp >= curLine {
				m.tabScrollOffs[0] = i
				break
			}
			_ = startLine
		}
	}

	// Scroll down: cursor below visible area
	if curLine >= offLine+h {
		// Find scroll offset that puts cursor line at the bottom of visible area
		targetTopLine := curLine - h + 1
		if targetTopLine < 0 {
			targetTopLine = 0
		}
		for i, lp := range fieldLinePos {
			headerLine := lp
			if i == 0 || allConfigFields[i].Group != allConfigFields[i-1].Group {
				headerLine--
			}
			if headerLine < 0 {
				headerLine = 0
			}
			if headerLine >= targetTopLine {
				m.tabScrollOffs[0] = i
				break
			}
		}
	}
}

func (m model) handleStringEdit(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	f := m.currentConfigField()
	if f == nil {
		m.editing = false
		return m, nil
	}
	val := m.stringFields[f.Key]

	switch msg.String() {
	case "enter", "esc":
		m.editing = false
	case "backspace":
		if m.editCursor > 0 && len(val) > 0 {
			val = val[:m.editCursor-1] + val[m.editCursor:]
			m.editCursor--
		}
	case "left":
		if m.editCursor > 0 {
			m.editCursor--
		}
		// Don't switch tabs while editing
	case "right":
		if m.editCursor < len(val) {
			m.editCursor++
		}
		// Don't switch tabs while editing
	default:
		ch := msg.String()
		if len(ch) == 1 && ch[0] >= 32 && ch[0] < 127 {
			val = val[:m.editCursor] + ch + val[m.editCursor:]
			m.editCursor++
		}
	}
	m.stringFields[f.Key] = val
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
