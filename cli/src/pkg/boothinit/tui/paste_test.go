// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package tui

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	tmpl "github.com/nawaman/codingbooth/src/pkg/boothinit/template"
)

// pasteMsg builds the key message a terminal delivers for a bracketed paste:
// one KeyRunes carrying the whole clipboard, flagged as a paste. This is the
// shape that used to be dropped by every text field, so the tests below assert
// against it rather than against a synthesized run of single keystrokes.
func pasteMsg(text string) tea.KeyMsg {
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(text), Paste: true}
}

func keyMsg(ch rune) tea.KeyMsg {
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{ch}}
}

// runesMsg builds the message Bubble Tea produces for several characters read at
// once WITHOUT bracketed paste — it coalesces a run of non-control runes into one
// KeyRunes with no Paste flag. A terminal that does not bracket its pastes, an
// `xdotool type`, and a laggy link all land here, so this shape has to be treated
// as text too.
func runesMsg(text string) tea.KeyMsg {
	return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(text)}
}

// A pasted key's String() is bracket-wrapped by Bubble Tea, which is precisely
// why the old `len(msg.String()) == 1` test threw pastes away. Pin that so the
// guard cannot be "simplified" back into the bug.
func TestPasteStringIsNotASingleChar(t *testing.T) {
	msg := pasteMsg("gopls@latest")
	if got := msg.String(); got != "[gopls@latest]" {
		t.Fatalf("paste String() = %q, want the bracket-wrapped form", got)
	}
	if got := typedText(msg); got != "gopls@latest" {
		t.Fatalf("typedText = %q, want the payload without brackets", got)
	}
}

func TestTypedText(t *testing.T) {
	cases := []struct {
		name string
		msg  tea.KeyMsg
		want string
	}{
		{"typed rune", keyMsg('x'), "x"},
		{"typed space", tea.KeyMsg{Type: tea.KeySpace, Runes: []rune{' '}}, " "},
		{"named key", tea.KeyMsg{Type: tea.KeyEnter}, ""},
		{"alt combo is not text", tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune{'x'}, Alt: true}, ""},
		{"paste", pasteMsg("github.com/a/b@v1"), "github.com/a/b@v1"},
		{"paste drops the copied newline", pasteMsg("gopls@latest\n"), "gopls@latest"},
		{"paste drops interior control chars", pasteMsg("a\tb\r\nc"), "abc"},
		{"paste drops non-ascii", pasteMsg("caf\u00e9"), "caf"},
		{"paste of only control chars", pasteMsg("\n\n"), ""},
		{"coalesced rune run", runesMsg("go-pkg"), "go-pkg"},
		{"coalesced run is filtered too", runesMsg("go\x07pkg"), "gopkg"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := typedText(c.msg); got != c.want {
				t.Fatalf("typedText = %q, want %q", got, c.want)
			}
		})
	}
}

// Pasting into a variadic package row is the case this was reported for: a
// module path copied from a browser has to land in GO_PKGS whole.
func TestPasteIntoVariadicValue(t *testing.T) {
	pk := "go-pkg:GO_PKGS"
	m := model{
		paramValues:     map[string]string{},
		variadicEditing: true,
		variadicEditKey: pk,
		variadicEditIdx: 0,
		// Half-typed, cursor at the end — a paste inserts at the cursor.
		variadicEditBuf:   "github.com/",
		variadicEditCur:   len("github.com/"),
		variadicEditIsNew: true,
	}

	res, _ := m.Update(pasteMsg("golangci/golangci-lint/cmd/golangci-lint@latest\n"))
	m = res.(model)
	want := "github.com/golangci/golangci-lint/cmd/golangci-lint@latest"
	if m.variadicEditBuf != want {
		t.Fatalf("buffer = %q, want %q", m.variadicEditBuf, want)
	}
	if m.variadicEditCur != len(want) {
		t.Fatalf("cursor = %d, want %d (end of the pasted text)", m.variadicEditCur, len(want))
	}

	m.commitVariadicEdit()
	if got := m.paramValues[pk]; got != want {
		t.Fatalf("committed value = %q, want %q", got, want)
	}
}

// Variadic values are stored comma-joined, so a paste holding several packages
// becomes several rows rather than one unusable value.
func TestPasteOfCommaSeparatedPackagesBecomesRows(t *testing.T) {
	pk := "go-pkg:GO_PKGS"
	m := model{
		paramValues:       map[string]string{},
		variadicEditing:   true,
		variadicEditKey:   pk,
		variadicEditIdx:   0,
		variadicEditIsNew: true,
	}

	res, _ := m.Update(pasteMsg("golang.org/x/tools/gopls@latest,github.com/go-delve/delve/cmd/dlv@latest"))
	m = res.(model)
	m.commitVariadicEdit()

	vals := m.splitVariadic(pk)
	want := []string{"golang.org/x/tools/gopls@latest", "github.com/go-delve/delve/cmd/dlv@latest"}
	if len(vals) != len(want) {
		t.Fatalf("got %d values %v, want %d", len(vals), vals, len(want))
	}
	for i := range want {
		if vals[i] != want[i] {
			t.Fatalf("value %d = %q, want %q", i, vals[i], want[i])
		}
	}
}

