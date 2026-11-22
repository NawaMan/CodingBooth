// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// helpText is the help page (?) of m.
func helpText(m model) string {
	return strings.Join(m.helpPage(), "\n")
}

// hintModel is a dashboard with everything on (hide, order, GitKraken,
// config), over orderRepos.
func hintModel(t *testing.T) (model, *fakeDeps) {
	t.Helper()
	booths, repos := orderRepos()
	f := &fakeDeps{snapshot: booths, repos: repos}
	deps := (&hideStore{}).wire((&orderStore{}).wire(f.deps()))
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos, hidden: deps.Hidden()})
	return next.(model), f
}

func TestCommandHintIsTwoLinesThatFit(t *testing.T) {
	m, _ := hintModel(t)
	hints := map[string][]string{"a row": m.helpLines()}

	plain := loaded(&fakeDeps{}, running("web"))
	plain.deps.Hide, plain.deps.SaveOrder, plain.deps.GitKraken, plain.deps.Config = nil, nil, nil, nil
	hints["nothing optional"] = plain.helpLines()

	// Every row selected, to make the count as wide as it gets here.
	sel, _ := press(t, m, "g")
	for range m.rows {
		sel, _ = press(t, sel, "shift+down")
	}
	if len(sel.selection()) != len(m.rows) {
		t.Fatalf("selected %d of %d rows", len(sel.selection()), len(m.rows))
	}
	hints["several rows"] = sel.helpLines()

	hidden, _ := press(t, m, "h", "H")
	hints["hidden rows"] = hidden.helpLines()
	hiddenSel, _ := press(t, m, "g", "h", "h", "H", "shift+down")
	if len(hiddenSel.selection()) != 2 {
		t.Fatalf("selected %d hidden rows, want 2", len(hiddenSel.selection()))
	}
	hints["several hidden rows"] = hiddenSel.helpLines()

	sep, _ := press(t, m, "-")
	hints["a separator"] = sep.helpLines()
	top, _ := press(t, sep, "g")
	if r, _ := top.currentRow(); r.sep != separatorTop {
		t.Fatalf("not on the top line: %+v", r)
	}
	hints["the top line"] = top.helpLines()

	naming, _ := press(t, sep, "enter")
	hints["naming a separator"] = naming.promptHelp()
	worktree, _ := press(t, m, "n")
	hints["a new worktree"] = worktree.promptHelp()
	hints["a message"] = composeHelpLines
	hints["the port picker"] = []string{pickerHelpLine}
	hints["the help page"] = []string{helpHintLine + " · lines 100-199 of 199"}

	for name, lines := range hints {
		if len(lines) > 2 {
			t.Errorf("%s: %d hint lines, want at most 2", name, len(lines))
		}
		for _, line := range lines {
			if w := lipgloss.Width(line); w > hintWidth {
				t.Errorf("%s: hint is %d wide, over %d: %q", name, w, hintWidth, line)
			}
		}
	}
	for _, name := range []string{"a row", "nothing optional", "several rows", "hidden rows", "several hidden rows", "a separator", "the top line"} {
		if last := hints[name][1]; !strings.HasSuffix(last, "? help · q quit") {
			t.Errorf("%s: hint does not end in ? help · q quit: %q", name, last)
		}
	}
	// In a narrow terminal the hint is still whole.
	m.width, m.height = hintWidth, 30
	view := stripANSI(m.View())
	for _, line := range m.helpLines() {
		if !strings.Contains(view, line) {
			t.Errorf("at %d columns the hint is cut: %q\n%s", hintWidth, line, view)
		}
	}
}

func TestCommandHintNamesMoreKeysOnAWiderTerminal(t *testing.T) {
	m, _ := hintModel(t)
	narrow := m.helpLines()
	for width := 0; width <= 200; width++ {
		m.width = width
		lines := m.helpLines()
		room := hintWidth
		if width > hintWidth {
			room = min(width, hintMax)
		}
		for i, line := range lines {
			if w := lipgloss.Width(line); w > room {
				t.Fatalf("at %d columns a hint line is %d wide, over %d: %q", width, w, room, line)
			}
			if !strings.HasPrefix(line, strings.TrimSuffix(narrow[i], " · ? help · q quit")) {
				t.Fatalf("at %d columns the hint lost its first keys: %q", width, line)
			}
		}
		if !strings.HasSuffix(lines[1], " · ? help · q quit") {
			t.Fatalf("at %d columns the hint does not end in ? help · q quit: %q", width, lines[1])
		}
		if width <= hintWidth && (lines[0] != narrow[0] || lines[1] != narrow[1]) {
			t.Fatalf("at %d columns the hint is not the narrow one: %q", width, lines)
		}
	}
	m.width = 100
	wide := m.helpLines()
	if !strings.Contains(wide[0], "· o open · p ports") || !strings.Contains(wide[1], "· H hidden") {
		t.Errorf("at 100 columns the hint names no more keys: %q", wide)
	}
	// It stops growing at hintMax, and is drawn whole.
	m.width, m.height = 200, 30
	if got := m.helpLines(); got[0] != wide[0] || got[1] != wide[1] {
		t.Errorf("at 200 columns the hint is %q, want the one at %d: %q", got, hintMax, wide)
	}
	view := stripANSI(m.View())
	for _, line := range wide {
		if !strings.Contains(view, line) {
			t.Errorf("the wide hint is cut: %q\n%s", line, view)
		}
	}
}

