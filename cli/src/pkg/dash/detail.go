// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// detailPane is what i shows below the table about the selected booth. Each
// part loads on its own, so a slow one never holds up the others, and one
// that fails shows why while the rest still show.
type detailPane struct {
	booth lifecycle.Booth
	key   string
	gen   int // which booth this pane is for; answers for an older one are dropped

	stats    part[lifecycle.BoothStats]
	state    part[lifecycle.BoothState]
	ports    part[[]lifecycle.ExposedPort]
	pending  part[[]lifecycle.PendingMessage]
	logs     part[string]
	inflight int
}

type part[T any] struct {
	value  T
	err    error
	loaded bool
}

func (p *part[T]) set(value T, err error) { p.value, p.err, p.loaded = value, err, true }

type (
	// detailMsg is one part of the pane, loaded.
	detailMsg struct {
		gen   int
		apply func(*detailPane)
	}
	// detailTickMsg reloads the pane; seq ends the chain when the pane closes.
	detailTickMsg struct{ seq int }
)

// logLinesWanted is how many log lines the pane asks for; it shows as many of
// them as fit.
const logLinesWanted = 20

// detailFixedLines: a blank, the header, the Image, Booth dir, Viewers, Idle,
// Ports and Messages rows, and the Logs row.
const detailFixedLines = 9

func (m model) toggleDetail() (model, tea.Cmd) {
	if m.detailOpen {
		m.detailOpen, m.detail = false, nil
		m.clampOffset()
		return m, nil
	}
	// One pane at a time: i takes c's place.
	m.configOpen, m.config = false, nil
	m.detailOpen = true
	m.detailSeq++
	return m, m.detailTick()
}

func (m model) detailTick() tea.Cmd {
	seq := m.detailSeq
	return tea.Tick(m.deps.DetailInterval, func(time.Time) tea.Msg { return detailTickMsg{seq: seq} })
}

// syncDetail points the open pane at the selected booth: a new pane (and a
// load) when the selection moved, the fresh row otherwise.
func (m model) syncDetail() (model, tea.Cmd) {
	if !m.detailOpen {
		return m, nil
	}
	booth, ok := m.current()
	if !ok {
		m.detail = nil
		return m, nil
	}
	if m.detail != nil && m.detail.key == boothKey(booth) {
		pane := *m.detail
		pane.booth = booth
		m.detail = &pane
		return m, nil
	}
	m.detailGen++
	m.detail = &detailPane{booth: booth, key: boothKey(booth), gen: m.detailGen}
	m.clampOffset()
	return m.loadDetail()
}

// loadDetail asks for every part of the pane that applies to the booth's
// state, unless the last load is still out.
func (m model) loadDetail() (model, tea.Cmd) {
	if m.detail == nil || m.detail.inflight > 0 {
		return m, nil
	}
	pane := *m.detail
	booth, gen, deps := pane.booth, pane.gen, m.deps
	load := func(apply func() func(*detailPane)) tea.Cmd {
		return func() tea.Msg { return detailMsg{gen: gen, apply: apply()} }
	}
	cmds := []tea.Cmd{
		load(func() func(*detailPane) {
			out, err := deps.Logs(booth, logLinesWanted)
			return func(p *detailPane) { p.logs.set(out, err) }
		}),
		load(func() func(*detailPane) {
			list, err := deps.Pending(booth)
			return func(p *detailPane) { p.pending.set(list, err) }
		}),
	}
	if booth.Running() {
		cmds = append(cmds,
			load(func() func(*detailPane) {
				stats, err := deps.Stats(booth)
				return func(p *detailPane) { p.stats.set(stats, err) }
			}),
			load(func() func(*detailPane) {
				state, err := deps.State(booth)
				return func(p *detailPane) { p.state.set(state, err) }
			}),
			load(func() func(*detailPane) {
				ports, err := deps.Ports(booth)
				return func(p *detailPane) { p.ports.set(ports, err) }
			}),
		)
	}
	pane.inflight = len(cmds)
	m.detail = &pane
	return m, tea.Batch(cmds...)
}

