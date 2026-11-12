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
	groupStyle   = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("75"))
)

const pickerHelpLine = "↑/↓ select · enter open · esc back"

// helpLines: what to look at or into, then what changes the booth.
var helpLines = []string{
	"↑/↓ move · i info · enter shell · o open · p ports · m message · e editor · K GitKraken",
	"s start · x stop · r restart · d remove · n new worktree · R refresh · q quit",
}

// chromeLines is everything but the table rows: title, blank, header, and
// below the table a blank, the status line and the two help lines.
const chromeLines = 7

// tableRows is how many booth rows fit on screen (all of them before the
// first WindowSizeMsg).
func (m model) tableRows() int {
	if m.height <= 0 {
		return max(1, len(m.rows))
	}
	rows := m.height - chromeLines - len(m.warnings)
	if m.compose != nil {
		rows -= composeLines
	}
	rows -= m.detailLines()
	return max(1, rows)
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
	m.offset = max(0, min(m.offset, max(0, len(m.rows)-rows)))
	// Show the header of the cursor's group when the cursor is its first row.
	if m.offset > 0 && m.offset == m.cursor && rows > 1 && m.rows[m.offset-1].header {
		m.offset--
	}
}

func (m model) View() string {
	var b strings.Builder
	b.WriteString(m.titleLine())
	b.WriteString("\n\n")

	if m.picker != nil {
		b.WriteString(m.pickerView())
		b.WriteString("\n")
		b.WriteString(m.statusLine() + "\n")
		b.WriteString(dimStyle.Render(m.fit(pickerHelpLine)))
		return b.String()
	}

	switch {
	case !m.loaded && m.listErr != nil:
		b.WriteString(errorStyle.Render("Could not list booths: "+m.listErr.Error()) + "\n")
	case !m.loaded:
		b.WriteString(dimStyle.Render("Loading booths…") + "\n")
	case len(m.rows) == 0:
		b.WriteString(dimStyle.Render("No booths. Run `booth` in a project folder to start one.") + "\n")
	default:
		b.WriteString(m.table())
	}

	for _, warning := range m.warnings {
		b.WriteString(warnStyle.Render(m.fit(warning)) + "\n")
	}
	help := helpLines
	if m.prompt != nil {
		help = promptHelpLines
	}
	if m.compose != nil {
		b.WriteString("\n")
		b.WriteString(m.composeView())
		help = composeHelpLines
	} else if m.detailShown() {
		b.WriteString("\n")
		b.WriteString(m.detailView())
	}
	b.WriteString("\n")
	b.WriteString(m.statusLine() + "\n")
	for i, line := range help {
		if i > 0 {
			b.WriteString("\n")
		}
		b.WriteString(dimStyle.Render(m.fit(line)))
	}
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
	if m.prompt != nil {
		return m.promptLine()
	}
	if m.confirm != nil {
		return confirmStyle.Render(m.fit(m.confirm.plan.Confirm + " [y/N]"))
	}
	if m.compose != nil && m.compose.err != "" {
		return errorStyle.Render(m.fit(m.compose.err))
	}
	if m.status == "" {
		return ""
	}
	if m.statusErr {
		return errorStyle.Render(m.fit(m.status))
	}
	return m.fit(m.status)
}

// pickerView lists the ports p offers to open.
func (m model) pickerView() string {
	p := m.picker
	var b strings.Builder
	b.WriteString(headerStyle.Render("Ports of "+p.booth.Name) + "\n")
	switch {
	case p.loading:
		b.WriteString(dimStyle.Render("Reading ports…") + "\n")
		return b.String()
	case p.err != nil:
		b.WriteString(errorStyle.Render(m.fit("Could not read ports: "+p.err.Error())) + "\n")
		return b.String()
	case len(p.ports) == 0:
		b.WriteString(dimStyle.Render(p.booth.Name+" publishes no TCP port.") + "\n")
		return b.String()
	}

	cells := make([][]string, 0, len(p.ports)+1)
	cells = append(cells, []string{"CONTAINER", "URL", "KIND", "SOURCE"})
	for _, port := range p.ports {
		kind := port.Kind
		if !port.Live {
			kind += " (not bound)"
		}
		cells = append(cells, []string{fmt.Sprint(port.ContainerPort), port.URL(), kind, port.Source})
	}
	widths := make([]int, 4)
	for _, row := range cells {
		for i, cell := range row {
			widths[i] = max(widths[i], lipgloss.Width(cell))
		}
	}
	line := func(row []string) string {
		parts := make([]string, len(row))
		for i, cell := range row {
			parts[i] = cell + strings.Repeat(" ", widths[i]-lipgloss.Width(cell))
		}
		return m.fit(strings.TrimRight(strings.Join(parts, "  "), " "))
	}
	b.WriteString("  " + headerStyle.Render(line(cells[0])) + "\n")
	for i, row := range cells[1:] {
		switch {
		case i == p.cursor:
			b.WriteString(cursorStyle.Render("› "+line(row)) + "\n")
		case !p.ports[i].Live:
			b.WriteString("  " + dimStyle.Render(line(row)) + "\n")
		default:
			b.WriteString("  " + line(row) + "\n")
		}
	}
	return b.String()
}

