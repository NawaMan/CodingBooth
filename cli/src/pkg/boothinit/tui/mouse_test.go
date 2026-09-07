// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// A click resolves by arithmetic over the row stack, so these tests are only as
// good as their agreement with the real frame — several of them assert against
// m.View() rather than against the arithmetic alone.

func clickAt(x, y int) tea.MouseMsg {
	return tea.MouseMsg{X: x, Y: y, Action: tea.MouseActionPress, Button: tea.MouseButtonLeft}
}

func wheelAt(x, y int, button tea.MouseButton) tea.MouseMsg {
	return tea.MouseMsg{X: x, Y: y, Action: tea.MouseActionPress, Button: button}
}

// mouseModel builds a model on the Languages tab with the given items, sized so
// that leftWidth is 55 and the content area is 23 rows tall.
func mouseModel(items []treeItem) model {
	m := model{
		width:         100,
		height:        30,
		tabNames:      []string{"Config", "Languages"},
		tabItems:      [][]treeItem{nil, items},
		activeTab:     1,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		selected:      map[string]bool{},
		paramValues:   map[string]string{},
		stringFields:  map[string]string{},
		boolFields:    map[string]bool{},
		cycleIndices:  map[string]int{},
		listFields:    map[string][]string{},
	}
	m.baseline = m.snapshot() // as newModel does, so "changed" means changed here
	return m
}

func templateItem(name string) treeItem {
	return treeItem{kind: kindTemplate, template: &tmpl.Template{Name: name, DisplayName: name}}
}

// goItems builds the go template plus its go-pkg extension (a variadic param) and
// a GO_VERSION cycle param, which is the shape most of these tests click on.
func goItems() []treeItem {
	ext := &tmpl.Template{
		Name:        "go-pkg",
		DisplayName: "go Packages",
		Params:      map[string]tmpl.Param{"GO_PKGS": {Variadic: true}},
		ParamOrder:  []string{"GO_PKGS"},
	}
	parent := &tmpl.Template{
		Name:        "go",
		DisplayName: "Go",
		Params:      map[string]tmpl.Param{"GO_VERSION": {Default: "1.25.7", Suggests: []string{"1.25.7", "1.24.13", "1.23.12"}}},
		ParamOrder:  []string{"GO_VERSION"},
		Extensions:  []*tmpl.Template{ext},
	}
	return []treeItem{
		{kind: kindTemplate, template: parent},
		{kind: kindExtension, template: parent, extension: ext},
	}
}

func click(m model, x, y int) model {
	res, _ := m.Update(clickAt(x, y))
	return res.(model)
}

// The row map is the whole basis of hit-testing, so pin it against the frame the
// renderer actually produces: add a header line and this test fails, rather than
// every click silently landing one row off.
func TestScreenRowsMatchTheRenderedFrame(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go"), templateItem("python"), templateItem("rust")})
	l := m.layout()

	lines := strings.Split(m.View(), "\n")
	if len(lines) != m.height {
		t.Fatalf("frame is %d lines, want the full height %d", len(lines), m.height)
	}
	if !strings.Contains(lines[rowSearch], "Search:") {
		t.Fatalf("row %d should be the search bar: %q", rowSearch, lines[rowSearch])
	}
	if !strings.Contains(lines[rowTabs], "Languages") {
		t.Fatalf("row %d should be the tab bar: %q", rowTabs, lines[rowTabs])
	}
	for i, want := range []string{"go", "python", "rust"} {
		if !strings.Contains(lines[contentTop+i], want) {
			t.Fatalf("content row %d should hold %q: %q", i, want, lines[contentTop+i])
		}
	}
	if !strings.Contains(lines[l.contentBottom()+1], "─") {
		t.Fatalf("row after the content should be the separator: %q", lines[l.contentBottom()+1])
	}
}

func TestClickTabSwitchesTab(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})

	// The Config tab is first; click inside its label.
	cfg := m.tabLabels()[0]
	m = click(m, cfg.start, rowTabs)
	if m.activeTab != 0 {
		t.Fatalf("clicking the Config tab should activate it, tab = %d", m.activeTab)
	}

	// And back, on the last column of the Languages label.
	lang := m.tabLabels()[1]
	m = click(m, lang.start+lang.width-1, rowTabs)
	if m.activeTab != 1 {
		t.Fatalf("clicking the Languages tab should activate it, tab = %d", m.activeTab)
	}

	// The gap between labels belongs to neither tab.
	before := m.activeTab
	m = click(m, lang.start+lang.width, rowTabs)
	if m.activeTab != before {
		t.Fatalf("a click between labels must not switch tabs, tab = %d", m.activeTab)
	}
}

