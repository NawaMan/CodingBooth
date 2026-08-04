// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// The screen is a fixed stack of rows, so a click resolves to a widget by
// arithmetic rather than by bookkeeping:
//
//	0                 header (title, selection count, scroll position)
//	1                 search bar
//	2                 tab bar
//	3                 separator
//	4 … 4+contentH-1  content: left panel, " │ ", right panel
//	4+contentH        separator
//	5+contentH        footer message
//	6+contentH        footer key hints
//
// contentHeight() subtracts exactly those seven rows, which is what keeps this
// map and the rendering in agreement. Everything below derives from it, and both
// View and the mouse handler go through layout() so neither can drift.

const (
	rowSearch  = 1
	rowTabs    = 2
	contentTop = 4
)

// layout holds the panel geometry for the current terminal size.
type layout struct {
	fullWidth  int
	leftWidth  int
	rightWidth int
	contentH   int
}

func (m model) layout() layout {
	full := m.width
	left := full * 55 / 100
	if left < 30 {
		left = 30
	}
	right := full - left - 3
	if right < 20 {
		right = 20
	}
	return layout{fullWidth: full, leftWidth: left, rightWidth: right, contentH: m.contentHeight()}
}

// contentBottom is the last screen row of the content panels.
func (l layout) contentBottom() int { return contentTop + l.contentH - 1 }

// rowFooterHints is the screen row carrying the key hints and the footer buttons:
// past the content, its separator and the message line.
func (l layout) rowFooterHints() int { return contentTop + l.contentH + 2 }

// buttonAction is what a footer button does when clicked.
type buttonAction int

const (
	buttonSave buttonAction = iota
	buttonCancel
	buttonDiscard     // confirming a cancel
	buttonKeepEditing // backing out of one
)

// footerButton is a clickable button on the footer's hint row.
type footerButton struct {
	label  string
	action buttonAction
	start  int
	width  int
}

func (b footerButton) style() lipgloss.Style {
	switch b.action {
	case buttonSave:
		return saveButtonStyle
	case buttonDiscard:
		return discardButtonStyle
	default:
		return cancelButtonStyle
	}
}

// footerButtons returns the buttons flush against the right of the hint row.
//
// Cancel asks before it acts, and it asks *here*: the pair becomes Discard and
// Back, so the confirmation is answerable by the same mouse that asked for it
// rather than sending the user to the keyboard mid-gesture. Each label carries its
// key, since the buttons replaced the hints that used to name them.
//
// renderFooter draws from this, and a click is hit-tested against it.
func (m model) footerButtons() []footerButton {
	labels := []footerButton{
		{label: "[ Save (Ctrl+S) ]", action: buttonSave},
		{label: "[ Cancel (Ctrl+E) ]", action: buttonCancel},
	}
	if m.quitting {
		labels = []footerButton{
			{label: "[ Discard (ENTER) ]", action: buttonDiscard},
			{label: "[ Back (ESC) ]", action: buttonKeepEditing},
		}
	}

	const gap = 2
	total := gap * (len(labels) - 1)
	for i := range labels {
		labels[i].width = lipgloss.Width(labels[i].label)
		total += labels[i].width
	}

	// One column of margin on the right. Too narrow to place them is not a reason
	// to draw them somewhere wrong — the keys still work.
	col := m.layout().fullWidth - total - 1
	if col < 1 {
		return nil
	}
	for i := range labels {
		labels[i].start = col
		col += labels[i].width + gap
	}
	return labels
}

// clickFooterButton runs the button at column x, if any.
func (m model) clickFooterButton(x int) (tea.Model, tea.Cmd) {
	for _, b := range m.footerButtons() {
		if x < b.start || x >= b.start+b.width {
			continue
		}
		switch b.action {
		case buttonSave:
			m.commitActiveEdit()
			return m.requestSave()
		case buttonCancel:
			return m.requestCancel()
		case buttonDiscard:
			return m, tea.Quit
		case buttonKeepEditing:
			m.quitting = false
			m.notification = ""
		}
		return m, nil
	}
	return m, nil
}

// rightStart is the first column of the right panel, past the " │ " divider.
func (l layout) rightStart() int { return l.leftWidth + 3 }

// tabLabel is one entry of the tab bar and the columns it occupies.
type tabLabel struct {
	name    string
	starred bool // the search matched something on this tab
	start   int
	width   int
}

// plain returns the label as it is measured: the name plus its one-column
// suffix, which is "*" when the search matched this tab and a space otherwise.
func (t tabLabel) plain() string {
	if t.starred {
		return t.name + "*"
	}
	return t.name + " "
}

