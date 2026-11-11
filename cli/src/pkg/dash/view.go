// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"strings"
	"time"

	"github.com/charmbracelet/lipgloss"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

var (
	titleStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("39"))
	dimStyle     = lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	headerStyle  = lipgloss.NewStyle().Bold(true)
	cursorStyle  = lipgloss.NewStyle().Background(lipgloss.Color("24")).Foreground(lipgloss.Color("255"))
	runningStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("82"))
	busyStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("214"))
	errorStyle   = lipgloss.NewStyle().Foreground(lipgloss.Color("203"))
	confirmStyle = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("220"))
	warnStyle    = lipgloss.NewStyle().Foreground(lipgloss.Color("220"))
)

const helpLine = "↑/↓ move · enter shell · o open · s start · x stop · r restart · d remove · R refresh · q quit"

// chromeLines is everything but the table rows: title, blank, header, and
// below the table a blank, the status line and the help line.
const chromeLines = 6

// tableRows is how many booth rows fit on screen (all of them before the
// first WindowSizeMsg).
func (m model) tableRows() int {
	if m.height <= 0 {
		return max(1, len(m.booths))
	}
	return max(1, m.height-chromeLines-len(m.warnings))
}

// clampOffset scrolls just enough to keep the cursor on screen.
func (m *model) clampOffset() {
	rows := m.tableRows()
	if m.cursor < m.offset {
		m.offset = m.cursor
	}
	if m.cursor >= m.offset+rows {
		m.offset = m.cursor - rows + 1
	}
	m.offset = max(0, min(m.offset, max(0, len(m.booths)-rows)))
}

func (m model) View() string {
	var b strings.Builder
	b.WriteString(m.titleLine())
	b.WriteString("\n\n")

	switch {
	case !m.loaded && m.listErr != nil:
		b.WriteString(errorStyle.Render("Could not list booths: "+m.listErr.Error()) + "\n")
	case !m.loaded:
		b.WriteString(dimStyle.Render("Loading booths…") + "\n")
	case len(m.booths) == 0:
		b.WriteString(dimStyle.Render("No booths. Run `booth` in a project folder to start one.") + "\n")
	default:
		b.WriteString(m.table())
	}

	for _, warning := range m.warnings {
		b.WriteString(warnStyle.Render(m.fit(warning)) + "\n")
	}
	b.WriteString("\n")
	b.WriteString(m.statusLine() + "\n")
	b.WriteString(dimStyle.Render(m.fit(helpLine)))
	return b.String()
}

func (m model) titleLine() string {
	title := titleStyle.Render("booth dash")
	var parts []string
	if m.loaded {
		noun := "booths"
		if len(m.booths) == 1 {
			noun = "booth"
		}
		parts = append(parts, fmt.Sprintf("%d %s", len(m.booths), noun))
		parts = append(parts, "refreshed "+m.refreshedAt.Format("15:04:05"))
	}
	if m.loaded && m.listErr != nil {
		parts = append(parts, errorStyle.Render("refresh failed: "+m.listErr.Error()))
	}
	if len(parts) == 0 {
		return title
	}
	return title + dimStyle.Render(" · ") + dimStyle.Render(strings.Join(parts, " · "))
}

func (m model) statusLine() string {
	if m.confirm != nil {
		return confirmStyle.Render(m.fit(m.confirm.plan.Confirm + " [y/N]"))
	}
	if m.status == "" {
		return ""
	}
	if m.statusErr {
		return errorStyle.Render(m.fit(m.status))
	}
	return m.fit(m.status)
}

// column is one table column: its header and each booth's cell.
type column struct {
	header string
	cell   func(lifecycle.Booth) string
	max    int  // widest it may grow; 0 = no limit
	flex   bool // takes the width left over (the code path)
}

func (m model) columns() []column {
	cols := []column{{header: "NAME", cell: func(b lifecycle.Booth) string { return b.Name }, max: 32}}
	if m.multiEngine() {
		cols = append(cols, column{header: "ENGINE", cell: func(b lifecycle.Booth) string { return b.Engine }})
	}
	cols = append(cols,
		column{header: "STATUS", cell: m.statusCell},
		column{header: "VARIANT", cell: func(b lifecycle.Booth) string { return dashIfEmpty(b.Variant) }, max: 16},
		column{header: "PORT", cell: func(b lifecycle.Booth) string { return dashIfEmpty(b.Port) }},
		column{header: "AGE", cell: func(b lifecycle.Booth) string { return age(b.CreatedAt, m.deps.Now()) }},
		column{header: "CODE PATH", cell: func(b lifecycle.Booth) string { return m.shortPath(b.CodePath) }, flex: true},
	)
	return cols
}