func (m model) applyDetail(msg detailMsg) model {
	if m.detail == nil || m.detail.gen != msg.gen {
		return m
	}
	pane := *m.detail
	msg.apply(&pane)
	pane.inflight = max(0, pane.inflight-1)
	m.detail = &pane
	return m
}

// detailShown: the pane is drawn (the compose box takes its place while open).
func (m model) detailShown() bool {
	return m.detailOpen && m.detail != nil && m.compose == nil
}

// logLines is how many log lines the pane shows: what is left once the table
// keeps a few rows, at most logLinesWanted.
func (m model) logLines() int {
	if m.height <= 0 {
		return logLinesWanted
	}
	keep := max(1, min(len(m.booths), 3))
	left := m.height - chromeLines - len(m.warnings) - detailFixedLines - keep
	return max(0, min(logLinesWanted, left))
}

// logShown is how many log lines the pane draws: the log's own length, up to
// what fits, so a short log leaves its room to the table.
func (m model) logShown() int {
	p := m.detail
	if p == nil || !p.logs.loaded || p.logs.err != nil {
		return 0
	}
	return len(logTail(p.logs.value, m.logLines()))
}

func (m model) detailLines() int {
	if !m.detailShown() {
		return 0
	}
	return detailFixedLines + m.logShown()
}

// detailView is the pane.
func (m model) detailView() string {
	p := m.detail
	b := p.booth
	now := m.deps.Now()
	var out strings.Builder

	header := []string{b.Name}
	if b.Running() {
		header = append(header, "Running")
		if up := since(b.StartedAt, now); up != "" {
			header = append(header, "up "+up)
		}
		switch {
		case !p.stats.loaded:
			header = append(header, "CPU …")
		case p.stats.err != nil:
			header = append(header, "stats: "+p.stats.err.Error())
		default:
			header = append(header, "CPU "+p.stats.value.CPU, "MEM "+p.stats.value.Memory+" ("+p.stats.value.MemPerc+")")
		}
	} else {
		header = append(header, "Stopped")
		if ago := since(b.FinishedAt, now); ago != "" {
			header = append(header, "stopped "+ago+" ago")
		}
	}
	out.WriteString(headerStyle.Render(m.fit(strings.Join(header, " · "))) + "\n")

	row := func(name, value string) {
		label := "  " + name + strings.Repeat(" ", 10-len(name))
		out.WriteString(dimStyle.Render(label) + m.fitTo(value, len(label)) + "\n")
	}
	row("Image", m.imageText(b))
	row("Booth dir", m.boothDirText(b))
	if b.Running() {
		row("Viewers", partText(p.state, func(s lifecycle.BoothState) string { return viewersText(s.Presence) }))
		row("Idle", partText(p.state, func(s lifecycle.BoothState) string { return idleText(s.Idle, now) }))
		row("Ports", partText(p.ports, portsText))
	} else {
		row("Viewers", "-")
		row("Idle", "-")
		row("Ports", "-")
	}
	row("Messages", partText(p.pending, messagesText))

	switch {
	case !p.logs.loaded:
		row("Logs", "…")
	case p.logs.err != nil:
		row("Logs", "- ("+p.logs.err.Error()+")")
	default:
		lines := logTail(p.logs.value, m.logLines())
		if len(lines) == 0 {
			row("Logs", "(empty)")
		} else if len(lines) == 1 {
			row("Logs", "last line · l shows the whole log")
		} else {
			row("Logs", fmt.Sprintf("last %d lines · l shows the whole log", len(lines)))
		}
		for _, line := range lines {
			out.WriteString("    " + dimStyle.Render(m.fitTo(line, 4)) + "\n")
		}
	}
	return out.String()
}

// fitTo cuts a value so that, after indent cells, the line fits the screen.
func (m model) fitTo(value string, indent int) string {
	if m.width <= 0 {
		return value
	}
	return truncateRight(value, max(1, m.width-indent))
}

func partText[T any](p part[T], show func(T) string) string {
	switch {
	case !p.loaded:
		return "…"
	case p.err != nil:
		return "- (" + p.err.Error() + ")"
	}
	return show(p.value)
}