// catalogTabNames is the real category bar. Two-tab fixtures hide the padding
// drift: each tab is two columns wider on screen than an unstyled name, and by
// Tools that error has the first letter of Tools landing on AI Tools.
var catalogTabNames = []string{
	"Config", "Languages", "Middlewares", "Tools", "AI Tools", "IDEs", "Desktop", "Education",
}

func catalogTabModel() model {
	m := mouseModel(nil)
	m.tabNames = catalogTabNames
	m.tabItems = make([][]treeItem, len(catalogTabNames))
	m.tabCursors = make([]int, len(catalogTabNames))
	m.tabScrollOffs = make([]int, len(catalogTabNames))
	return m
}

// The spans a click uses must be the columns the bar actually occupies — padding
// included — not the unstyled names. Assert against View, the same way the
// footer buttons pin their hit boxes to the hint row.
func TestTabHitsMatchTheDrawnBar(t *testing.T) {
	m := catalogTabModel()
	lines := strings.Split(m.View(), "\n")
	bar := stripANSI(lines[rowTabs])

	labels := m.tabLabels()
	if len(labels) != len(catalogTabNames) {
		t.Fatalf("got %d labels, want %d", len(labels), len(catalogTabNames))
	}

	for i, tab := range labels {
		want := stripANSI(tab.rendered(i == m.activeTab))
		got := plainAt(bar, tab.start, tab.start+tab.width-1)
		if got != want {
			t.Fatalf("tab %q: columns %d-%d hold %q, want %q (bar %q)",
				tab.name, tab.start, tab.start+tab.width-1, got, want, bar)
		}

		// First letter of the name, after the style's left padding.
		letter := tab.start + 1
		if runeAt(bar, letter) != string(tab.name[0]) {
			t.Fatalf("tab %q: column %d holds %q, want the first letter %q",
				tab.name, letter, runeAt(bar, letter), string(tab.name[0]))
		}
		clicked := click(m, letter, rowTabs)
		if clicked.activeTab != i {
			t.Fatalf("clicking the %q of %q selected tab %d (%q)",
				string(tab.name[0]), tab.name, clicked.activeTab, catalogTabNames[clicked.activeTab])
		}
	}
}

func TestClickSearchBarFocusesSearch(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	m.searchQuery = "go"

	m = click(m, 20, rowSearch)
	if !m.searchFocused {
		t.Fatal("clicking the search bar should focus it")
	}
	if m.searchCursor != len("go") {
		t.Fatalf("cursor = %d, want the end of the query", m.searchCursor)
	}
}

func TestClickTreeRowMovesCursorWithoutSelecting(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go"), templateItem("python"), templateItem("rust")})

	// Click the description area of the third row — past the checkbox.
	m = click(m, 30, contentTop+2)
	if m.cursorPos() != 2 {
		t.Fatalf("cursor = %d, want 2", m.cursorPos())
	}
	if len(m.selected) != 0 {
		t.Fatalf("a click off the marker must not select: %v", m.selected)
	}

	// A click below the last item changes nothing.
	m = click(m, 30, contentTop+10)
	if m.cursorPos() != 2 {
		t.Fatalf("cursor = %d, want it unchanged past the end of the list", m.cursorPos())
	}
}

func TestClickCheckboxTogglesSelection(t *testing.T) {
	items := goItems()
	m := mouseModel(items)

	// Template marker sits at columns 0-2.
	m = click(m, 1, contentTop)
	if !m.selected["go"] {
		t.Fatalf("clicking the marker should select: %v", m.selected)
	}
	m = click(m, 1, contentTop)
	if m.selected["go"] {
		t.Fatalf("clicking it again should deselect: %v", m.selected)
	}

	// An extension row is indented, so its marker sits at columns 4-6 — and column
	// 1 there is blank, not a marker.
	m = click(m, 1, contentTop+1)
	if m.selected["go/go-pkg"] {
		t.Fatalf("column 1 of an extension row is not its marker: %v", m.selected)
	}
	m = click(m, 5, contentTop+1)
	if !m.selected["go/go-pkg"] {
		t.Fatalf("clicking the extension marker should select it: %v", m.selected)
	}
	if !m.selected["go"] {
		t.Fatalf("selecting an extension should pull in its parent: %v", m.selected)
	}
}