// tabLabels returns the tab bar as label plus column span. renderTabBar draws
// from this and the mouse handler hit-tests against it, so a click cannot land
// on a tab the bar is not drawing there.
func (m model) tabLabels() []tabLabel {
	labels := make([]tabLabel, 0, len(m.tabNames))
	col := 1 // renderTabBar opens with a single leading space
	for i, name := range m.tabNames {
		starred := false
		if m.searchQuery != "" && i > 0 && m.tabItems[i] != nil {
			mp := &m
			starred = len(mp.filterItems(m.tabItems[i])) > 0
		}
		t := tabLabel{name: name, starred: starred, start: col}
		t.width = lipgloss.Width(t.plain())
		labels = append(labels, t)
		col += t.width + 1 // tabs are joined with a space
	}
	return labels
}

// tabAt returns the tab index at column x of the tab bar, or -1.
func (m model) tabAt(x int) int {
	for i, t := range m.tabLabels() {
		if x >= t.start && x < t.start+t.width {
			return i
		}
	}
	return -1
}

// checkboxCols returns the columns of the "[ ]" marker on a tree row. An
// extension row is indented four columns; clicking the marker is how a mouse
// says Space, so it has to be the marker and not the whole row.
func checkboxCols(item treeItem) (start, end int) {
	if item.kind == kindExtension {
		return 4, 6
	}
	return 0, 2
}

// handleMouse routes a mouse event to the widget under the pointer.
//
// Only a left press and the wheel do anything: releases would double-handle every
// click, and motion is a drag, which this TUI has nothing to do with.
func (m model) handleMouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	if m.width == 0 || m.height == 0 {
		return m, nil
	}

	leftPress := msg.Action == tea.MouseActionPress && msg.Button == tea.MouseButtonLeft

	// The overwrite dialog must be typed through in full: it exists so that
	// destroying hand-written files costs more than a reflex, and a click is a
	// reflex.
	if m.overwriteDialog {
		return m, nil
	}
	// The cancel confirmation is answerable by mouse, but only on its own two
	// buttons — a click anywhere else must not discard a configuration.
	if m.quitting {
		if leftPress && msg.Y == m.layout().rowFooterHints() {
			return m.clickFooterButton(msg.X)
		}
		return m, nil
	}
	if m.warningDialog {
		if leftPress {
			m.warningDialog = false
		}
		return m, nil
	}

	if msg.Action == tea.MouseActionPress {
		switch msg.Button {
		case tea.MouseButtonWheelUp:
			return m.handleWheel(msg, -wheelStep)
		case tea.MouseButtonWheelDown:
			return m.handleWheel(msg, wheelStep)
		case tea.MouseButtonLeft:
			return m.handleClick(msg)
		}
	}
	return m, nil
}

// wheelStep is how many rows one wheel notch moves.
const wheelStep = 3

func (m model) handleClick(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	l := m.layout()

	switch {
	case msg.Y == rowSearch:
		m.commitActiveEdit()
		m.searchFocused = true
		m.paramFocused = false
		m.searchCursor = len(m.searchQuery)
		return m, nil

	case msg.Y == rowTabs:
		idx := m.tabAt(msg.X)
		if idx < 0 || idx == m.activeTab {
			return m, nil
		}
		m.commitActiveEdit()
		m.searchFocused = false
		m.paramFocused = false
		m.activeTab = idx
		return m, nil

	case msg.Y >= contentTop && msg.Y <= l.contentBottom():
		if msg.X < l.leftWidth {
			return m.clickLeftPanel(msg.Y-contentTop, msg.X)
		}
		if msg.X >= l.rightStart() {
			return m.clickRightPanel(msg.Y-contentTop, msg.X-l.rightStart())
		}

	case msg.Y == l.rowFooterHints():
		return m.clickFooterButton(msg.X)
	}
	return m, nil
}

// clickLeftPanel resolves a click on visible line `line` of the left panel.
// Both panels render exactly one line per row, so the row is the scroll offset
// plus the line.
func (m model) clickLeftPanel(line, x int) (tea.Model, tea.Cmd) {
	m.commitActiveEdit()
	m.searchFocused = false
	m.paramFocused = false

	if m.isConfigTab() {
		rows := m.buildConfigRows()
		idx := m.tabScrollOffs[0] + line
		if idx < 0 || idx >= len(rows) {
			return m, nil
		}
		// Group headers are not navigable — the keyboard skips over them.
		if rows[idx].kind == configRowGroup {
			return m, nil
		}
		m.setCursor(idx)
		m.activateConfigRow(rows[idx])
		m.adjustConfigScroll()
		return m, nil
	}

	items := m.activeItems()
	idx := m.scrollOffset() + line
	if idx < 0 || idx >= len(items) {
		return m, nil
	}
	m.setCursor(idx)
	// The marker is the mouse's Space; the rest of the row only moves the cursor,
	// so a click to read a description cannot silently change the selection.
	if start, end := checkboxCols(items[idx]); x >= start && x <= end {
		m.toggleSelection()
	}
	m.adjustScroll()
	return m, nil
}