// column is one table column: its header and each row's cell.
type column struct {
	header string
	cell   func(row) string
	max    int  // widest it may grow; 0 = no limit
	flex   bool // takes the width left over (the code path)
}

func (m model) columns() []column {
	boothCell := func(f func(lifecycle.Booth) string) func(row) string {
		return func(r row) string {
			if r.booth == nil {
				return "-"
			}
			return f(*r.booth)
		}
	}
	cols := []column{{header: "NAME", cell: boothCell(func(b lifecycle.Booth) string { return b.Name }), max: 32}}
	if m.multiEngine() {
		cols = append(cols, column{header: "ENGINE", cell: boothCell(func(b lifecycle.Booth) string { return b.Engine })})
	}
	cols = append(cols, column{header: "STATUS", cell: m.statusCell})
	if len(m.repos) > 0 {
		cols = append(cols, column{header: "WORKTREE", cell: func(r row) string { return branchText(r.worktree) }, max: 32})
	}
	cols = append(cols,
		column{header: "VARIANT", cell: boothCell(func(b lifecycle.Booth) string { return dashIfEmpty(b.Variant) }), max: 16},
		column{header: "PORT", cell: boothCell(func(b lifecycle.Booth) string { return dashIfEmpty(b.Port) })},
		column{header: "AGE", cell: boothCell(func(b lifecycle.Booth) string { return age(b.CreatedAt, m.deps.Now()) })},
		column{header: "CODE PATH", cell: func(r row) string { return m.shortPath(r.path()) }, flex: true},
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

func (m model) statusCell(r row) string {
	if r.booth == nil {
		if busy, ok := m.busy[r.key()]; ok {
			return busy
		}
		if r.worktree != nil && r.worktree.Prunable {
			return "folder gone"
		}
		return "no booth"
	}
	b := *r.booth
	state := "Stopped"
	if busy, ok := m.busy[boothKey(b)]; ok {
		state = busy
	} else if b.Running() {
		state = "Running"
	}
	// A question waiting for the booth user's answer.
	if m.asking[boothKey(b)] > 0 {
		state += " ?"
	}
	return state
}

func (m model) table() string {
	cols := m.columns()
	widths := make([]int, len(cols))
	for i, col := range cols {
		widths[i] = lipgloss.Width(col.header)
		for _, r := range m.rows {
			if !r.header {
				widths[i] = max(widths[i], lipgloss.Width(col.cell(r)))
			}
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
	end := min(len(m.rows), m.offset+rows)
	for i := m.offset; i < end; i++ {
		r := m.rows[i]
		if r.header {
			b.WriteString(m.groupHeader(*r.repo) + "\n")
			continue
		}
		cells := make([]string, len(cols))
		for c, col := range cols {
			cells[c] = col.cell(r)
		}
		line := render(cells)
		switch {
		case i == m.cursor:
			b.WriteString(cursorStyle.Render("› " + line))
		case m.busy[r.key()] != "":
			b.WriteString("  " + busyStyle.Render(line))
		case r.booth == nil:
			b.WriteString("  " + dimStyle.Render(line))
		case r.booth.Running():
			b.WriteString("  " + runningStyle.Render(line))
		default:
			b.WriteString("  " + line)
		}
		b.WriteString("\n")
	}
	return b.String()
}

// groupHeader is a repository's line: its name, then where it is.
func (m model) groupHeader(repo lifecycle.Repo) string {
	name := repo.Name
	if repo.Here {
		name += " (here)"
	}
	line := groupStyle.Render(name)
	if repo.Root != "" {
		line += dimStyle.Render("  " + m.shortPath(repo.Root))
	}
	return line
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