// The marker columns are asserted against the drawn line, so an indent change
// cannot leave the hit test pointing at blank space.
func TestCheckboxColumnsAreWhereTheMarkerIsDrawn(t *testing.T) {
	items := goItems()
	m := mouseModel(items)
	lines := strings.Split(m.View(), "\n")

	for i, item := range items {
		start, end := checkboxCols(item)
		line := lines[contentTop+i]
		if got := plainAt(line, start, end); got != "[ ]" {
			t.Fatalf("row %d: columns %d-%d hold %q, want the marker", i, start, end, got)
		}
	}
}

// plainAt returns columns [start,end] of a rendered line with styling removed.
// Columns, not bytes: the footer hints are full of "│" and "◄►", and a byte slice
// through those reads a column or two off — which is exactly the mistake a hit test
// must not make either.
func plainAt(line string, start, end int) string {
	cols := []rune(stripANSI(line))
	if start < 0 || end >= len(cols) {
		return ""
	}
	return string(cols[start : end+1])
}

func stripANSI(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); {
		if s[i] == 0x1b {
			for i < len(s) && s[i] != 'm' {
				i++
			}
			i++ // skip the 'm'
			continue
		}
		b.WriteByte(s[i])
		i++
	}
	return b.String()
}

func TestClickConfigRowActivatesIt(t *testing.T) {
	m := mouseModel(nil)
	m.activeTab = 0

	rows := m.buildConfigRows()
	// Find the first bool field and the group header above it.
	boolIdx, groupIdx := -1, -1
	for i, r := range rows {
		if r.kind == configRowGroup {
			groupIdx = i
		}
		if r.kind == configRowField && allConfigFields[r.fieldIdx].Kind == fieldKindBool {
			boolIdx = i
			break
		}
	}
	if boolIdx < 0 || groupIdx < 0 {
		t.Skip("config schema has no bool field under a group header")
	}
	key := allConfigFields[rows[boolIdx].fieldIdx].Key

	m = click(m, 5, contentTop+boolIdx)
	if m.cursorPos() != boolIdx {
		t.Fatalf("cursor = %d, want the clicked row %d", m.cursorPos(), boolIdx)
	}
	if !m.boolFields[key] {
		t.Fatalf("clicking a bool field should toggle it: %v", m.boolFields)
	}

	// A group header is not navigable, so clicking one does nothing at all.
	m = click(m, 5, contentTop+groupIdx)
	if m.cursorPos() != boolIdx {
		t.Fatalf("cursor = %d, want it left on %d — group headers are not rows you can land on",
			m.cursorPos(), boolIdx)
	}
}

func configMouseModel() model {
	m := mouseModel(nil)
	m.activeTab = 0
	return m
}

func configFieldRow(m model, key string) (rowIdx int, field configFieldDef, ok bool) {
	for idx, row := range m.buildConfigRows() {
		if row.kind != configRowField {
			continue
		}
		field = allConfigFields[row.fieldIdx]
		if field.Key == key {
			return idx, field, true
		}
	}
	return 0, configFieldDef{}, false
}

func clickConfigField(t *testing.T, m model, key string) (model, int, configFieldDef) {
	t.Helper()
	rowIdx, field, ok := configFieldRow(m, key)
	if !ok {
		t.Fatalf("config field %q not found", key)
	}
	return click(m, 5, contentTop+rowIdx), rowIdx, field
}

func optionLine(panel configDetail, field configFieldDef, want string) (int, bool) {
	for line, optIdx := range panel.optionAt {
		if optIdx >= 0 && optIdx < len(field.Options) && field.Options[optIdx] == want {
			return line, true
		}
	}
	return 0, false
}

// Clicking Variant listed the options in the help pane but did nothing with
// the click — clickRightPanel treated that pane as help-text-only. A click on
// an option is a pick, the same as cycling there and pressing Enter.
func TestClickConfigCycleOptionPicksIt(t *testing.T) {
	m := configMouseModel()
	m, _, field := clickConfigField(t, m, "variant")
	if !m.cycleEditing {
		t.Fatal("clicking Variant should open it for stepping")
	}

	panel := m.renderConfigDetail(m.layout().rightWidth, m.layout().contentH)
	line, ok := optionLine(panel, field, "notebook")
	if !ok {
		t.Fatal("notebook should be a visible option once Variant is being edited")
	}

	m = click(m, m.layout().rightStart()+2, contentTop+line)
	if m.stringFields["variant"] != "notebook" {
		t.Fatalf("variant = %q, want notebook", m.stringFields["variant"])
	}
	if m.cycleEditing {
		t.Fatal("picking an option should commit, not leave the field in cycle-edit")
	}
	wantIdx := -1
	for idx, opt := range field.Options {
		if opt == "notebook" {
			wantIdx = idx
			break
		}
	}
	if m.cycleIndices["variant"] != wantIdx {
		t.Fatalf("cycle index = %d, want %d (notebook)", m.cycleIndices["variant"], wantIdx)
	}
}

