// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

func keyOf(kind tea.KeyType) tea.KeyMsg { return tea.KeyMsg{Type: kind} }

var (
	keyLeft  = keyOf(tea.KeyLeft)
	keyRight = keyOf(tea.KeyRight)
	keyHome  = keyOf(tea.KeyHome)
	keyEnd   = keyOf(tea.KeyEnd)
)

func TestMoveTextCursor(t *testing.T) {
	cases := []struct {
		name   string
		key    string
		cursor int
		length int
		want   int
		moved  bool
	}{
		{"left", "left", 3, 5, 2, true},
		{"left at the start stays", "left", 0, 5, 0, true},
		{"right", "right", 3, 5, 4, true},
		{"right at the end stays", "right", 5, 5, 5, true},
		{"home", "home", 3, 5, 0, true},
		{"end", "end", 0, 5, 5, true},
		{"home on an empty field", "home", 0, 0, 0, true},
		{"end on an empty field", "end", 0, 0, 0, true},
		{"a stale cursor is clamped", "left", 9, 5, 5, true},
		{"another key is not ours", "enter", 3, 5, 3, false},
		{"text is not a key", "", 3, 5, 3, false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, moved := moveTextCursor(c.key, c.cursor, c.length)
			if got != c.want || moved != c.moved {
				t.Fatalf("moveTextCursor(%q, %d, %d) = (%d, %v), want (%d, %v)",
					c.key, c.cursor, c.length, got, moved, c.want, c.moved)
			}
		})
	}
}

// block wraps what the cursor is sitting on, for readable expectations below.
func block(cell string) string { return cursorReverseOn + cell + cursorReverseOff }

func TestCaretText(t *testing.T) {
	cases := []struct {
		name   string
		value  string
		cursor int
		want   string
	}{
		{"at the end covers the blank cell", "booth", 5, "booth" + block(" ")},
		{"at the start", "booth", 0, block("b") + "ooth"},
		{"in the middle", "booth", 3, "boo" + block("t") + "h"},
		{"empty value", "", 0, block(" ")},
		{"past the end is clamped", "booth", 99, "booth" + block(" ")},
		{"negative is clamped", "booth", -1, block("b") + "ooth"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := caretText(c.value, c.cursor); got != c.want {
				t.Fatalf("caretText(%q, %d) = %q, want %q", c.value, c.cursor, got, c.want)
			}
		})
	}
}

// The cursor must cost columns only where it covers a blank cell at the end —
// mid-value it reverses a character that is already there, so the text around it
// cannot shift as the cursor walks. The padding math in the search box and the
// overwrite dialog measures this, so it has to be measured the same way.
func TestCaretTextWidth(t *testing.T) {
	cases := []struct {
		value  string
		cursor int
		want   int
	}{
		{"booth", 3, 5},
		{"booth", 0, 5},
		{"booth", 5, 6},
		{"", 0, 1},
	}
	for _, c := range cases {
		if got := lipgloss.Width(caretText(c.value, c.cursor)); got != c.want {
			t.Fatalf("width of caretText(%q, %d) = %d, want %d", c.value, c.cursor, got, c.want)
		}
	}
}

func TestWindowAround(t *testing.T) {
	cases := []struct {
		name       string
		text       string
		cursor     int
		width      int
		want       string
		wantCursor int
	}{
		{"fits whole", "go-pkg", 2, 20, "go-pkg", 2},
		{"cursor at the end shows the tail", "abcdefghij", 10, 4, "ghij", 4},
		{"cursor at the start shows the head", "abcdefghij", 0, 4, "abcd", 0},
		{"cursor in the middle stays inside", "abcdefghij", 5, 4, "bcde", 4},
		{"a width of zero still holds the caret", "abcdefghij", 10, 0, "j", 1},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, gotCursor := windowAround(c.text, c.cursor, c.width)
			if got != c.want || gotCursor != c.wantCursor {
				t.Fatalf("windowAround(%q, %d, %d) = (%q, %d), want (%q, %d)",
					c.text, c.cursor, c.width, got, gotCursor, c.want, c.wantCursor)
			}
		})
	}
}

