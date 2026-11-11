// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package dash is `booth dash`: a full-screen table of every booth on the
// machine, refreshed by polling, where each row is the anchor for actions on
// that booth. It reads booths through lifecycle.Snapshot and acts by running
// the booth binary itself (`booth stop --name … --engine …`), so every action
// behaves exactly as it does from the command line.
package dash

import (
	"os/exec"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// Keys. Kept as constants so actions.go and the help line agree.
const (
	keyStart   = "s"
	keyStop    = "x"
	keyRestart = "r"
	keyRemove  = "d"
	keyShell   = "enter"
	keyRefresh = "R"
)

// Deps is everything the dashboard does outside itself; tests replace it.
type Deps struct {
	// Snapshot lists the booths, plus warnings from engines that could not answer.
	Snapshot func() ([]lifecycle.Booth, []string, error)
	// Run runs the booth binary with args, capturing its output.
	Run func(args []string) (string, error)
	// Command builds the booth binary command for an interactive action.
	Command func(args []string) *exec.Cmd
	// Interval between refreshes.
	Interval time.Duration
	// Home is shortened to ~ in code paths ("" leaves paths as they are).
	Home string
	// Now is the clock (ages, the refresh time).
	Now func() time.Time
}

type model struct {
	deps Deps

	booths   []lifecycle.Booth
	cursor   int
	offset   int    // first row shown when the table is taller than the screen
	selected string // key of the selected booth, kept across refreshes
	busy     map[string]string

	loading     bool // a snapshot is in flight
	fetchSeq    int  // the latest snapshot asked for
	appliedSeq  int  // the latest snapshot shown; an older one arriving late is dropped
	loaded      bool // at least one snapshot arrived
	listErr     error
	warnings    []string
	refreshedAt time.Time

	status    string
	statusErr bool
	confirm   *pendingConfirm

	width, height int
}

type pendingConfirm struct {
	plan  plan
	booth lifecycle.Booth
}

type (
	snapshotMsg struct {
		seq      int
		booths   []lifecycle.Booth
		warnings []string
		err      error
	}
	tickMsg       struct{}
	actionDoneMsg struct {
		key, name string
		plan      plan
		output    string
		err       error
	}
	execDoneMsg struct {
		name string
		plan plan
		err  error
	}
)

func boothKey(b lifecycle.Booth) string { return b.Name + "@" + b.Engine }

func newModel(deps Deps) model {
	if deps.Interval <= 0 {
		deps.Interval = 2 * time.Second
	}
	if deps.Now == nil {
		deps.Now = time.Now
	}
	return model{deps: deps, busy: map[string]string{}, loading: true, fetchSeq: 1}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(m.fetch(1), m.tick())
}

func (m model) fetch(seq int) tea.Cmd {
	snapshot := m.deps.Snapshot
	return func() tea.Msg {
		booths, warnings, err := snapshot()
		return snapshotMsg{seq: seq, booths: booths, warnings: warnings, err: err}
	}
}

func (m model) tick() tea.Cmd {
	return tea.Tick(m.deps.Interval, func(time.Time) tea.Msg { return tickMsg{} })
}

// refresh starts a snapshot unless one is already in flight, so a slow engine
// never piles up calls. force starts one anyway: after an action, a snapshot
// that began before the action finished may not show its result.
func (m model) refresh(force bool) (model, tea.Cmd) {
	if m.loading && !force {
		return m, nil
	}
	m.loading = true
	m.fetchSeq++
	return m, m.fetch(m.fetchSeq)
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.clampOffset()
		return m, nil

	case tickMsg:
		m, cmd := m.refresh(false)
		return m, tea.Batch(cmd, m.tick())

	case snapshotMsg:
		if msg.seq <= m.appliedSeq {
			return m, nil
		}
		m.appliedSeq = msg.seq
		if msg.seq == m.fetchSeq {
			m.loading = false
		}
		m.listErr = msg.err
		m.warnings = msg.warnings
		if msg.err == nil {
			m.loaded = true
			m.booths = msg.booths
			m.refreshedAt = m.deps.Now()
			m.reselect()
		}
		return m, nil

	case actionDoneMsg:
		delete(m.busy, msg.key)
		if msg.err != nil {
			m.setStatus(failure(msg.plan.Verb, msg.name, msg.output, msg.err), true)
		} else {
			m.setStatus(msg.plan.Done, false)
		}
		return m.refresh(true)

	case execDoneMsg:
		if msg.err != nil {
			m.setStatus(failure(msg.plan.Verb, msg.name, "", msg.err), true)
		} else {
			m.setStatus("", false)
		}
		return m.refresh(true)

	case tea.KeyMsg:
		return m.handleKey(msg.String())
	}
	return m, nil
}