// The option map must point at the line the value is drawn on — the same
// agreement paramRowAt keeps with the template detail pane.
func TestConfigCycleOptionMapMatchesTheDrawnRows(t *testing.T) {
	m := configMouseModel()
	m, _, field := clickConfigField(t, m, "variant")

	panel := m.renderConfigDetail(m.layout().rightWidth, m.layout().contentH)
	if len(panel.optionAt) != len(field.Options) {
		t.Fatalf("mapped %d options, want all %d", len(panel.optionAt), len(field.Options))
	}
	for line, optIdx := range panel.optionAt {
		want := variantDisplay(field.Options[optIdx])
		if !strings.Contains(stripANSI(panel.lines[line]), want) {
			t.Fatalf("line %d maps to %q but reads %q", line, want, stripANSI(panel.lines[line]))
		}
	}
}

func TestClickOnConfigHelpDoesNotPickACycleOption(t *testing.T) {
	m := configMouseModel()
	m, _, _ = clickConfigField(t, m, "variant")

	m = click(m, m.layout().rightStart()+2, contentTop) // title, not an option
	if m.stringFields["variant"] != "" {
		t.Fatalf("clicking the help text should not pick a value, got %q", m.stringFields["variant"])
	}
	if !m.cycleEditing {
		t.Fatal("a miss should leave cycle-edit open")
	}
}

func TestClickConfigCycleArrowsStepTheValue(t *testing.T) {
	m := configMouseModel()
	m, rowIdx, field := clickConfigField(t, m, "variant")
	if !m.cycleEditing {
		t.Fatal("clicking Variant should open it for stepping")
	}

	leftCol, rightCol := m.cycleFieldArrowCols(field)
	plain := stripANSI(strings.Split(m.View(), "\n")[contentTop+rowIdx])
	if got := runeAt(plain, leftCol); got != "◄" {
		t.Fatalf("column %d holds %q, want ◄ (line %q)", leftCol, got, plain)
	}
	if got := runeAt(plain, rightCol); got != "►" {
		t.Fatalf("column %d holds %q, want ► (line %q)", rightCol, got, plain)
	}

	m = click(m, rightCol, contentTop+rowIdx)
	if m.stringFields["variant"] != "base" {
		t.Fatalf("clicking ► should step to base, got %q", m.stringFields["variant"])
	}
	if !m.cycleEditing {
		t.Fatal("stepping with the arrows should stay in cycle-edit")
	}

	// The value is shorter now, so the columns move; re-read them.
	leftCol, _ = m.cycleFieldArrowCols(field)
	m = click(m, leftCol, contentTop+rowIdx)
	if m.stringFields["variant"] != "" {
		t.Fatalf("clicking ◄ should step back to default, got %q", m.stringFields["variant"])
	}

	// Config cycle wraps, unlike param suggests. ◄ from the first option is the last.
	leftCol, _ = m.cycleFieldArrowCols(field)
	m = click(m, leftCol, contentTop+rowIdx)
	if m.stringFields["variant"] != "terminal" {
		t.Fatalf("stepping back from default should wrap to terminal, got %q", m.stringFields["variant"])
	}
}

// Variant's help restates every option, then lists them again. On a short
// terminal the list was what fell off the bottom — the rows a mouse needs.
func TestCycleEditKeepsOptionsOnScreen(t *testing.T) {
	m := configMouseModel()
	m.height = 20
	rowIdx, field, ok := configFieldRow(m, "variant")
	if !ok {
		t.Fatal("variant field missing")
	}
	m.setCursor(rowIdx)

	browsing := m.renderConfigDetail(m.layout().rightWidth, m.layout().contentH)
	if _, ok := optionLine(browsing, field, "terminal"); ok {
		t.Fatal("browsing a short terminal should clip the last Variant options — the test needs that clip to exist")
	}

	m.cycleEditing = true
	editing := m.renderConfigDetail(m.layout().rightWidth, m.layout().contentH)
	if len(editing.optionAt) != len(field.Options) {
		t.Fatalf("cycle-edit mapped %d options, want all %d so a click can reach them",
			len(editing.optionAt), len(field.Options))
	}
	if _, ok := optionLine(editing, field, "terminal"); !ok {
		t.Fatal("terminal should stay on screen while Variant is being edited")
	}
}