// configModelAt builds a Config-tab model with the cursor parked on a field.
func configModelAt(t *testing.T, fieldKey string) model {
	t.Helper()
	m := model{
		tabNames:      []string{"Config"},
		tabItems:      [][]treeItem{nil},
		tabCursors:    []int{0},
		tabScrollOffs: []int{0},
		selected:      map[string]bool{},
		stringFields:  map[string]string{},
		boolFields:    map[string]bool{},
		cycleIndices:  map[string]int{},
		listFields:    map[string][]string{},
		paramValues:   map[string]string{},
		width:         120,
		height:        40,
	}
	for index, row := range m.buildConfigRows() {
		if allConfigFields[row.fieldIdx].Key != fieldKey {
			continue
		}
		if row.kind == configRowField || row.kind == configRowListItem {
			m.setCursor(index)
			return m
		}
	}
	t.Fatalf("no row for config field %q", fieldKey)
	return m
}

// The four keys have to reach the field itself. Left and Right in particular are
// the tab switchers everywhere else in the TUI, so an open edit has to claim them.
func TestConfigStringFieldCursorKeys(t *testing.T) {
	m := configModelAt(t, "name")
	m.stringFields["name"] = "booth"
	m.editing = true
	m.editCursor = len("booth")

	for _, step := range []struct {
		msg  tea.KeyMsg
		want int
	}{
		{keyLeft, 4},
		{keyLeft, 3},
		{keyRight, 4},
		{keyHome, 0},
		{keyEnd, 5},
		{keyHome, 0},
	} {
		res, _ := m.Update(step.msg)
		m = res.(model)
		if m.editCursor != step.want {
			t.Fatalf("cursor = %d, want %d", m.editCursor, step.want)
		}
	}

	if m.activeTab != 0 {
		t.Fatalf("editing must not let the arrows switch tabs, tab = %d", m.activeTab)
	}

	// Typing lands where the cursor was left, not at the end.
	res, _ := m.Update(keyMsg('x'))
	m = res.(model)
	if got := m.stringFields["name"]; got != "xbooth" {
		t.Fatalf("value = %q, want %q", got, "xbooth")
	}
	if m.editCursor != 1 {
		t.Fatalf("cursor = %d, want 1 (after the inserted character)", m.editCursor)
	}
}

// Backspace deletes in front of the cursor, wherever it has been moved to.
func TestConfigStringFieldBackspaceAtCursor(t *testing.T) {
	m := configModelAt(t, "name")
	m.stringFields["name"] = "booth"
	m.editing = true
	m.editCursor = len("booth")

	for _, msg := range []tea.KeyMsg{keyHome, keyRight, keyRight, keyOf(tea.KeyBackspace)} {
		res, _ := m.Update(msg)
		m = res.(model)
	}
	if got := m.stringFields["name"]; got != "both" {
		t.Fatalf("value = %q, want %q", got, "both")
	}
	if m.editCursor != 1 {
		t.Fatalf("cursor = %d, want 1", m.editCursor)
	}
}

// A list entry (expose, env, mount) is edited by the same handler but writes back
// into a different place, so it gets its own pass.
func TestConfigListItemCursorKeys(t *testing.T) {
	m := configModelAt(t, "name")
	m.listFields["expose"] = []string{"8080"}

	// The entry only becomes a row once the list holds one.
	found := false
	for index, row := range m.buildConfigRows() {
		if row.kind == configRowListItem && allConfigFields[row.fieldIdx].Key == "expose" {
			m.setCursor(index)
			found = true
			break
		}
	}
	if !found {
		t.Fatal("no list-entry row for expose")
	}
	m.editing = true
	m.listEditing = true
	m.listEditIdx = 0
	m.editCursor = len("8080")

	res, _ := m.Update(keyHome)
	m = res.(model)
	res, _ = m.Update(keyMsg('1'))
	m = res.(model)

	if got := m.listFields["expose"][0]; got != "18080" {
		t.Fatalf("entry = %q, want %q", got, "18080")
	}
}

func TestSearchCursorKeys(t *testing.T) {
	m := model{
		tabNames:      []string{"Config", "Languages"},
		tabItems:      [][]treeItem{nil, {}},
		activeTab:     1,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		searchQuery:   "pkg",
		searchCursor:  3,
		searchFocused: true,
		width:         120,
		height:        40,
	}

	res, _ := m.Update(keyHome)
	m = res.(model)
	if m.searchCursor != 0 {
		t.Fatalf("cursor = %d, want 0", m.searchCursor)
	}
	res, _ = m.Update(keyMsg('g'))
	m = res.(model)
	res, _ = m.Update(keyOf(tea.KeyEnd))
	m = res.(model)
	res, _ = m.Update(keyMsg('s'))
	m = res.(model)

	if m.searchQuery != "gpkgs" {
		t.Fatalf("query = %q, want %q", m.searchQuery, "gpkgs")
	}
	if m.searchCursor != len("gpkgs") {
		t.Fatalf("cursor = %d, want %d", m.searchCursor, len("gpkgs"))
	}
}

