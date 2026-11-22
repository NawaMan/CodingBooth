// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// The command hint is the two lines below the status line. It names only the
// keys used most, so that it fits a narrow terminal whole: each line is at
// most hintWidth cells, whatever is selected. On a wider terminal a row's
// hint names more keys, as many as fit, up to hintMax cells: it stays compact
// on a very wide one. The help page (?) lists every key.

const keyHelp = "?"

// hintWidth is the widest a command hint line may be on any terminal.
const hintWidth = 80

// hintMax is the widest a command hint line grows to on a wider terminal.
const hintMax = 100

// hintRoom is how wide a hint line may be on this terminal.
func (m model) hintRoom() int {
	return max(hintWidth, min(m.width, hintMax))
}

// hintLine is base, then as many of more as still fit in room, in their order
// (one too long is passed over for a shorter one after it), then end.
func hintLine(room int, base string, more []string, end string) string {
	line := base
	for _, item := range more {
		if lipgloss.Width(line+" · "+item+end) <= room {
			line += " · " + item
		}
	}
	return line + end
}

// helpLines is the command hint for what is selected now.
func (m model) helpLines() []string {
	if sel := m.selection(); len(sel) > 1 {
		acts := "s start · x stop · r restart · del delete"
		if m.deps.Hide != nil && m.showHidden {
			acts = "h unhide · " + acts
		} else if m.deps.Hide != nil {
			acts = "h hide · " + acts
		}
		if m.deps.SaveOrder != nil {
			acts += " · ctrl+↑/↓ move"
		}
		return []string{fmt.Sprintf("%d selected: ", len(sel)) + acts,
			"shift+↑/↓ more or fewer · esc end the selection · ? help · q quit"}
	}
	if r, ok := m.currentRow(); ok && r.sep != "" && m.deps.SaveOrder != nil {
		// A separator: only these keys do anything on it.
		on := "separator: enter name the rows below it · ctrl+↑/↓ move it · del delete it"
		if r.sep == separatorTop {
			on = "top line: enter name the rows below it · it stays while there is a separator"
		}
		return []string{on, "↑/↓ move · - separator · ? help · q quit"}
	}
	// What a wider terminal has room for, most used first.
	look := []string{"o open", "p ports", "m message", "t terminal", "e editor"}
	if m.deps.Config != nil {
		look = append(look, "c config")
	}
	move := "↑/↓ move · shift+↑/↓ select · n new worktree"
	var arrange []string
	switch {
	case m.deps.Hide == nil:
	case m.showHidden:
		move = "↑/↓ move · shift+↑/↓ select · h unhide · H back"
	default:
		move += " · h hide"
		arrange = append(arrange, "H hidden")
	}
	if m.deps.SaveOrder != nil {
		arrange = append(arrange, "ctrl+↑/↓ reorder")
		if !m.showHidden {
			arrange = append(arrange, "- separator")
		}
	}
	arrange = append(arrange, "R refresh")
	room := m.hintRoom()
	return []string{
		hintLine(room, "enter shell · s start · x stop · r restart · del delete · i info · l log", look, ""),
		hintLine(room, move, arrange, " · ? help · q quit"),
	}
}

// helpHintLine is the hint while the help page is open.
const helpHintLine = "↑/↓ scroll · ? or esc back"

type helpEntry struct{ keys, does string }

type helpSection struct {
	title   string
	entries []helpEntry
}