// A paste onto a focused-but-not-yet-editing row opens the editor, the same way
// typing a character does.
func TestPasteStartsEditingFocusedRow(t *testing.T) {
	item, _ := goPkgItem()
	m := model{
		tabNames:      []string{"Config", "Languages"},
		tabItems:      [][]treeItem{nil, {item}},
		activeTab:     1,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		selected:      map[string]bool{"go": true, "go/go-pkg": true},
		paramValues:   map[string]string{},
		paramFocused:  true,
	}

	res, _ := m.Update(pasteMsg("golang.org/x/tools/gopls@v0.16.1"))
	m = res.(model)
	if !m.variadicEditing {
		t.Fatal("paste on the (+ add) row should open the value editor")
	}
	if m.variadicEditBuf != "golang.org/x/tools/gopls@v0.16.1" {
		t.Fatalf("buffer = %q", m.variadicEditBuf)
	}
	if m.variadicEditCur != len(m.variadicEditBuf) {
		t.Fatalf("cursor = %d, want %d", m.variadicEditCur, len(m.variadicEditBuf))
	}
}

// goPkgItem builds the go-pkg extension as a treeItem: a variadic GO_PKGS param
// hanging off the go template.
func goPkgItem() (treeItem, *tmpl.Template) {
	ext := &tmpl.Template{
		Name:       "go-pkg",
		Params:     map[string]tmpl.Param{"GO_PKGS": {Variadic: true}},
		ParamOrder: []string{"GO_PKGS"},
	}
	parent := &tmpl.Template{Name: "go", Extensions: []*tmpl.Template{ext}}
	return treeItem{kind: kindExtension, template: parent, extension: ext}, ext
}

func TestPasteIntoSingleValueParam(t *testing.T) {
	pk := "go:GO_VERSION"
	m := model{
		paramValues:     map[string]string{pk: ""},
		paramEditing:    true,
		paramEditKey:    pk,
		paramEditCursor: 0,
	}

	res, _ := m.Update(pasteMsg("1.25.7\n"))
	m = res.(model)
	if got := m.paramValues[pk]; got != "1.25.7" {
		t.Fatalf("value = %q, want %q", got, "1.25.7")
	}
	if m.paramEditCursor != len("1.25.7") {
		t.Fatalf("cursor = %d", m.paramEditCursor)
	}
}

func TestPasteIntoSearchQuery(t *testing.T) {
	m := model{
		tabNames:      []string{"Config", "Languages"},
		tabItems:      [][]treeItem{nil, {}},
		activeTab:     0,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		searchFocused: true,
	}

	res, _ := m.Update(pasteMsg("go-pkg\n"))
	m = res.(model)
	if m.searchQuery != "go-pkg" {
		t.Fatalf("search query = %q", m.searchQuery)
	}
	if m.searchCursor != len("go-pkg") {
		t.Fatalf("search cursor = %d", m.searchCursor)
	}
	if m.activeTab != 1 {
		t.Fatalf("a paste should leave the Config tab like typing does, tab = %d", m.activeTab)
	}
}

// The same field must accept a run of characters that arrived in one read with no
// Paste flag — how a fast feeder (or a terminal that does not bracket pastes)
// delivers text. Driving the real TUI through a PTY hit exactly this: the whole
// search string vanished and the wrong template got selected.
func TestCoalescedRunIntoSearchQuery(t *testing.T) {
	m := model{
		tabNames:      []string{"Config", "Languages"},
		tabItems:      [][]treeItem{nil, {}},
		activeTab:     0,
		tabCursors:    []int{0, 0},
		tabScrollOffs: []int{0, 0},
		searchFocused: true,
	}

	res, _ := m.Update(runesMsg("go-pkg"))
	m = res.(model)
	if m.searchQuery != "go-pkg" {
		t.Fatalf("search query = %q, want the whole run", m.searchQuery)
	}
	if m.searchCursor != len("go-pkg") {
		t.Fatalf("search cursor = %d", m.searchCursor)
	}
}

// Text whose characters spell a key name is still text. Handlers dispatch on
// msg.String(), and an unbracketed multi-rune event stringifies to its own runes —
// so "up" would have moved the cursor instead of landing in the field.
func TestMultiRuneTextIsNotAKeyName(t *testing.T) {
	pk := "apt-pkg:APT_PKGS"
	m := model{
		paramValues:       map[string]string{},
		variadicEditing:   true,
		variadicEditKey:   pk,
		variadicEditIdx:   0,
		variadicEditIsNew: true,
	}

	// "up" as text, and "esc" — which would otherwise discard the edit outright.
	for _, text := range []string{"up", "esc"} {
		res, _ := m.Update(runesMsg(text))
		m = res.(model)
	}
	if !m.variadicEditing {
		t.Fatal("a multi-rune payload must not be obeyed as a key")
	}
	if m.variadicEditBuf != "upesc" {
		t.Fatalf("buffer = %q, want %q", m.variadicEditBuf, "upesc")
	}
}

// An int config field filters a paste per character, for the same reason it
// filters keystrokes: a non-numeric value fails the config.toml decode.
func TestPasteIntoIntFieldKeepsDigitsOnly(t *testing.T) {
	if got := acceptsEditText(fieldKindInt, "30 minutes"); got != "30" {
		t.Fatalf("int field = %q, want %q", got, "30")
	}
	if got := acceptsEditText(fieldKindString, "30 minutes"); got != "30 minutes" {
		t.Fatalf("string field = %q, want it unfiltered", got)
	}
}

func TestOverwriteConfirmAcceptsPastedWord(t *testing.T) {
	m := model{overwriteDialog: true, drifted: []string{".booth/Boothfile"}}

	res, _ := m.Update(pasteMsg(overwriteConfirmWord + "\n"))
	m = res.(model)
	if m.overwriteInput != overwriteConfirmWord {
		t.Fatalf("input = %q, want %q", m.overwriteInput, overwriteConfirmWord)
	}

	res, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	m = res.(model)
	if !m.confirmed || m.saveBeside {
		t.Fatalf("Enter on the pasted word should confirm an overwrite: confirmed=%v saveBeside=%v", m.confirmed, m.saveBeside)
	}
	if cmd == nil {
		t.Fatal("confirming should quit the program")
	}
}