// A query longer than its box scrolls with the cursor: Home must bring the head of
// the query — and the caret — back into view.
func TestSearchBarWindowFollowsTheCursor(t *testing.T) {
	query := strings.Repeat("abcdefghij", 6)
	m := model{
		tabNames:      []string{"Config"},
		tabItems:      [][]treeItem{nil},
		tabCursors:    []int{0},
		tabScrollOffs: []int{0},
		searchQuery:   query,
		searchCursor:  len(query),
		searchFocused: true,
		width:         40,
		height:        40,
	}

	tail := m.renderSearchBar(40)
	if !strings.Contains(tail, "ij"+block(" ")) {
		t.Fatalf("with the cursor at the end the box should show the tail and the cursor:\n%q", tail)
	}

	m.searchCursor = 0
	head := m.renderSearchBar(40)
	if !strings.Contains(head, block("a")+"bcde") {
		t.Fatalf("with the cursor at Home the box should show the head:\n%q", head)
	}

	// The box is one line of fixed width whichever cell the cursor is on.
	m.searchCursor = 20
	middle := m.renderSearchBar(40)
	if lipgloss.Width(tail) != lipgloss.Width(middle) {
		t.Fatalf("the search box changed width with the cursor: %d vs %d",
			lipgloss.Width(tail), lipgloss.Width(middle))
	}
}

func TestParamStringEditCursorKeys(t *testing.T) {
	pk := "go:GO_VERSION"
	m := model{
		paramValues:     map[string]string{pk: "1.25"},
		paramEditing:    true,
		paramEditKey:    pk,
		paramEditCursor: len("1.25"),
	}

	res, _ := m.Update(keyHome)
	m = res.(model)
	if m.paramEditCursor != 0 {
		t.Fatalf("cursor = %d, want 0", m.paramEditCursor)
	}
	res, _ = m.Update(pasteMsg("v"))
	m = res.(model)
	if got := m.paramValues[pk]; got != "v1.25" {
		t.Fatalf("value = %q, want %q", got, "v1.25")
	}

	res, _ = m.Update(keyEnd)
	m = res.(model)
	if m.paramEditCursor != len("v1.25") {
		t.Fatalf("cursor = %d, want %d", m.paramEditCursor, len("v1.25"))
	}
}

func TestVariadicEditCursorKeys(t *testing.T) {
	pk := "go-pkg:GO_PKGS"
	m := model{
		paramValues:     map[string]string{},
		variadicEditing: true,
		variadicEditKey: pk,
		variadicEditIdx: 0,
		variadicEditBuf: "tools/gopls@latest",
		variadicEditCur: len("tools/gopls@latest"),
	}

	res, _ := m.Update(keyHome)
	m = res.(model)
	res, _ = m.Update(pasteMsg("golang.org/x/"))
	m = res.(model)

	want := "golang.org/x/tools/gopls@latest"
	if m.variadicEditBuf != want {
		t.Fatalf("buffer = %q, want %q", m.variadicEditBuf, want)
	}
	if m.variadicEditCur != len("golang.org/x/") {
		t.Fatalf("cursor = %d, want %d", m.variadicEditCur, len("golang.org/x/"))
	}
	if !m.variadicEditing {
		t.Fatal("moving the cursor must not end the edit")
	}
}

// The overwrite confirmation is a text box too, and it had no cursor at all — the
// caret was pinned to the end and every character appended. Typing the word is the
// only way past it, so mistyping it has to be fixable in place.
func TestOverwriteConfirmCursorKeys(t *testing.T) {
	m := model{
		drifted:         []string{"Dockerfile"},
		overwriteDialog: true,
		overwriteInput:  "verwrite",
		overwriteCursor: len("verwrite"),
	}

	res, _ := m.Update(keyHome)
	m = res.(model)
	res, _ = m.Update(keyMsg('o'))
	m = res.(model)

	if m.overwriteInput != overwriteConfirmWord {
		t.Fatalf("input = %q, want %q", m.overwriteInput, overwriteConfirmWord)
	}

	res, _ = m.Update(keyOf(tea.KeyEnter))
	m = res.(model)
	if !m.confirmed || m.saveBeside {
		t.Fatalf("the typed word should confirm the overwrite (confirmed=%v, saveBeside=%v)", m.confirmed, m.saveBeside)
	}
}