// clickRightPanel resolves a click on visible line `line` of the right panel,
// `x` columns into it.
func (m model) clickRightPanel(line, x int) (tea.Model, tea.Cmd) {
	if m.isConfigTab() {
		return m, nil // the Config tab's right panel is help text only
	}

	panel := m.renderRightPanel(m.layout().rightWidth, m.layout().contentH)
	rowIdx, ok := panel.paramRowAt[line]
	if !ok {
		return m, nil
	}

	item, paramNames := m.currentItemParams()
	if len(paramNames) == 0 {
		return m, nil
	}
	t := itemTemplate(item)
	rows := m.buildParamRows(item, t)
	if rowIdx < 0 || rowIdx >= len(rows) {
		return m, nil
	}
	row := rows[rowIdx]

	// A click on the row already being edited is a no-op; clicking any other row
	// commits what was in progress rather than abandoning it.
	alreadyHere := m.paramFocused && m.paramCursorIdx == rowIdx
	if !alreadyHere {
		m.commitActiveEdit()
	}
	m.searchFocused = false
	m.paramFocused = true
	m.paramCursorIdx = rowIdx

	switch row.kind {
	case paramRowVariadicAdd:
		// The add row does nothing but add, so a click means Space on it.
		pk := paramKey(item, row.param)
		m.beginVariadicEdit(pk, len(m.splitVariadic(pk)), "", true)

	case paramRowField:
		// The ◄ ► arrows only exist once the row is focused, so the first click
		// focuses and a second one on an arrow steps the value — the same step
		// the arrow keys make, including their refusal to wrap.
		if alreadyHere && len(t.Params[row.param].Suggests) > 0 && !m.paramEditing {
			pk := paramKey(item, row.param)
			leftCol, rightCol := m.cycleArrowCols(t, row.param, pk)
			switch x {
			case leftCol:
				m.stepSuggest(t, row.param, pk, -1)
			case rightCol:
				m.stepSuggest(t, row.param, pk, 1)
			}
		}
	}
	return m, nil
}

// handleWheel scrolls the pane under the pointer by delta rows.
//
// Over a focused parameter list the wheel walks its rows, because that list is
// what the pointer is on. Everywhere else it scrolls the left panel — the only
// pane with a scroll position of its own — so the wheel always does something.
func (m model) handleWheel(msg tea.MouseMsg, delta int) (tea.Model, tea.Cmd) {
	l := m.layout()
	if msg.Y < contentTop || msg.Y > l.contentBottom() {
		return m, nil
	}

	if m.paramFocused && msg.X >= l.rightStart() {
		item, paramNames := m.currentItemParams()
		if len(paramNames) == 0 {
			return m, nil
		}
		rows := m.buildParamRows(item, itemTemplate(item))
		idx := m.paramCursorIdx + sign(delta)
		if idx < 0 {
			idx = 0
		}
		if idx >= len(rows) {
			idx = len(rows) - 1
		}
		m.paramCursorIdx = idx
		return m, nil
	}

	if m.isConfigTab() {
		m.scrollConfigBy(delta)
		return m, nil
	}
	m.scrollTreeBy(delta)
	return m, nil
}

// scrollTreeBy moves the tree panel's viewport and drags the cursor along only as
// far as it must to stay visible — the right panel shows the cursor's item, so a
// cursor scrolled off screen would leave the two panels describing different rows.
func (m *model) scrollTreeBy(delta int) {
	items := m.activeItems()
	h := m.contentHeight()
	if len(items) == 0 || h <= 0 {
		return
	}

	off := clamp(m.scrollOffset()+delta, 0, max(0, len(items)-h))
	m.setScrollOffset(off)
	m.setCursor(clamp(m.cursorPos(), off, min(off+h-1, len(items)-1)))
}