func (m model) multiEngine() bool {
	for _, booth := range m.booths {
		if booth.Engine != m.booths[0].Engine {
			return true
		}
	}
	return false
}

func (m model) statusCell(b lifecycle.Booth) string {
	if state, ok := m.busy[boothKey(b)]; ok {
		return state
	}
	if b.Running() {
		return "Running"
	}
	return "Stopped"
}

func (m model) table() string {
	cols := m.columns()
	widths := make([]int, len(cols))
	for i, col := range cols {
		widths[i] = lipgloss.Width(col.header)
		for _, booth := range m.booths {
			widths[i] = max(widths[i], lipgloss.Width(col.cell(booth)))
		}
		if col.max > 0 {
			widths[i] = min(widths[i], col.max)
		}
	}
	// The flexible column gets what the others leave, never less than its header.
	if m.width > 0 {
		used := 2 // the cursor gutter
		for i, col := range cols {
			if !col.flex {
				used += widths[i] + 2
			}
		}
		for i, col := range cols {
			if col.flex {
				widths[i] = max(lipgloss.Width(col.header), min(widths[i], m.width-used))
			}
		}
	}

	render := func(cells []string) string {
		parts := make([]string, len(cells))
		for i, cell := range cells {
			if cols[i].flex {
				cell = truncateLeft(cell, widths[i])
			} else {
				cell = truncateRight(cell, widths[i])
			}
			parts[i] = cell + strings.Repeat(" ", widths[i]-lipgloss.Width(cell))
		}
		return strings.TrimRight(strings.Join(parts, "  "), " ")
	}

	var b strings.Builder
	headers := make([]string, len(cols))
	for i, col := range cols {
		headers[i] = col.header
	}
	b.WriteString("  " + headerStyle.Render(render(headers)) + "\n")

	rows := m.tableRows()
	end := min(len(m.booths), m.offset+rows)
	for i := m.offset; i < end; i++ {
		booth := m.booths[i]
		cells := make([]string, len(cols))
		for c, col := range cols {
			cells[c] = col.cell(booth)
		}
		line := render(cells)
		switch {
		case i == m.cursor:
			b.WriteString(cursorStyle.Render("› " + line))
		case m.busy[boothKey(booth)] != "":
			b.WriteString("  " + busyStyle.Render(line))
		case booth.Running():
			b.WriteString("  " + runningStyle.Render(line))
		default:
			b.WriteString("  " + line)
		}
		b.WriteString("\n")
	}
	return b.String()
}

// fit cuts a line to the screen width.
func (m model) fit(line string) string {
	if m.width <= 0 {
		return line
	}
	return truncateRight(line, m.width)
}

func (m model) shortPath(path string) string {
	if path == "" {
		return "-"
	}
	if m.deps.Home != "" && (path == m.deps.Home || strings.HasPrefix(path, m.deps.Home+"/")) {
		return "~" + strings.TrimPrefix(path, m.deps.Home)
	}
	return path
}

func dashIfEmpty(value string) string {
	if value == "" {
		return "-"
	}
	return value
}

// age is how long ago an RFC 3339 time was, in its largest unit: 45s, 12m, 3h, 5d.
func age(created string, now time.Time) string {
	at, err := time.Parse(time.RFC3339, created)
	if err != nil {
		return "-"
	}
	d := now.Sub(at)
	switch {
	case d < 0:
		return "0s"
	case d < time.Minute:
		return fmt.Sprintf("%ds", int(d.Seconds()))
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 48*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}

func truncateRight(s string, width int) string {
	if lipgloss.Width(s) <= width {
		return s
	}
	if width <= 1 {
		return string([]rune(s)[:max(0, width)])
	}
	runes := []rune(s)
	for lipgloss.Width(string(runes))+1 > width {
		runes = runes[:len(runes)-1]
	}
	return string(runes) + "…"
}

// truncateLeft keeps the end of a path, which is the part that tells booths apart.
func truncateLeft(s string, width int) string {
	if lipgloss.Width(s) <= width {
		return s
	}
	if width <= 1 {
		runes := []rune(s)
		return string(runes[len(runes)-max(0, width):])
	}
	runes := []rune(s)
	for lipgloss.Width(string(runes))+1 > width {
		runes = runes[1:]
	}
	return "…" + string(runes)
}