func TestClickParamRowFocusesAndAddRowStartsEditing(t *testing.T) {
	items := goItems()
	m := mouseModel(items)
	m.setCursor(1) // the go-pkg extension
	m.selected["go"] = true
	m.selected["go/go-pkg"] = true

	// Find the "(+ add)" row on screen through the panel's own map.
	panel := m.renderRightPanel(m.layout().rightWidth, m.layout().contentH)
	addLine := -1
	for line, row := range panel.paramRowAt {
		if m.buildParamRows(items[1], items[1].extension)[row].kind == paramRowVariadicAdd {
			addLine = line
		}
	}
	if addLine < 0 {
		t.Fatal("the panel should be showing an add row")
	}

	m = click(m, m.layout().rightStart()+6, contentTop+addLine)
	if !m.paramFocused {
		t.Fatal("clicking a param row should focus the param editor")
	}
	if !m.variadicEditing || !m.variadicEditIsNew {
		t.Fatalf("clicking the add row should start a new value: editing=%v new=%v",
			m.variadicEditing, m.variadicEditIsNew)
	}

	// Typing then clicking a different row keeps what was typed.
	res, _ := m.Update(pasteMsg("gopls@latest"))
	m = res.(model)
	m = click(m, 30, contentTop) // back to the tree
	if m.paramValues["go/go-pkg:GO_PKGS"] != "gopls@latest" {
		t.Fatalf("clicking away should commit the value, not drop it: %q",
			m.paramValues["go/go-pkg:GO_PKGS"])
	}
	if m.variadicEditing {
		t.Fatal("the edit should have ended")
	}
}

// The param row map must point at the line the value is drawn on.
func TestParamRowMapMatchesTheDrawnRows(t *testing.T) {
	items := goItems()
	m := mouseModel(items)
	m.setCursor(1)
	m.selected["go"] = true
	m.selected["go/go-pkg"] = true
	m.paramFocused = true
	m.paramValues["go/go-pkg:GO_PKGS"] = "gopls@latest,dlv@latest"

	panel := m.renderRightPanel(m.layout().rightWidth, m.layout().contentH)
	for line, row := range panel.paramRowAt {
		want := []string{"gopls@latest", "dlv@latest", "(+ add)"}[row]
		if !strings.Contains(panel.lines[line], want) {
			t.Fatalf("line %d maps to row %d (%q) but reads %q", line, row, want, panel.lines[line])
		}
	}
	if len(panel.paramRowAt) != 3 {
		t.Fatalf("want 3 mapped rows (two values + add), got %d", len(panel.paramRowAt))
	}
}

func TestClickCycleArrowsStepTheValue(t *testing.T) {
	items := goItems()
	m := mouseModel(items)
	m.selected["go"] = true
	m.paramValues["go:GO_VERSION"] = "1.25.7"

	// First click focuses the row — that is when the arrows appear.
	panel := m.renderRightPanel(m.layout().rightWidth, m.layout().contentH)
	var rowLine int
	for line := range panel.paramRowAt {
		rowLine = line
	}
	m = click(m, m.layout().rightStart()+4, contentTop+rowLine)
	if !m.paramFocused {
		t.Fatal("clicking the row should focus it")
	}

	// The arrow columns must be where the arrows are drawn.
	panel = m.renderRightPanel(m.layout().rightWidth, m.layout().contentH)
	for line, row := range panel.paramRowAt {
		if row == 0 {
			rowLine = line
		}
	}
	leftCol, rightCol := m.cycleArrowCols(items[0].template, "GO_VERSION", "go:GO_VERSION")
	plain := stripANSI(panel.lines[rowLine])
	if got := runeAt(plain, leftCol); got != "◄" {
		t.Fatalf("column %d holds %q, want ◄ (line %q)", leftCol, got, plain)
	}
	if got := runeAt(plain, rightCol); got != "►" {
		t.Fatalf("column %d holds %q, want ► (line %q)", rightCol, got, plain)
	}

	m = click(m, m.layout().rightStart()+rightCol, contentTop+rowLine)
	if m.paramValues["go:GO_VERSION"] != "1.24.13" {
		t.Fatalf("clicking ► should step to the next suggest, got %q", m.paramValues["go:GO_VERSION"])
	}
	m = click(m, m.layout().rightStart()+leftCol, contentTop+rowLine)
	if m.paramValues["go:GO_VERSION"] != "1.25.7" {
		t.Fatalf("clicking ◄ should step back, got %q", m.paramValues["go:GO_VERSION"])
	}

	// ◄ at the first suggest does not wrap, exactly as the arrow keys refuse to.
	m = click(m, m.layout().rightStart()+leftCol, contentTop+rowLine)
	if m.paramValues["go:GO_VERSION"] != "1.25.7" {
		t.Fatalf("stepping back from the first suggest should stay put, got %q", m.paramValues["go:GO_VERSION"])
	}
}