// helpSections is every key the dashboard takes, as it is set up now: a key
// that is off (K without GitKraken, c without a config reader) is left out.
func (m model) helpSections() []helpSection {
	look := []helpEntry{{"i", "show or hide its details below the table"}}
	if m.deps.Config != nil {
		look = append(look, helpEntry{"c", "show or hide its project config in that place"})
	}
	look = append(look,
		helpEntry{"l", "show its whole log, following it while it runs"},
		helpEntry{"o", "open its page in the browser"},
		helpEntry{"p", "pick one of its exposed ports to open"},
		helpEntry{"t", "open a host shell in its folder"},
		helpEntry{"e", "open its folder in your editor ($VISUAL, $EDITOR, code)"},
	)
	if m.deps.GitKraken != nil {
		look = append(look, helpEntry{"K", "open its folder in GitKraken"})
	}

	sections := []helpSection{
		{"Move", []helpEntry{
			{"↑/↓  j/k", "select the row above or below"},
			{"g/G  home/end", "the first or the last row"},
			{"pgup/pgdown", "a screen up or down"},
		}},
		{"Look", look},
		{"Booth", []helpEntry{
			{"enter", "open a shell in it; when stopped: ask, then start it for that"},
			{"s", "start it"},
			{"x", "stop it"},
			{"r", "restart it"},
			{"delete", "delete it and its home volume (or backspace); gone: forget it"},
			{"m", "send its user a message, or a question answered here"},
		}},
		{"Worktree", []helpEntry{
			{"n", "new worktree in the row's repository, with its booth started"},
			{"s", "on a worktree with no booth: start one there"},
			{"enter", "on a worktree with no booth: a terminal booth, just for a shell"},
			{"delete", "on a worktree with no booth: delete the worktree"},
		}},
	}

	var arrange []helpEntry
	if m.deps.SaveOrder != nil {
		arrange = append(arrange,
			helpEntry{"ctrl+↑/↓", "move its group, or a worktree or booth among its siblings"},
			helpEntry{"-", "add a separator line below its group"},
			helpEntry{"enter", "on a separator: name the rows below it"},
			helpEntry{"delete", "on a separator: delete it"},
		)
	}
	if m.deps.Hide != nil {
		arrange = append(arrange,
			helpEntry{"h", "hide it; under H: show it again"},
			helpEntry{"H", "show only the hidden rows; H again goes back"},
		)
	}
	if len(arrange) > 0 {
		sections = append(sections, helpSection{"Arrange", arrange})
	}

	several := "then s, x, r and delete act on all of them"
	if m.deps.Hide != nil {
		several = "then h, s, x, r and delete act on all of them"
	}
	if m.deps.SaveOrder != nil {
		several += ", ctrl+↑/↓ too"
	}
	return append(sections,
		helpSection{"Several rows", []helpEntry{
			{"shift+↑/↓", "select the next row too, or one fewer"},
			{"", several},
			{"esc", "end the selection (a plain ↑/↓ does too)"},
		}},
		helpSection{"Dashboard", []helpEntry{
			{"R", "refresh now"},
			{"?", "show or leave this page"},
			{"q", "quit"},
		}},
	)
}

// helpPage is the help page's lines, unstyled.
func (m model) helpPage() []string {
	sections := m.helpSections()
	width := 0
	for _, s := range sections {
		for _, e := range s.entries {
			width = max(width, lipgloss.Width(e.keys))
		}
	}
	var lines []string
	for i, s := range sections {
		if i > 0 {
			lines = append(lines, "")
		}
		lines = append(lines, s.title)
		for _, e := range s.entries {
			pad := strings.Repeat(" ", width-lipgloss.Width(e.keys))
			lines = append(lines, "  "+e.keys+pad+"  "+e.does)
		}
	}
	return lines
}

// helpRows is how many lines of the help page fit on screen (all of them
// before the first WindowSizeMsg): the title, a blank, and below the page a
// blank and the hint are not its.
func (m model) helpRows() int {
	if m.height <= 0 {
		return len(m.helpPage())
	}
	return max(1, m.height-4)
}

// toggleHelp opens the help page at its top, or leaves it.
func (m model) toggleHelp() (tea.Model, tea.Cmd) {
	m.helpOpen = !m.helpOpen
	m.helpOffset = 0
	return m, nil
}

// handleHelpKey is a key while the help page is open: it scrolls or leaves the
// page, and never reaches a row.
func (m model) handleHelpKey(key string) (tea.Model, tea.Cmd) {
	rows := m.helpRows()
	switch key {
	case "ctrl+c":
		return m, tea.Quit
	case keyHelp, "esc", "q", "enter":
		return m.toggleHelp()
	case "up", "k":
		m.helpOffset--
	case "down", "j":
		m.helpOffset++
	case "pgup":
		m.helpOffset -= rows
	case "pgdown", " ":
		m.helpOffset += rows
	case "home", "g":
		m.helpOffset = 0
	case "end", "G":
		m.helpOffset = len(m.helpPage())
	}
	m.helpOffset = max(0, min(m.helpOffset, len(m.helpPage())-rows))
	return m, nil
}

// helpView is the help page, in the table's place.
func (m model) helpView() string {
	lines := m.helpPage()
	rows := m.helpRows()
	offset := max(0, min(m.helpOffset, len(lines)-rows))
	end := min(len(lines), offset+rows)
	var b strings.Builder
	for _, line := range lines[offset:end] {
		switch {
		case line == "":
		case !strings.HasPrefix(line, " "):
			line = headerStyle.Render(m.fit(line))
		default:
			line = m.fit(line)
		}
		b.WriteString(line + "\n")
	}
	hint := helpHintLine
	if end < len(lines) || offset > 0 {
		hint += fmt.Sprintf(" · lines %d-%d of %d", offset+1, end, len(lines))
	}
	b.WriteString("\n" + dimStyle.Render(m.fit(hint)))
	return b.String()
}
