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

	// Warning dialog — shown once at startup (e.g., .booth not writable)
	warningDialog  bool
	warningMessage string

	// Search
	searchQuery   string
	searchFocused bool
	searchCursor  int

	// Config fields (generic)
	stringFields map[string]string   // values for string/cycle fields
	boolFields   map[string]bool     // values for bool fields
	cycleIndices map[string]int      // current index for cycle fields
	listFields   map[string][]string // values for list fields (e.g., expose, env, mount)
	editing      bool                // true when editing a string field
	editCursor   int                 // cursor position within the edited string
	listEditing  bool                // true when editing a list item
	listEditIdx  int                 // index within the list being edited (-1 = none)

	// Template/extension parameter values
	// Key format: "templateName:PARAM_NAME" or "templateName/extName:PARAM_NAME"
	paramValues     map[string]string
	paramFocused    bool   // true when right panel param fields have focus
	paramEditing    bool   // true when editing a param string value
	paramEditKey    string // which param is being edited (full key)
	paramEditCursor int    // cursor position in edited string
	paramEditPrev   string // previous value before editing (for ESC cancel)
	paramCursorIdx  int    // which param field in right panel has focus
}

func newModel(registry *tmpl.TemplateRegistry, pre *PreSelection) model {
	m := model{
		registry:     registry,
		selected:     make(map[string]bool),
		stringFields: make(map[string]string),
		boolFields:   defaultBoolValues(),
		cycleIndices: make(map[string]int),
		listFields:   make(map[string][]string),
		paramValues:  make(map[string]string),
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
		for k, v := range pre.ListFields {
			if len(v) > 0 {
				m.listFields[k] = append([]string{}, v...)
			}
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
			// Init default param values for pre-selected templates
			if t, ok := registry.ByName[tName]; ok {
				m.initParamDefaults(tName, t)
			}
		}
		for tName, exts := range pre.SelectedExts {
			for eName := range exts {
				m.selected[tName+"/"+eName] = true
				// Init default param values for pre-selected extensions
				if t, ok := registry.ByName[tName]; ok {
					for _, ext := range t.Extensions {
						if ext.Name == eName {
							m.initParamDefaults(tName+"/"+eName, ext)
							break
						}
					}
				}
			}
		}
		// Apply pre-selected param values (overriding defaults)
		for k, v := range pre.ParamValues {
			m.paramValues[k] = v
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
	items := m.tabItems[m.activeTab]
	if m.searchQuery == "" {
		return items
	}
	return m.filterItems(items)
}

// filterItems returns items matching the search query (case-insensitive).
// - Template matches → show the template (without non-matching extensions)
// - Extension matches → show that extension + its parent template
// - Non-matching extensions are hidden
// - Templates with no match (and no matching extensions) are hidden
func (m *model) filterItems(items []treeItem) []treeItem {
	if m.searchQuery == "" {
		return items
	}
	query := strings.ToLower(m.searchQuery)

	matches := func(item treeItem) bool {
		var t *tmpl.Template
		if item.kind == kindTemplate {
			t = item.template
		} else {
			t = item.extension
		}
		return strings.Contains(strings.ToLower(t.Name), query) ||
			strings.Contains(strings.ToLower(t.DisplayName), query) ||
			strings.Contains(strings.ToLower(t.DisplayDesc), query)
	}

	// Find which templates have at least one matching extension
	parentNeeded := make(map[string]bool)
	for _, item := range items {
		if item.kind == kindExtension && matches(item) {
			parentNeeded[item.template.Name] = true
		}
	}

	var result []treeItem
	for _, item := range items {
		switch item.kind {
		case kindTemplate:
			if matches(item) || parentNeeded[item.template.Name] {
				result = append(result, item)
			}
		case kindExtension:
			if matches(item) {
				result = append(result, item)
			}
		}
	}

	return result
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

// configRowKind identifies the type of a config row in the rendered list.
type configRowKind int

const (
	configRowGroup    configRowKind = iota // group header
	configRowField                         // normal field (bool/cycle/string)
	configRowListItem                      // one entry of a list field
	configRowListAdd                       // the "(+ add new)" row for a list field
)

// configRow represents a single visible row in the config panel.
type configRow struct {
	kind      configRowKind
	group     string // for group headers
	fieldIdx  int    // index into allConfigFields
	listIndex int    // for list items: index into listFields[key]
}

// buildConfigRows builds the dynamic list of visible rows for the config panel.
func (m *model) buildConfigRows() []configRow {
	var rows []configRow
	lastGroup := ""
	for i, f := range allConfigFields {
		if f.Group != lastGroup {
			rows = append(rows, configRow{kind: configRowGroup, group: f.Group, fieldIdx: i})
			lastGroup = f.Group
		}
		if f.Kind == fieldKindList {
			items := m.listFields[f.Key]
			for li := range items {
				rows = append(rows, configRow{kind: configRowListItem, fieldIdx: i, listIndex: li})
			}
			rows = append(rows, configRow{kind: configRowListAdd, fieldIdx: i})
		} else {
			rows = append(rows, configRow{kind: configRowField, fieldIdx: i})
		}
	}
	return rows
}

// currentConfigRow returns the config row at the current cursor position.
func (m *model) currentConfigRow(rows []configRow) *configRow {
	idx := m.cursorPos()
	if idx >= 0 && idx < len(rows) {
		return &rows[idx]
	}
	return nil
}

// currentConfigField returns the config field definition at the current cursor position.
func (m *model) currentConfigField() *configFieldDef {
	rows := m.buildConfigRows()
	row := m.currentConfigRow(rows)
	if row == nil {
		return nil
	}
	if row.kind == configRowGroup {
		return nil
	}
	if row.fieldIdx >= 0 && row.fieldIdx < len(allConfigFields) {
		return &allConfigFields[row.fieldIdx]
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
		// Warning dialog mode — must dismiss before using TUI
		if m.warningDialog {
			switch msg.String() {
			case "enter", " ":
				m.warningDialog = false
				return m, nil
			case "esc", "ctrl+c", "ctrl+e":
				return m, tea.Quit
			}
			return m, nil
		}

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

		// Param string editing mode (right panel)
		if m.paramEditing {
			return m.handleParamStringEdit(msg)
		}

		// Param focus mode (right panel navigation)
		if m.paramFocused {
			return m.handleParamKey(msg)
		}

		// String field editing mode (config tab)
		if m.editing {
			return m.handleStringEdit(msg)
		}

		// Search input mode
		if m.searchFocused {
			return m.handleSearchInput(msg)
		}

		switch msg.String() {
		case "ctrl+c", "ctrl+e":
			m.quitting = true
			m.notification = "Quit without saving? Press ENTER to quit  │  ESC to go back"
			return m, nil

		case "ctrl+s":
			m.confirmed = true
			return m, tea.Quit

		case "tab":
			m.searchFocused = true
			m.searchCursor = len(m.searchQuery)
			return m, nil
		}

		// Tab switching (digit keys and left/right)
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

// handleSearchInput handles keys when the search bar is focused.
func (m model) handleSearchInput(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.searchQuery = ""
		m.searchFocused = false
		// Reset cursors since filtered items changed
		m.resetTabCursors()
		return m, nil

	case "tab", "enter", "down":
		m.searchFocused = false
		// Reset cursors since user may have changed search
		m.resetTabCursors()
		return m, nil

	case "ctrl+c", "ctrl+e":
		m.quitting = true
		m.notification = "Quit without saving? Press ENTER to quit  │  ESC to go back"
		m.searchFocused = false
		return m, nil

	case "ctrl+s":
		m.confirmed = true
		return m, tea.Quit

	case "backspace":
		if m.searchCursor > 0 && len(m.searchQuery) > 0 {
			m.searchQuery = m.searchQuery[:m.searchCursor-1] + m.searchQuery[m.searchCursor:]
			m.searchCursor--
			m.resetTabCursors()
		}

	case "left":
		if m.searchCursor > 0 {
			m.searchCursor--
		}

	case "right":
		if m.searchCursor < len(m.searchQuery) {
			m.searchCursor++
		}

	default:
		ch := msg.String()
		if len(ch) == 1 && ch[0] >= 32 && ch[0] < 127 {
			m.searchQuery = m.searchQuery[:m.searchCursor] + ch + m.searchQuery[m.searchCursor:]
			m.searchCursor++
			m.resetTabCursors()
			// Auto-switch to first category tab if on Config tab
			if m.isConfigTab() && len(m.tabItems) > 1 {
				m.activeTab = 1
			}
		}
	}
	return m, nil
}

// resetTabCursors resets all tab cursors to 0 when search changes.
func (m *model) resetTabCursors() {
	for i := range m.tabCursors {
		m.tabCursors[i] = 0
	}
	for i := range m.tabScrollOffs {
		m.tabScrollOffs[i] = 0
	}
}

func (m *model) handleTabSwitch(msg tea.KeyMsg) (bool, tea.Model) {
	numTabs := len(m.tabItems)
	if numTabs == 0 {
		return false, m
	}

	key := msg.String()

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
	rows := m.buildConfigRows()
	maxIdx := len(rows) - 1

	// Skip group headers when navigating
	skipGroups := func(pos, dir int) int {
		for pos >= 0 && pos <= maxIdx && rows[pos].kind == configRowGroup {
			pos += dir
		}
		if pos < 0 {
			pos = 0
		}
		if pos > maxIdx {
			pos = maxIdx
		}
		return pos
	}

	switch msg.String() {
	case "up":
		cur := m.cursorPos()
		if cur > 0 {
			m.setCursor(skipGroups(cur-1, -1))
		}
	case "down":
		cur := m.cursorPos()
		if cur < maxIdx {
			m.setCursor(skipGroups(cur+1, 1))
		}
	case "pgup":
		cur := m.cursorPos() - m.contentHeight()
		if cur < 0 {
			cur = 0
		}
		m.setCursor(skipGroups(cur, -1))
	case "pgdown":
		cur := m.cursorPos() + m.contentHeight()
		if cur > maxIdx {
			cur = maxIdx
		}
		m.setCursor(skipGroups(cur, 1))
	case "home":
		m.setCursor(skipGroups(0, 1))
	case "end":
		m.setCursor(skipGroups(maxIdx, -1))
	case "delete", "backspace":
		row := m.currentConfigRow(rows)
		if row != nil && row.kind == configRowListItem {
			f := allConfigFields[row.fieldIdx]
			items := m.listFields[f.Key]
			m.listFields[f.Key] = append(items[:row.listIndex], items[row.listIndex+1:]...)
			// Clamp cursor after deletion
			newRows := m.buildConfigRows()
			if m.cursorPos() >= len(newRows) {
				m.setCursor(len(newRows) - 1)
			}
		}
	case " ", "enter":
		row := m.currentConfigRow(rows)
		if row == nil {
			break
		}
		switch row.kind {
		case configRowField:
			f := allConfigFields[row.fieldIdx]
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
		case configRowListItem:
			f := allConfigFields[row.fieldIdx]
			m.listEditing = true
			m.listEditIdx = row.listIndex
			m.editing = true
			m.editCursor = len(m.listFields[f.Key][row.listIndex])
		case configRowListAdd:
			f := allConfigFields[row.fieldIdx]
			m.listFields[f.Key] = append(m.listFields[f.Key], "")
			m.listEditing = true
			m.listEditIdx = len(m.listFields[f.Key]) - 1
			m.editing = true
			m.editCursor = 0
			// Move cursor to the new list item row (one before the add row)
			newRows := m.buildConfigRows()
			for ri, r := range newRows {
				if r.kind == configRowListItem && r.fieldIdx == row.fieldIdx && r.listIndex == m.listEditIdx {
					m.setCursor(ri)
					break
				}
			}
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

	// Config scroll now uses row indices directly since buildConfigRows() gives
	// a 1:1 mapping between rows and rendered lines.
	rows := m.buildConfigRows()
	cur := m.cursorPos()
	if cur < 0 || cur >= len(rows) {
		return
	}

	off := m.tabScrollOffs[0]
	if off < 0 {
		off = 0
	}

	// Scroll up: cursor above visible area
	if cur < off {
		m.tabScrollOffs[0] = cur
		// Include group header above if present
		if cur > 0 && rows[cur-1].kind == configRowGroup {
			m.tabScrollOffs[0] = cur - 1
		}
	}

	// Scroll down: cursor below visible area
	if cur >= off+h {
		m.tabScrollOffs[0] = cur - h + 1
	}
}

func (m model) handleStringEdit(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	f := m.currentConfigField()
	if f == nil {
		m.editing = false
		m.listEditing = false
		return m, nil
	}

	// Determine which value we're editing
	var val string
	if m.listEditing {
		items := m.listFields[f.Key]
		if m.listEditIdx >= 0 && m.listEditIdx < len(items) {
			val = items[m.listEditIdx]
		}
	} else {
		val = m.stringFields[f.Key]
	}

	switch msg.String() {
	case "enter", "esc":
		m.editing = false
		if m.listEditing {
			// Remove empty entries on cancel/finish
			if val == "" {
				items := m.listFields[f.Key]
				m.listFields[f.Key] = append(items[:m.listEditIdx], items[m.listEditIdx+1:]...)
			}
			m.listEditing = false
			m.listEditIdx = -1
		}
		return m, nil
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

	// Write back the edited value
	if m.listEditing {
		m.listFields[f.Key][m.listEditIdx] = val
	} else {
		m.stringFields[f.Key] = val
	}
	return m, nil
}

// handleParamKey handles keys when the right panel param fields have focus.
func (m model) handleParamKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	item, paramNames := m.currentItemParams()
	if len(paramNames) == 0 {
		m.paramFocused = false
		return m, nil
	}

	var t *tmpl.Template
	if item.kind == kindExtension {
		t = item.extension
	} else {
		t = item.template
	}

	switch msg.String() {
	case "esc":
		m.paramFocused = false
		m.paramEditing = false
		return m, nil

	case "ctrl+c", "ctrl+e":
		m.paramFocused = false
		m.quitting = true
		m.notification = "Quit without saving? Press ENTER to quit  │  ESC to go back"
		return m, nil

	case "ctrl+s":
		m.confirmed = true
		return m, tea.Quit

	case "up":
		if m.paramCursorIdx > 0 {
			m.paramCursorIdx--
		}
		return m, nil

	case "down":
		if m.paramCursorIdx < len(paramNames)-1 {
			m.paramCursorIdx++
		}
		return m, nil

	case "left", "right":
		if m.paramCursorIdx >= len(paramNames) {
			return m, nil
		}
		pName := paramNames[m.paramCursorIdx]
		p := t.Params[pName]
		pk := paramKey(item, pName)

		if len(p.Suggests) > 0 {
			// Cycle through suggests with left/right
			currentVal := m.paramValues[pk]
			currentIdx := -1
			for i, s := range p.Suggests {
				if s == currentVal {
					currentIdx = i
					break
				}
			}
			if msg.String() == "right" {
				if currentIdx < 0 {
					m.paramValues[pk] = p.Suggests[0]
				} else if currentIdx < len(p.Suggests)-1 {
					m.paramValues[pk] = p.Suggests[currentIdx+1]
				}
			} else { // left
				if currentIdx < 0 {
					m.paramValues[pk] = p.Suggests[len(p.Suggests)-1]
				} else if currentIdx > 0 {
					m.paramValues[pk] = p.Suggests[currentIdx-1]
				}
			}
		}
		return m, nil

	case " ", "enter":
		if m.paramCursorIdx >= len(paramNames) {
			return m, nil
		}
		pName := paramNames[m.paramCursorIdx]
		pk := paramKey(item, pName)

		// Enter string edit mode directly
		m.paramEditing = true
		m.paramEditKey = pk
		m.paramEditCursor = len(m.paramValues[pk])
		m.paramEditPrev = m.paramValues[pk]
		return m, nil

	default:
		// Any typing starts custom string edit mode
		ch := msg.String()
		if len(ch) == 1 && ch[0] >= 32 && ch[0] < 127 {
			if m.paramCursorIdx < len(paramNames) {
				pName := paramNames[m.paramCursorIdx]
				pk := paramKey(item, pName)
				m.paramEditPrev = m.paramValues[pk]
				m.paramEditing = true
				m.paramEditKey = pk
				m.paramValues[pk] = ch
				m.paramEditCursor = 1
			}
		}
		return m, nil
	}

	return m, nil
}

// handleParamStringEdit handles typing when editing a param string value.
func (m model) handleParamStringEdit(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	val := m.paramValues[m.paramEditKey]

	switch msg.String() {
	case "enter", "tab":
		// Accept the edited value
		m.paramEditing = false
	case "esc":
		// Cancel — restore previous value
		m.paramValues[m.paramEditKey] = m.paramEditPrev
		m.paramEditing = false
	case "backspace":
		if m.paramEditCursor > 0 && len(val) > 0 {
			val = val[:m.paramEditCursor-1] + val[m.paramEditCursor:]
			m.paramEditCursor--
		}
	case "left":
		if m.paramEditCursor > 0 {
			m.paramEditCursor--
		}
	case "right":
		if m.paramEditCursor < len(val) {
			m.paramEditCursor++
		}
	default:
		ch := msg.String()
		if len(ch) == 1 && ch[0] >= 32 && ch[0] < 127 {
			val = val[:m.paramEditCursor] + ch + val[m.paramEditCursor:]
			m.paramEditCursor++
		}
	}
	m.paramValues[m.paramEditKey] = val
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
	case "enter":
		// Focus right panel for param editing if current item is selected and has params
		item, paramNames := m.currentItemParams()
		_ = item
		if len(paramNames) > 0 && m.selected[item.key()] {
			m.paramFocused = true
			m.paramCursorIdx = 0
			m.paramEditing = false
		}
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

// paramKey builds the paramValues map key for a template or extension param.
func paramKey(item treeItem, paramName string) string {
	return item.key() + ":" + paramName
}

// currentItemParams returns the ordered param names and the template for the current cursor item.
// Returns nil if the item has no params or is not selected.
func (m *model) currentItemParams() (treeItem, []string) {
	items := m.activeItems()
	cursor := m.cursorPos()
	if cursor < 0 || cursor >= len(items) {
		return treeItem{}, nil
	}
	item := items[cursor]
	if !m.selected[item.key()] {
		// For extensions, also check parent is selected
		if item.kind == kindExtension && !m.selected[item.template.Name] {
			return item, nil
		}
		if item.kind == kindTemplate {
			return item, nil
		}
	}

	var t *tmpl.Template
	if item.kind == kindExtension {
		t = item.extension
	} else {
		t = item.template
	}

	if len(t.Params) == 0 {
		return item, nil
	}

	return item, orderedParamNames(t)
}

// orderedParamNames returns param names in declaration order.
func orderedParamNames(t *tmpl.Template) []string {
	if len(t.ParamOrder) > 0 {
		return t.ParamOrder
	}
	names := make([]string, 0, len(t.Params))
	for name := range t.Params {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
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

			// Append template params as :p1,p2
			item += m.buildParamDSL(t.Name, t)

			var exts []string
			for _, ext := range t.Extensions {
				extKey := t.Name + "/" + ext.Name
				if m.selected[extKey] {
					isAutoSelect := ext.AutoSelect != nil && *ext.AutoSelect
					if !isAutoSelect {
						extDSL := ext.Name + m.buildParamDSL(extKey, ext)
						exts = append(exts, extDSL)
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

// buildParamDSL returns the ":p1,p2" suffix for a template/extension's params.
// Returns "" if all params are at their default values.
func (m model) buildParamDSL(itemKey string, t *tmpl.Template) string {
	if len(t.Params) == 0 {
		return ""
	}
	paramNames := orderedParamNames(t)

	// Collect positional param values
	var vals []string
	allDefault := true
	for _, name := range paramNames {
		pk := itemKey + ":" + name
		val := m.paramValues[pk]
		if val == "" {
			val = t.Params[name].Default
		}
		if val != t.Params[name].Default {
			allDefault = false
		}
		vals = append(vals, val)
	}

	if allDefault {
		return ""
	}

	// Trim trailing default values
	for len(vals) > 0 && vals[len(vals)-1] == t.Params[paramNames[len(vals)-1]].Default {
		vals = vals[:len(vals)-1]
	}

	if len(vals) == 0 {
		return ""
	}

	return ":" + strings.Join(vals, ",")
}