// runeAt returns the rune occupying visual column col of a plain string.
func runeAt(plain string, col int) string {
	i := 0
	for _, r := range plain {
		if i == col {
			return string(r)
		}
		i++
	}
	return ""
}

func TestWheelScrollsTheListAndKeepsTheCursorVisible(t *testing.T) {
	var items []treeItem
	for _, n := range []string{"a", "b", "c", "d", "e", "f", "g", "h"} {
		items = append(items, templateItem(n))
	}
	m := mouseModel(items)
	m.height = 12 // contentH = 5, so the list scrolls

	res, _ := m.Update(wheelAt(10, contentTop+1, tea.MouseButtonWheelDown))
	m = res.(model)
	if m.scrollOffset() != wheelStep {
		t.Fatalf("offset = %d, want one notch (%d)", m.scrollOffset(), wheelStep)
	}
	if m.cursorPos() < m.scrollOffset() {
		t.Fatalf("cursor %d scrolled out of view (offset %d)", m.cursorPos(), m.scrollOffset())
	}

	// Scrolling back up stops at the top rather than going negative.
	for range 5 {
		res, _ = m.Update(wheelAt(10, contentTop+1, tea.MouseButtonWheelUp))
		m = res.(model)
	}
	if m.scrollOffset() != 0 {
		t.Fatalf("offset = %d, want 0 at the top of the list", m.scrollOffset())
	}

	// A wheel event outside the content area is ignored.
	before := m.scrollOffset()
	res, _ = m.Update(wheelAt(10, rowTabs, tea.MouseButtonWheelDown))
	m = res.(model)
	if m.scrollOffset() != before {
		t.Fatalf("wheel on the tab bar should not scroll the list, offset = %d", m.scrollOffset())
	}
}

func TestWheelWalksFocusedParamRows(t *testing.T) {
	items := goItems()
	m := mouseModel(items)
	m.setCursor(1)
	m.selected["go"] = true
	m.selected["go/go-pkg"] = true
	m.paramFocused = true
	m.paramValues["go/go-pkg:GO_PKGS"] = "gopls@latest,dlv@latest"

	res, _ := m.Update(wheelAt(m.layout().rightStart()+2, contentTop+1, tea.MouseButtonWheelDown))
	m = res.(model)
	if m.paramCursorIdx != 1 {
		t.Fatalf("param cursor = %d, want 1", m.paramCursorIdx)
	}
	// Three rows (two values + add), so it stops at index 2.
	for range 4 {
		res, _ = m.Update(wheelAt(m.layout().rightStart()+2, contentTop+1, tea.MouseButtonWheelDown))
		m = res.(model)
	}
	if m.paramCursorIdx != 2 {
		t.Fatalf("param cursor = %d, want it clamped to the last row (2)", m.paramCursorIdx)
	}
}

func TestDialogsGuardAgainstClicks(t *testing.T) {
	// The warning is informational: a click dismisses it.
	m := mouseModel([]treeItem{templateItem("go")})
	m.warningDialog = true
	m = click(m, 10, 10)
	if m.warningDialog {
		t.Fatal("a click should dismiss the warning dialog")
	}

	// The overwrite dialog must be typed through, so clicks do nothing.
	m = mouseModel([]treeItem{templateItem("go")})
	m.overwriteDialog = true
	m = click(m, 10, 10)
	if !m.overwriteDialog || m.confirmed {
		t.Fatalf("clicks must not answer the overwrite dialog: open=%v confirmed=%v",
			m.overwriteDialog, m.confirmed)
	}

	// Same for the quit prompt.
	m = mouseModel([]treeItem{templateItem("go")})
	m.quitting = true
	m = click(m, 10, 10)
	if !m.quitting {
		t.Fatal("clicks must not answer the quit prompt")
	}
}