func viewersText(p lifecycle.BoothPresence) string {
	if p.Viewers == 0 {
		return "nobody"
	}
	text := fmt.Sprintf("%d viewing", p.Viewers)
	if p.Background > 0 {
		text += fmt.Sprintf(" (%d in background)", p.Background)
	}
	return text
}

func idleText(idle lifecycle.BoothIdle, now time.Time) string {
	switch {
	case !idle.Enabled:
		return "off"
	case idle.Disabled:
		return "disabled until resumed"
	case idle.PauseUntil > now.Unix():
		return "paused until " + time.Unix(idle.PauseUntil, 0).In(now.Location()).Format("15:04")
	}
	return "asks after " + shortDuration(idle.IdleTime) + " idle, then shuts down " +
		shortDuration(idle.ShutdownTime) + " later"
}

func portsText(ports []lifecycle.ExposedPort) string {
	var parts []string
	for _, port := range ports {
		if url := port.URL(); url != "" {
			parts = append(parts, fmt.Sprintf("%d %s", port.ContainerPort, url))
		}
	}
	if len(parts) == 0 {
		return "none"
	}
	return strings.Join(parts, " · ")
}

func messagesText(pending []lifecycle.PendingMessage) string {
	if len(pending) == 0 {
		return "none waiting"
	}
	titles := make([]string, len(pending))
	for i, msg := range pending {
		titles[i] = msg.Title
	}
	return fmt.Sprintf("%d waiting: %s", len(pending), strings.Join(titles, " · "))
}

// shortDuration is seconds as 45s, 30m, 2h or 1h30m.
func shortDuration(seconds int) string {
	d := time.Duration(seconds) * time.Second
	text := d.String()
	if strings.HasSuffix(text, "m0s") {
		text = strings.TrimSuffix(text, "0s")
	}
	if strings.HasSuffix(text, "h0m") {
		text = strings.TrimSuffix(text, "0m")
	}
	return text
}

// since is how long ago an engine time was, or "" when the engine gave none
// (Docker's zero time is year 1).
func since(at string, now time.Time) string {
	t, err := time.Parse(time.RFC3339Nano, at)
	if err != nil || t.Year() < 2000 {
		return ""
	}
	return age(at, now)
}

var controlSequence = regexp.MustCompile(`\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07\x1b]*(\x07|\x1b\\)|[\x00-\x08\x0b-\x1f\x7f]`)

// logTail is the last n non-empty lines of a log, with terminal escapes and
// carriage-return progress removed so they cannot disturb the screen.
func logTail(log string, n int) []string {
	if n <= 0 {
		return nil
	}
	var lines []string
	for _, line := range strings.Split(log, "\n") {
		if i := strings.LastIndex(line, "\r"); i >= 0 && i < len(line)-1 {
			line = line[i+1:]
		}
		line = strings.TrimRight(controlSequence.ReplaceAllString(line, ""), " ")
		if line != "" {
			lines = append(lines, line)
		}
	}
	if len(lines) > n {
		lines = lines[len(lines)-n:]
	}
	return lines
}

// imageText is the Image row: whether the booth is what `booth` would build
// for it now, and if not, why and how to bring it up to date.
func (m model) imageText(b lifecycle.Booth) string {
	f := m.fresh[boothKey(b)]
	var why []string
	if f.Older {
		why = append(why, "built with "+dashIfEmpty(b.Version)+"; its project now builds "+f.Want)
	}
	if f.Rebuilt {
		why = append(why, "its image "+b.ImageRef+" was rebuilt since")
	}
	if len(why) == 0 {
		if b.Version == "" {
			return "-"
		}
		return "up to date (" + b.Version + ")"
	}
	return strings.Join(why, "; ") + ". To update: booth remove --force --name " + b.Name +
		" (a persisted home goes with it), then run booth in its folder"
}

// boothDirText is the .booth the booth reads: its folder's, or an express
// booth's own (marked, as that is not the folder's config).
func (m model) boothDirText(b lifecycle.Booth) string {
	if b.BoothDir != "" {
		return m.shortPath(b.BoothDir) + " (express)"
	}
	if b.CodePath == "" {
		return "-"
	}
	return m.shortPath(filepath.Join(b.CodePath, ".booth"))
}