func (m model) handleKey(key string) (tea.Model, tea.Cmd) {
	if m.confirm != nil {
		pending := *m.confirm
		m.confirm = nil
		if key == "y" || key == "Y" {
			return m.execute(pending.booth, pending.plan)
		}
		m.setStatus("Cancelled.", false)
		return m, nil
	}

	switch key {
	case "q", "ctrl+c":
		return m, tea.Quit
	case "up", "k":
		m.move(-1)
	case "down", "j":
		m.move(1)
	case "home", "g":
		m.move(-len(m.booths))
	case "end", "G":
		m.move(len(m.booths))
	case "pgup":
		m.move(-m.tableRows())
	case "pgdown":
		m.move(m.tableRows())
	case keyRefresh:
		m.setStatus("", false)
		return m.refresh(true)
	case keyStart, keyStop, keyRestart, keyRemove, keyShell:
		booth, ok := m.current()
		if !ok {
			return m, nil
		}
		if state, busy := m.busy[boothKey(booth)]; busy {
			m.setStatus(booth.Name+" is "+strings.TrimSuffix(state, "…")+"; wait for it to finish.", false)
			return m, nil
		}
		p, reason := planFor(key, booth)
		if reason != "" {
			m.setStatus(reason, false)
			return m, nil
		}
		if p.Confirm != "" {
			m.confirm = &pendingConfirm{plan: p, booth: booth}
			return m, nil
		}
		return m.execute(booth, p)
	}
	return m, nil
}

func (m model) execute(booth lifecycle.Booth, p plan) (tea.Model, tea.Cmd) {
	if p.Interactive {
		m.setStatus("", false)
		name := booth.Name
		return m, tea.ExecProcess(m.deps.Command(p.Args), func(err error) tea.Msg {
			return execDoneMsg{name: name, plan: p, err: err}
		})
	}
	key := boothKey(booth)
	m.busy[key] = p.Busy
	m.setStatus("", false)
	run := m.deps.Run
	name := booth.Name
	return m, func() tea.Msg {
		output, err := run(p.Args)
		return actionDoneMsg{key: key, name: name, plan: p, output: output, err: err}
	}
}

func (m *model) setStatus(status string, isErr bool) {
	m.status, m.statusErr = status, isErr
}

func (m model) current() (lifecycle.Booth, bool) {
	if m.cursor < 0 || m.cursor >= len(m.booths) {
		return lifecycle.Booth{}, false
	}
	return m.booths[m.cursor], true
}

func (m *model) move(delta int) {
	if len(m.booths) == 0 {
		return
	}
	m.cursor = max(0, min(len(m.booths)-1, m.cursor+delta))
	m.selected = boothKey(m.booths[m.cursor])
	m.clampOffset()
}

// reselect keeps the cursor on the same booth after a refresh; when that booth
// is gone, it stays at the same row number.
func (m *model) reselect() {
	if len(m.booths) == 0 {
		m.cursor, m.selected = 0, ""
		m.clampOffset()
		return
	}
	for i, booth := range m.booths {
		if boothKey(booth) == m.selected {
			m.cursor = i
			m.clampOffset()
			return
		}
	}
	m.cursor = max(0, min(len(m.booths)-1, m.cursor))
	m.selected = boothKey(m.booths[m.cursor])
	m.clampOffset()
}

// failure is the status line for a failed action: the command's own last
// line of output when it printed one (usually its "Error: …"), otherwise err.
func failure(verb, name, output string, err error) string {
	lines := strings.Split(strings.TrimSpace(output), "\n")
	if last := strings.TrimSpace(lines[len(lines)-1]); last != "" {
		return last
	}
	return "Failed to " + verb + " " + name + ": " + err.Error()
}