func TestReleaseAndMotionAreIgnored(t *testing.T) {
	items := goItems()
	m := mouseModel(items)

	for _, msg := range []tea.MouseMsg{
		{X: 1, Y: contentTop, Action: tea.MouseActionRelease, Button: tea.MouseButtonLeft},
		{X: 1, Y: contentTop, Action: tea.MouseActionMotion, Button: tea.MouseButtonLeft},
		{X: 1, Y: contentTop, Action: tea.MouseActionPress, Button: tea.MouseButtonRight},
	} {
		res, _ := m.Update(msg)
		got := res.(model)
		if len(got.selected) != 0 {
			t.Fatalf("%v should not select anything: %v", msg.Action, got.selected)
		}
	}
}

// A model that has not been sized yet must not be hit-tested — every column and
// row would be computed from a zero width.
func TestClickBeforeFirstResizeIsIgnored(t *testing.T) {
	m := mouseModel(goItems())
	m.width, m.height = 0, 0

	m = click(m, 1, contentTop)
	if len(m.selected) != 0 {
		t.Fatalf("a click before the first WindowSizeMsg should do nothing: %v", m.selected)
	}
}

// The buttons are drawn from footerButtons and clicked through it, so assert both
// halves: the labels land on the hint row where the spans say they do.
func TestFooterButtonsAreDrawnWhereTheyAreClicked(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	l := m.layout()

	lines := strings.Split(m.View(), "\n")
	hints := stripANSI(lines[l.rowFooterHints()])

	buttons := m.footerButtons()
	if len(buttons) != 2 {
		t.Fatalf("want Save and Cancel, got %d buttons", len(buttons))
	}
	for _, b := range buttons {
		if got := plainAt(hints, b.start, b.start+b.width-1); got != b.label {
			t.Fatalf("columns %d-%d hold %q, want %q", b.start, b.start+b.width-1, got, b.label)
		}
	}
	// Flush right, with a single column of margin.
	last := buttons[len(buttons)-1]
	if last.start+last.width != m.width-1 {
		t.Fatalf("buttons end at column %d, want the width less one (%d)", last.start+last.width, m.width-1)
	}
}

// Cancel asks first when there is something to lose, and the answer must be
// reachable with the same mouse that asked.
func TestCancelButtonConfirmsBeforeQuitting(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	l := m.layout()
	m = click(m, 1, contentTop) // select something, so cancelling has stakes
	cancel := m.footerButtons()[1]

	res, cmd := m.Update(clickAt(cancel.start+1, l.rowFooterHints()))
	m = res.(model)
	if !m.quitting {
		t.Fatal("Cancel should raise the confirmation, not quit")
	}
	if cmd != nil {
		t.Fatal("Cancel must not quit before it is confirmed")
	}
	if m.notification != quitPromptMessage {
		t.Fatalf("notification = %q, want the quit prompt", m.notification)
	}

	// The pair becomes Discard / Back while the question stands.
	buttons := m.footerButtons()
	if len(buttons) != 2 || buttons[0].action != buttonDiscard || buttons[1].action != buttonKeepEditing {
		t.Fatalf("confirmation should offer Discard and Back, got %+v", buttons)
	}

	// Back returns to the configuration untouched.
	res, cmd = m.Update(clickAt(buttons[1].start+1, l.rowFooterHints()))
	back := res.(model)
	if back.quitting || cmd != nil {
		t.Fatalf("Back should cancel the quit: quitting=%v cmd=%v", back.quitting, cmd)
	}
	if back.notification != "" {
		t.Fatalf("Back should clear the prompt, got %q", back.notification)
	}

	// Discard leaves — and leaves unconfirmed, so nothing is written.
	res, cmd = m.Update(clickAt(buttons[0].start+1, l.rowFooterHints()))
	gone := res.(model)
	if cmd == nil {
		t.Fatal("Discard should quit")
	}
	if gone.confirmed {
		t.Fatal("quitting must not count as confirming a save")
	}
}