func TestHelpPageListsEveryKey(t *testing.T) {
	m, _ := hintModel(t)
	page := m.helpPage()
	keys := map[string]bool{}
	for _, s := range m.helpSections() {
		for _, e := range s.entries {
			for _, k := range strings.FieldsFunc(e.keys, func(r rune) bool { return r == ' ' || r == '/' }) {
				keys[k] = true
			}
			keys[e.keys] = true
		}
	}
	for _, key := range []string{keyStart, keyStop, keyRestart, keyRemove, keyShell, keyOpen, keyPorts, keyMessage,
		keyDetail, keyConfig, keyNew, keyEditor, keyTerm, keyLog, keyGitKraken, keyRefresh, keyHide, keyHidden,
		keySeparator, keyHelp, "ctrl+↑/↓", "shift+↑/↓", "esc", "q", "j", "k", "g", "G", "pgup", "pgdown", "home", "end"} {
		if !keys[key] {
			t.Errorf("the help page does not list %q:\n%s", key, strings.Join(page, "\n"))
		}
	}
	for _, line := range page {
		if w := lipgloss.Width(line); w > hintWidth {
			t.Errorf("help page line is %d wide, over %d: %q", w, hintWidth, line)
		}
	}
	// What is off is not offered.
	m.deps.GitKraken, m.deps.Config, m.deps.Hide, m.deps.SaveOrder = nil, nil, nil, nil
	off := helpText(m)
	for _, gone := range []string{"GitKraken", "project config", "hide it;", "separator", "ctrl+↑/↓", "Arrange"} {
		if strings.Contains(off, gone) {
			t.Errorf("with it off, the help page still says %q:\n%s", gone, off)
		}
	}
}

func TestHelpKeyShowsThePageAndKeysDoNotReachTheRows(t *testing.T) {
	m, f := hintModel(t)
	m.width, m.height = 100, 60
	before := rowSummary(m.rows)
	cursor := m.cursor
	m, _ = press(t, m, "?")
	view := stripANSI(m.View())
	for _, want := range []string{"booth dashboard", "Booth\n", "Several rows\n", "show or leave this page", helpHintLine} {
		if !strings.Contains(view, want) {
			t.Errorf("help page lacks %q:\n%s", want, view)
		}
	}
	if strings.Contains(view, "CODE PATH") {
		t.Errorf("the table is still shown under the help page:\n%s", view)
	}
	for _, key := range []string{"x", "s", "r", "delete", "h", "n", "-", "m", "p", "t", "e", "K", "ctrl+down", "shift+down", "down"} {
		var cmd tea.Cmd
		m, cmd = press(t, m, key)
		if cmd != nil {
			t.Errorf("%s on the help page ran a command", key)
		}
	}
	if !m.helpOpen || m.confirm != nil || m.prompt != nil || m.compose != nil || m.picker != nil ||
		len(f.ran)+len(f.execed) != 0 || m.cursor != cursor || m.anchor != "" {
		t.Fatalf("a key on the help page acted: confirm %+v prompt %+v ran %v execed %v cursor %d→%d",
			m.confirm, m.prompt, f.ran, f.execed, cursor, m.cursor)
	}
	if got := rowSummary(m.rows); strings.Join(got, ",") != strings.Join(before, ",") {
		t.Errorf("rows changed under the help page: %v → %v", before, got)
	}
	// A refresh does not close it.
	next, _ := m.Update(snapshotMsg{seq: 2, booths: m.booths, repos: m.repos})
	m = next.(model)
	if !m.helpOpen {
		t.Errorf("a refresh closed the help page")
	}
	for _, leave := range []string{"?", "esc", "q", "enter"} {
		open, _ := press(t, m)
		closed, cmd := press(t, open, leave)
		if closed.helpOpen || cmd != nil {
			t.Errorf("%s did not leave the help page (cmd %v)", leave, cmd != nil)
		}
		if !strings.Contains(stripANSI(closed.View()), "CODE PATH") {
			t.Errorf("after %s the table is not back", leave)
		}
	}
}

func TestHelpPageScrollsOnAShortScreen(t *testing.T) {
	m, _ := hintModel(t)
	m.width, m.height = 100, 12 // 8 lines of the page
	total := len(m.helpPage())
	m, _ = press(t, m, "?")
	view := stripANSI(m.View())
	if n := strings.Count(view, "\n") + 1; n > m.height {
		t.Fatalf("help page is %d lines on a %d line screen:\n%s", n, m.height, view)
	}
	if !strings.Contains(view, "Move") || strings.Contains(view, "quit") || !strings.Contains(view, "lines 1-8 of ") {
		t.Errorf("first screen of the help page:\n%s", view)
	}
	m, _ = press(t, m, "up") // already at the top
	if m.helpOffset != 0 {
		t.Errorf("scrolled above the top: %d", m.helpOffset)
	}
	m, _ = press(t, m, "down", "down", "pgdown")
	if m.helpOffset != 10 {
		t.Errorf("offset = %d, want 10", m.helpOffset)
	}
	m, _ = press(t, m, "end", "down")
	if m.helpOffset != total-8 {
		t.Errorf("offset at the end = %d, want %d", m.helpOffset, total-8)
	}
	if view := stripANSI(m.View()); !strings.Contains(view, "q          quit") && !strings.Contains(view, "quit") {
		t.Errorf("the end of the help page is not shown:\n%s", view)
	}
	m, _ = press(t, m, "home")
	if m.helpOffset != 0 {
		t.Errorf("home: offset = %d", m.helpOffset)
	}
	// Opened again, it starts at its top.
	m, _ = press(t, m, "end", "?", "?")
	if !m.helpOpen || m.helpOffset != 0 {
		t.Errorf("reopened: open %v offset %d", m.helpOpen, m.helpOffset)
	}
}