// scrollConfigBy is scrollTreeBy for the Config tab, whose rows include group
// headers the cursor may not land on.
func (m *model) scrollConfigBy(delta int) {
	rows := m.buildConfigRows()
	h := m.contentHeight()
	if len(rows) == 0 || h <= 0 {
		return
	}

	off := clamp(m.tabScrollOffs[0]+delta, 0, max(0, len(rows)-h))
	m.tabScrollOffs[0] = off

	cur := clamp(m.cursorPos(), off, min(off+h-1, len(rows)-1))
	// Nudge off a group header, preferring to stay inside the visible window.
	for cur < len(rows) && rows[cur].kind == configRowGroup {
		cur++
	}
	if cur > min(off+h-1, len(rows)-1) {
		for cur >= 0 && (cur >= len(rows) || rows[cur].kind == configRowGroup) {
			cur--
		}
	}
	if cur >= 0 && cur < len(rows) {
		m.setCursor(cur)
	}
}

// commitActiveEdit ends whatever edit is in progress, keeping what was typed.
//
// Clicking somewhere else is not a cancellation: the value is accepted exactly as
// Enter would accept it. Without this a click could strand the TUI in edit mode,
// with the next keystroke going into a field the user had visually left behind.
func (m *model) commitActiveEdit() {
	if m.variadicEditing {
		m.commitVariadicEdit()
	}
	if m.paramEditing {
		m.paramEditing = false
	}
	if m.cycleEditing {
		m.cycleEditing = false
	}
	if m.editing {
		m.editing = false
		if m.listEditing {
			// An entry left empty is dropped, the same as finishing it with Enter.
			if f := m.currentConfigField(); f != nil {
				items := m.listFields[f.Key]
				if m.listEditIdx >= 0 && m.listEditIdx < len(items) && items[m.listEditIdx] == "" {
					m.listFields[f.Key] = append(items[:m.listEditIdx], items[m.listEditIdx+1:]...)
				}
			}
			m.listEditing = false
			m.listEditIdx = -1
		}
	}
}

// cycleParamDisplay returns the text a cycle param shows: its value with the
// references resolved, plus the note saying where that value came from.
func (m model) cycleParamDisplay(t *tmpl.Template, name, pk string) string {
	p := t.Params[name]
	raw := m.paramValues[pk]
	if raw == "" {
		raw = p.Default
	}
	display, follows := m.paramDisplay(raw)

	// A value that follows another param is not a hand-typed custom value — say
	// which param it tracks instead of labelling it "(custom)".
	suffix := followsHint(follows)
	if suffix == "" {
		isCustom := true
		for _, s := range p.Suggests {
			if s == display {
				isCustom = false
				break
			}
		}
		if isCustom && display != "" {
			suffix = " (custom)"
		}
	}
	return display + suffix
}

// cycleArrowsAround wraps a focused cycle value in its ◄ ► arrows.
func cycleArrowsAround(display string) string {
	return " ◄ " + display + " ► "
}

// cycleArrowCols returns the columns, within the right panel, of the ◄ and ► on a
// focused cycle param row.
//
// The row is drawn as an unstyled two-space indent, the label, two spaces, then
// cycleArrowsAround — and styles cost no columns — so the arrows sit at fixed
// offsets either side of the same display string the renderer uses. Sharing that
// string is the point: a click lands on the arrow that is actually there.
func (m model) cycleArrowCols(t *tmpl.Template, name, pk string) (leftCol, rightCol int) {
	prefix := lipgloss.Width("  " + name + ":" + "  ")
	inner := cycleArrowsAround(m.cycleParamDisplay(t, name, pk))
	return prefix + 1, prefix + lipgloss.Width(inner) - 2
}

// stepSuggest moves a param to the next or previous suggested value.
//
// Shared with the arrow keys so a click on ◄ or ► does exactly what pressing them
// does — including stopping at either end rather than wrapping, so neither input
// can walk a value past the list the other one stops at.
func (m *model) stepSuggest(t *tmpl.Template, name, pk string, dir int) {
	suggests := t.Params[name].Suggests
	if len(suggests) == 0 {
		return
	}

	current := -1
	for i, s := range suggests {
		if s == m.paramValues[pk] {
			current = i
			break
		}
	}

	switch {
	case current < 0 && dir > 0:
		m.paramValues[pk] = suggests[0]
	case current < 0:
		m.paramValues[pk] = suggests[len(suggests)-1]
	case dir > 0 && current < len(suggests)-1:
		m.paramValues[pk] = suggests[current+1]
	case dir < 0 && current > 0:
		m.paramValues[pk] = suggests[current-1]
	}
}

// itemTemplate returns the template whose params an item carries.
func itemTemplate(item treeItem) *tmpl.Template {
	if item.kind == kindExtension {
		return item.extension
	}
	return item.template
}

func sign(n int) int {
	if n < 0 {
		return -1
	}
	if n > 0 {
		return 1
	}
	return 0
}

func clamp(v, lo, hi int) int {
	if hi < lo {
		return lo
	}
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}