// While the question stands, only its own two buttons may answer it.
func TestClicksElsewhereCannotAnswerTheConfirmation(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	l := m.layout()
	m.quitting = true

	for _, at := range []struct {
		what string
		x, y int
	}{
		{"a template row", 1, contentTop},
		{"the tab bar", 1, rowTabs},
		{"the search bar", 10, rowSearch},
		{"empty space on the hint row", 0, l.rowFooterHints()},
	} {
		res, cmd := m.Update(clickAt(at.x, at.y))
		got := res.(model)
		if !got.quitting || cmd != nil {
			t.Fatalf("clicking %s should not answer the confirmation: quitting=%v cmd=%v",
				at.what, got.quitting, cmd)
		}
		if len(got.selected) != 0 {
			t.Fatalf("clicking %s should not reach the tree: %v", at.what, got.selected)
		}
	}
}

func TestSaveButtonSaves(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	l := m.layout()
	m.selected["go"] = true
	save := m.footerButtons()[0]

	res, cmd := m.Update(clickAt(save.start+1, l.rowFooterHints()))
	m = res.(model)
	if !m.confirmed || cmd == nil {
		t.Fatalf("Save should confirm and quit: confirmed=%v cmd=%v", m.confirmed, cmd)
	}
}

// On a booth holding hand-written files, Save has to route through the typed
// confirmation exactly as Ctrl+S does — a button must not become a way around it.
func TestSaveButtonRespectsTheOverwriteGuard(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	l := m.layout()
	m.drifted = []string{".booth/Boothfile"}
	save := m.footerButtons()[0]

	res, cmd := m.Update(clickAt(save.start+1, l.rowFooterHints()))
	m = res.(model)
	if !m.overwriteDialog {
		t.Fatal("Save should open the overwrite dialog on a drifted booth")
	}
	if m.confirmed || cmd != nil {
		t.Fatalf("nothing may be written yet: confirmed=%v cmd=%v", m.confirmed, cmd)
	}

	// And that dialog stays keyboard-only.
	res, cmd = m.Update(clickAt(save.start+1, l.rowFooterHints()))
	still := res.(model)
	if !still.overwriteDialog || still.confirmed || cmd != nil {
		t.Fatalf("clicks must not answer the overwrite dialog: open=%v confirmed=%v",
			still.overwriteDialog, still.confirmed)
	}
}

// Clicking Save while a value is being typed keeps it, rather than saving the
// half-finished state that was on screen before the edit.
func TestSaveButtonCommitsAnEditFirst(t *testing.T) {
	items := goItems()
	m := mouseModel(items)
	l := m.layout()
	m.setCursor(1)
	m.selected["go"] = true
	m.selected["go/go-pkg"] = true
	m.paramFocused = true
	m.beginVariadicEdit("go/go-pkg:GO_PKGS", 0, "gopls@latest", true)

	save := m.footerButtons()[0]
	res, _ := m.Update(clickAt(save.start+1, l.rowFooterHints()))
	m = res.(model)
	if got := m.paramValues["go/go-pkg:GO_PKGS"]; got != "gopls@latest" {
		t.Fatalf("value = %q, want the in-progress edit committed", got)
	}
}

// A terminal too narrow for the buttons must not have them drawn in the wrong
// place; the keys still work.
func TestButtonsAreDroppedOnANarrowTerminal(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	m.width = 20

	if got := m.footerButtons(); got != nil {
		t.Fatalf("want no buttons at width 20, got %+v", got)
	}
	// And the hint row still renders, just without them.
	lines := strings.Split(m.View(), "\n")
	if strings.Contains(lines[m.layout().rowFooterHints()], "Save") {
		t.Fatalf("no button should be drawn: %q", lines[m.layout().rowFooterHints()])
	}
}

// The hints give way to the buttons rather than overrunning them.
func TestHintsAreTruncatedRatherThanCollidingWithButtons(t *testing.T) {
	m := mouseModel([]treeItem{templateItem("go")})
	m.width = 60
	l := m.layout()

	lines := strings.Split(m.View(), "\n")
	hints := stripANSI(lines[l.rowFooterHints()])
	if len([]rune(hints)) > m.width {
		t.Fatalf("hint row is %d columns wide, want at most %d: %q", len([]rune(hints)), m.width, hints)
	}
	for _, b := range m.footerButtons() {
		if got := plainAt(hints, b.start, b.start+b.width-1); got != b.label {
			t.Fatalf("button %q was overrun by the hints: columns hold %q", b.label, got)
		}
	}
}
