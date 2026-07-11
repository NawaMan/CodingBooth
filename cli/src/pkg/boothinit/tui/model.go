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
	kindTemplate itemKind = iota
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

	// Overwrite confirmation — saving regenerates .booth/ files from scratch, so
	// when any of them hold hand-written content (drifted, from output.Drifted)
	// Ctrl+S opens a dialog that will not save until the user types
	// overwriteConfirmWord. Destroying someone's work should take more than a
	// reflex keystroke.
	drifted         []string
	overwriteDialog bool
	overwriteInput  string

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
	cycleEditing bool                // true when editing a cycle field (Variant, Sudo)
	cyclePrevIdx int                 // previous cycle index (for ESC cancel)

	// Template/extension parameter values
	// Key format: "templateName:PARAM_NAME" or "templateName/extName:PARAM_NAME"
	paramValues     map[string]string
	paramFocused    bool   // true when right panel param fields have focus
	paramEditing    bool   // true when editing a param string value
	paramEditKey    string // which param is being edited (full key)
	paramEditCursor int    // cursor position in edited string
	paramEditPrev   string // previous value before editing (for ESC cancel)
	paramCursorIdx  int    // which param row in right panel has focus (index into buildParamRows)

	// Variadic (multi-value) param editing — a single value of a variadic
	// param edited as one row in the right panel's multi-row list.
	variadicEditing   bool   // true when editing one value of a variadic param
	variadicEditKey   string // paramValues key of the variadic param being edited
	variadicEditIdx   int    // index of the value within the variadic list
	variadicEditBuf   string // in-progress text for the value being edited
	variadicEditCur   int    // cursor position within variadicEditBuf
	variadicEditIsNew bool   // true when adding a new value (ESC discards it)
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

	// No string-field defaults: an unset port (and other unset string fields)
	// must round-trip as "absent in config.toml" so booth picks the runtime
	// default. Seeding "10000" here would write port = "10000" to config.toml
	// even when the user didn't choose it.

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

		// Overwrite confirmation — blocks saving until the word is typed in full
		if m.overwriteDialog {
			return m.handleOverwriteConfirm(msg)
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

		// Variadic value editing mode (right panel multi-row list)
		if m.variadicEditing {
			return m.handleVariadicEdit(msg)
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

		// Cycle field editing mode (config tab)
		if m.cycleEditing {
			return m.handleCycleEdit(msg)
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
			return m.requestSave()

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
		return m.requestSave()

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
				m.cycleEditing = true
				m.cyclePrevIdx = m.cycleIndices[f.Key]
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

func (m model) handleCycleEdit(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	f := m.currentConfigField()
	if f == nil || f.Kind != fieldKindCycle {
		m.cycleEditing = false
		return m, nil
	}
	switch msg.String() {
	case "enter":
		m.cycleEditing = false
	case "esc":
		m.cycleIndices[f.Key] = m.cyclePrevIdx
		m.stringFields[f.Key] = f.Options[m.cyclePrevIdx]
		m.cycleEditing = false
	case "right", " ", "down":
		idx := (m.cycleIndices[f.Key] + 1) % len(f.Options)
		m.cycleIndices[f.Key] = idx
		m.stringFields[f.Key] = f.Options[idx]
	case "left", "up":
		idx := m.cycleIndices[f.Key] - 1
		if idx < 0 {
			idx = len(f.Options) - 1
		}
		m.cycleIndices[f.Key] = idx
		m.stringFields[f.Key] = f.Options[idx]
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

	rows := m.buildParamRows(item, t)
	if m.paramCursorIdx >= len(rows) {
		m.paramCursorIdx = len(rows) - 1
	}
	if m.paramCursorIdx < 0 {
		m.paramCursorIdx = 0
	}
	row := rows[m.paramCursorIdx]

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
		return m.requestSave()

	case "up":
		if m.paramCursorIdx > 0 {
			m.paramCursorIdx--
		}
		return m, nil

	case "down":
		if m.paramCursorIdx < len(rows)-1 {
			m.paramCursorIdx++
		}
		return m, nil

	case "backspace", "delete":
		// Remove a value from a variadic list.
		if row.kind == paramRowVariadicValue {
			pk := paramKey(item, row.param)
			vals := m.splitVariadic(pk)
			if row.valueIdx < len(vals) {
				vals = append(vals[:row.valueIdx], vals[row.valueIdx+1:]...)
				m.joinVariadic(pk, vals)
			}
			// Clamp cursor to the new row count.
			newRows := m.buildParamRows(item, t)
			if m.paramCursorIdx >= len(newRows) {
				m.paramCursorIdx = len(newRows) - 1
			}
		}
		return m, nil

	case "left", "right":
		if row.kind != paramRowField {
			return m, nil
		}
		p := t.Params[row.param]
		pk := paramKey(item, row.param)
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
		switch row.kind {
		case paramRowField:
			pk := paramKey(item, row.param)
			m.paramEditing = true
			m.paramEditKey = pk
			m.paramEditCursor = len(m.paramValues[pk])
			m.paramEditPrev = m.paramValues[pk]
		case paramRowVariadicValue:
			pk := paramKey(item, row.param)
			vals := m.splitVariadic(pk)
			m.beginVariadicEdit(pk, row.valueIdx, vals[row.valueIdx], false)
		case paramRowVariadicAdd:
			pk := paramKey(item, row.param)
			m.beginVariadicEdit(pk, len(m.splitVariadic(pk)), "", true)
		}
		return m, nil

	default:
		// Any printable key starts editing the current row.
		ch := msg.String()
		if len(ch) != 1 || ch[0] < 32 || ch[0] >= 127 {
			return m, nil
		}
		switch row.kind {
		case paramRowField:
			pk := paramKey(item, row.param)
			m.paramEditPrev = m.paramValues[pk]
			m.paramEditing = true
			m.paramEditKey = pk
			m.paramValues[pk] = ch
			m.paramEditCursor = 1
		case paramRowVariadicValue:
			pk := paramKey(item, row.param)
			vals := m.splitVariadic(pk)
			m.beginVariadicEdit(pk, row.valueIdx, vals[row.valueIdx], false)
			m.variadicEditBuf = ch
			m.variadicEditCur = 1
		case paramRowVariadicAdd:
			pk := paramKey(item, row.param)
			m.beginVariadicEdit(pk, len(m.splitVariadic(pk)), "", true)
			m.variadicEditBuf = ch
			m.variadicEditCur = 1
		}
		return m, nil
	}
}

// currentParamRow returns the focused row in the right-panel param editor.
func (m *model) currentParamRow() (paramRow, bool) {
	item, paramNames := m.currentItemParams()
	if len(paramNames) == 0 {
		return paramRow{}, false
	}
	var t *tmpl.Template
	if item.kind == kindExtension {
		t = item.extension
	} else {
		t = item.template
	}
	rows := m.buildParamRows(item, t)
	if m.paramCursorIdx < 0 || m.paramCursorIdx >= len(rows) {
		return paramRow{}, false
	}
	return rows[m.paramCursorIdx], true
}

// beginVariadicEdit puts the model into single-value edit mode for a variadic
// param. isNew marks an add (ESC discards rather than reverting).
func (m *model) beginVariadicEdit(pk string, idx int, val string, isNew bool) {
	m.variadicEditing = true
	m.variadicEditKey = pk
	m.variadicEditIdx = idx
	m.variadicEditBuf = val
	m.variadicEditCur = len(val)
	m.variadicEditIsNew = isNew
}

// handleVariadicEdit handles typing when editing one value of a variadic param.
func (m model) handleVariadicEdit(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "enter", "tab":
		m.commitVariadicEdit()
	case "esc":
		// Discard the in-progress edit (a new value is simply dropped).
		m.endVariadicEdit()
	case "ctrl+s":
		m.commitVariadicEdit()
		return m.requestSave()
	case "backspace":
		if m.variadicEditCur > 0 && len(m.variadicEditBuf) > 0 {
			m.variadicEditBuf = m.variadicEditBuf[:m.variadicEditCur-1] + m.variadicEditBuf[m.variadicEditCur:]
			m.variadicEditCur--
		}
	case "left":
		if m.variadicEditCur > 0 {
			m.variadicEditCur--
		}
	case "right":
		if m.variadicEditCur < len(m.variadicEditBuf) {
			m.variadicEditCur++
		}
	default:
		ch := msg.String()
		if len(ch) == 1 && ch[0] >= 32 && ch[0] < 127 {
			m.variadicEditBuf = m.variadicEditBuf[:m.variadicEditCur] + ch + m.variadicEditBuf[m.variadicEditCur:]
			m.variadicEditCur++
		}
	}
	return m, nil
}

// commitVariadicEdit writes the edited value back into the variadic list and
// leaves edit mode, positioning the cursor on the committed value.
func (m *model) commitVariadicEdit() {
	pk := m.variadicEditKey
	wasNew := m.variadicEditIsNew
	vals := m.splitVariadic(pk)
	val := strings.TrimSpace(m.variadicEditBuf)
	if wasNew {
		if val != "" {
			vals = append(vals, val)
		}
	} else if m.variadicEditIdx < len(vals) {
		vals[m.variadicEditIdx] = val // blanks are dropped by joinVariadic
	}
	m.joinVariadic(pk, vals)
	if wasNew {
		// Land back on the trailing "(+ add)" row so the user can keep adding.
		m.paramCursorIdx = len(m.splitVariadic(pk))
	}
	m.endVariadicEdit()
}

// endVariadicEdit clears the variadic edit state.
func (m *model) endVariadicEdit() {
	m.variadicEditing = false
	m.variadicEditKey = ""
	m.variadicEditIdx = -1
	m.variadicEditBuf = ""
	m.variadicEditCur = 0
	m.variadicEditIsNew = false
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

// paramRowKind identifies a navigable row in the right-panel param editor.
type paramRowKind int

const (
	paramRowField         paramRowKind = iota // a single-value param (cycle or string)
	paramRowVariadicValue                     // one value of a variadic param
	paramRowVariadicAdd                       // the "(+ add)" pseudo-row for a variadic param
)

// paramRow is one navigable row in the right-panel param editor. A normal
// param is a single field row; a variadic param expands into one value row per
// entry plus a trailing add row (mirroring the Config tab's list fields).
type paramRow struct {
	kind     paramRowKind
	param    string // param name
	valueIdx int    // index into the variadic value list (paramRowVariadicValue)
}

// buildParamRows expands a selected item's params into navigable rows. The
// cursor (paramCursorIdx) indexes into the returned slice.
func (m *model) buildParamRows(item treeItem, t *tmpl.Template) []paramRow {
	var rows []paramRow
	for _, name := range orderedParamNames(t) {
		if t.Params[name].Variadic {
			pk := paramKey(item, name)
			vals := m.splitVariadic(pk)
			for i := range vals {
				rows = append(rows, paramRow{kind: paramRowVariadicValue, param: name, valueIdx: i})
			}
			rows = append(rows, paramRow{kind: paramRowVariadicAdd, param: name})
		} else {
			rows = append(rows, paramRow{kind: paramRowField, param: name})
		}
	}
	return rows
}

// splitVariadic returns the committed values of a variadic param, parsed from
// its comma-joined storage. Blank entries are dropped.
func (m *model) splitVariadic(pk string) []string {
	raw := m.paramValues[pk]
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	var out []string
	for _, p := range strings.Split(raw, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// joinVariadic writes a variadic param's values back to comma-joined storage,
// dropping blanks. An empty list removes the key so it round-trips as default.
func (m *model) joinVariadic(pk string, vals []string) {
	clean := make([]string, 0, len(vals))
	for _, v := range vals {
		if v = strings.TrimSpace(v); v != "" {
			clean = append(clean, v)
		}
	}
	if len(clean) == 0 {
		delete(m.paramValues, pk)
		return
	}
	m.paramValues[pk] = strings.Join(clean, ",")
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
					extDSL := ext.Name + m.buildParamDSL(extKey, ext)
					exts = append(exts, extDSL)
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

// overwriteConfirmWord is what the user must type to save over hand-written
// content. Deliberately not "y" or "yes" — a reflex keystroke is exactly what
// this dialog exists to prevent.
const overwriteConfirmWord = "overwrite"

// requestSave handles Ctrl+S from every mode. Saving regenerates .booth/ files
// from scratch, so when any of them hold hand-written content it routes through
// the typed confirmation instead of quitting straight into the write.
func (m model) requestSave() (tea.Model, tea.Cmd) {
	if len(m.drifted) > 0 {
		m.overwriteDialog = true
		m.overwriteInput = ""
		return m, nil
	}
	m.confirmed = true
	return m, tea.Quit
}

// handleOverwriteConfirm drives the typed confirmation. Enter only saves once the
// word matches exactly; anything else keeps the dialog up, and Esc backs out with
// the configuration untouched.
func (m model) handleOverwriteConfirm(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch msg.String() {
	case "esc":
		m.overwriteDialog = false
		m.overwriteInput = ""
		return m, nil

	case "enter":
		if m.overwriteInput == overwriteConfirmWord {
			m.confirmed = true
			return m, tea.Quit
		}
		return m, nil

	case "backspace":
		if len(m.overwriteInput) > 0 {
			m.overwriteInput = m.overwriteInput[:len(m.overwriteInput)-1]
		}
		return m, nil

	case "ctrl+c", "ctrl+e":
		// Quit without saving — the files stay as the user wrote them.
		return m, tea.Quit
	}

	if msg.Type == tea.KeyRunes {
		m.overwriteInput += string(msg.Runes)
	}
	return m, nil
}
