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
	"context"
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
	keyOpen    = "o"
	keyPorts   = "p"
	keyMessage = "m"
	keyDetail  = "i"
	keyNew     = "n"
	keyEditor  = "e"
	// GitKraken is K: g already jumps to the top.
	keyGitKraken = "K"
	keyRefresh   = "R"
)

// Deps is everything the dashboard does outside itself; tests replace it.
type Deps struct {
	// Snapshot lists the booths, plus warnings from engines that could not answer.
	Snapshot func() ([]lifecycle.Booth, []string, error)
	// Run runs the booth binary with args in dir ("" = the dashboard's own),
	// capturing its output.
	Run func(dir string, args []string) (string, error)
	// Repos finds the repositories to group booths under; nil shows a flat list.
	Repos func(booths []lifecycle.Booth) []lifecycle.Repo
	// Editor is the command that opens path in the user's editor; it gets the
	// terminal, so a terminal editor works too.
	Editor func(path string) (*exec.Cmd, error)
	// GitKraken opens path in GitKraken, and returns once it is launched.
	GitKraken func(path string) error
	// Command builds the booth binary command for an interactive action, to
	// run in dir ("" = the dashboard's own).
	Command func(dir string, args []string) *exec.Cmd
	// Message runs `booth message send` with args, capturing its output. A
	// question waits for the booth user's answer, so it can run for minutes;
	// ctx is cancelled when the dashboard exits, to not leave it behind.
	Message func(ctx context.Context, args []string) (string, error)
	// Open opens a URL in the host's browser.
	Open func(url string) error
	// Ports lists a running booth's exposed ports (`booth expose list`).
	Ports func(booth lifecycle.Booth) ([]lifecycle.ExposedPort, error)
	// The detail pane's parts (i), for one booth.
	Stats   func(booth lifecycle.Booth) (lifecycle.BoothStats, error)
	State   func(booth lifecycle.Booth) (lifecycle.BoothState, error)
	Pending func(booth lifecycle.Booth) ([]lifecycle.PendingMessage, error)
	Logs    func(booth lifecycle.Booth, lines int) (string, error)
	// Interval between refreshes.
	Interval time.Duration
	// DetailInterval between reloads of the detail pane (default 5s): it
	// costs an exec and a stats sample, so it is slower than the table.
	DetailInterval time.Duration
	// Home is shortened to ~ in code paths ("" leaves paths as they are).
	Home string
	// Now is the clock (ages, the refresh time).
	Now func() time.Time
}

type model struct {
	deps Deps

	booths   []lifecycle.Booth
	repos    []lifecycle.Repo
	rows     []row  // what the table shows: headers, booths, bare worktrees
	cursor   int    // index in rows; never a header once there is a row
	offset   int    // first row shown when the table is taller than the screen
	selected string // key of the selected row, kept across refreshes
	busy     map[string]string
	asking   map[string]int // questions sent and not yet answered, per booth

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
	picker    *portPicker
	compose   *compose
	prompt    *namePrompt

	detailOpen bool
	detail     *detailPane
	detailGen  int // bumped for each booth the pane loads
	detailSeq  int // bumped each time the pane opens; ends the old tick chain

	// ctx ends with the dashboard; questions still waiting are cancelled.
	ctx    context.Context
	cancel context.CancelFunc

	width, height int
}

// portPicker is the list of a booth's exposed ports shown by p, to open one.
type portPicker struct {
	booth   lifecycle.Booth
	ports   []lifecycle.ExposedPort // TCP ports with a host binding
	cursor  int
	loading bool
	err     error
}

type pendingConfirm struct {
	plan      plan
	key, name string
}

type (
	snapshotMsg struct {
		seq      int
		booths   []lifecycle.Booth
		repos    []lifecycle.Repo
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
	portsMsg struct {
		key   string
		ports []lifecycle.ExposedPort
		err   error
	}
	messageDoneMsg struct {
		key, name string
		kind      messageKind
		output    string
		err       error
	}
	openDoneMsg struct {
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
	if deps.DetailInterval <= 0 {
		deps.DetailInterval = 5 * time.Second
	}
	ctx, cancel := context.WithCancel(context.Background())
	return model{deps: deps, busy: map[string]string{}, asking: map[string]int{},
		loading: true, fetchSeq: 1, ctx: ctx, cancel: cancel}
}

func (m model) Init() tea.Cmd {
	return tea.Batch(m.fetch(1), m.tick())
}

func (m model) fetch(seq int) tea.Cmd {
	snapshot, findRepos := m.deps.Snapshot, m.deps.Repos
	return func() tea.Msg {
		booths, warnings, err := snapshot()
		var repos []lifecycle.Repo
		if err == nil && findRepos != nil {
			repos = findRepos(booths)
		}
		return snapshotMsg{seq: seq, booths: booths, repos: repos, warnings: warnings, err: err}
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

// Update handles msg, then keeps the detail pane on the selected booth.
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	next, cmd := m.update(msg)
	m, ok := next.(model)
	if !ok {
		return next, cmd
	}
	m, load := m.syncDetail()
	return m, tea.Batch(cmd, load)
}

func (m model) update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case detailMsg:
		return m.applyDetail(msg), nil

	case detailTickMsg:
		if !m.detailOpen || msg.seq != m.detailSeq {
			return m, nil
		}
		m, load := m.loadDetail()
		return m, tea.Batch(load, m.detailTick())

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
			m.repos = msg.repos
			m.rows = buildRows(m.booths, m.repos)
			m.refreshedAt = m.deps.Now()
			m.reselect()
		}
		return m, nil

	case actionDoneMsg:
		delete(m.busy, msg.key)
		if msg.err != nil && msg.plan.Verb == "remove worktree" {
			m.setStatus(keptWorktree(msg.name, msg.output, msg.err), true)
		} else if msg.err != nil {
			m.setStatus(failure(msg.plan.Verb, msg.name, msg.output, msg.err), true)
		} else {
			m.setStatus(msg.plan.Done, false)
		}
		return m.refresh(true)

	case portsMsg:
		if m.picker == nil || boothKey(m.picker.booth) != msg.key {
			return m, nil // closed, or opened again for another booth
		}
		picker := *m.picker
		picker.loading = false
		picker.err = msg.err
		picker.ports = nil
		for _, port := range msg.ports {
			if port.URL() != "" {
				picker.ports = append(picker.ports, port)
			}
		}
		m.picker = &picker
		return m, nil

	case messageDoneMsg:
		return m.messageDone(msg)

	case openDoneMsg:
		if msg.err != nil {
			m.setStatus(msg.err.Error(), true)
		} else {
			m.setStatus(msg.plan.Done, false)
		}
		return m, nil

	case execDoneMsg:
		if msg.err != nil {
			m.setStatus(failure(msg.plan.Verb, msg.name, "", msg.err), true)
		} else {
			m.setStatus(msg.plan.Done, false)
		}
		return m.refresh(true)

	case tea.KeyMsg:
		if m.compose != nil {
			return m.handleComposeKey(msg)
		}
		if m.prompt != nil {
			return m.handlePromptKey(msg)
		}
		return m.handleKey(msg.String())
	}
	return m, nil
}

func (m model) handleKey(key string) (tea.Model, tea.Cmd) {
	if m.picker != nil {
		return m.handlePickerKey(key)
	}
	if m.confirm != nil {
		pending := *m.confirm
		m.confirm = nil
		if key == "y" || key == "Y" {
			return m.execute(pending.key, pending.name, pending.plan)
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
		m.move(-len(m.rows))
	case "end", "G":
		m.move(len(m.rows))
	case "pgup":
		m.move(-m.tableRows())
	case "pgdown":
		m.move(m.tableRows())
	case keyRefresh:
		m.setStatus("", false)
		return m.refresh(true)
	case keyDetail:
		return m.toggleDetail()
	case keyNew:
		r, ok := m.currentRow()
		if !ok || r.repo == nil || r.repo == otherBooths {
			m.setStatus("Select a row of a repository to add a worktree to it.", false)
			return m, nil
		}
		m.setStatus("", false)
		m.prompt = &namePrompt{repo: r.repo}
		return m, nil
	case keyEditor, keyGitKraken:
		r, ok := m.currentRow()
		if !ok || r.path() == "" {
			return m, nil
		}
		return m.openIn(key, r.path())
	}

	r, ok := m.currentRow()
	if !ok {
		return m, nil
	}
	if r.booth == nil {
		// A worktree without a booth.
		if state, busy := m.busy[r.key()]; busy {
			m.setStatus(r.worktree.Name()+" is "+strings.TrimSuffix(state, "…")+"; wait for it to finish.", false)
			return m, nil
		}
		p, reason := planForWorktree(key, r)
		if reason != "" {
			m.setStatus(reason, false)
			return m, nil
		}
		if p.Verb == "" {
			return m, nil
		}
		return m.run(r.key(), r.worktree.Name(), p)
	}

	booth := *r.booth
	switch key {
	case keyPorts:
		if !booth.Running() {
			m.setStatus(booth.Name+" is not running; use s to start it.", false)
			return m, nil
		}
		m.setStatus("", false)
		m.picker = &portPicker{booth: booth, loading: true}
		ports, key := m.deps.Ports, boothKey(booth)
		return m, func() tea.Msg {
			list, err := ports(booth)
			return portsMsg{key: key, ports: list, err: err}
		}
	case keyMessage:
		if !booth.Running() {
			m.setStatus(booth.Name+" is not running; use s to start it.", false)
			return m, nil
		}
		m.setStatus("", false)
		m.compose = &compose{booth: booth}
		m.clampOffset()
		return m, nil
	case keyStart, keyStop, keyRestart, keyRemove, keyShell, keyOpen:
		if state, busy := m.busy[boothKey(booth)]; busy {
			m.setStatus(booth.Name+" is "+strings.TrimSuffix(state, "…")+"; wait for it to finish.", false)
			return m, nil
		}
		p, reason := planFor(key, booth)
		if reason != "" {
			m.setStatus(reason, false)
			return m, nil
		}
		return m.run(boothKey(booth), booth.Name, p)
	}
	return m, nil
}

// run asks first when the plan says so, else executes it.
func (m model) run(key, name string, p plan) (tea.Model, tea.Cmd) {
	if p.Confirm != "" {
		m.confirm = &pendingConfirm{plan: p, key: key, name: name}
		return m, nil
	}
	return m.execute(key, name, p)
}

// execute carries out p for the row named key (its busy state) and name (in
// messages).
func (m model) execute(key, name string, p plan) (tea.Model, tea.Cmd) {
	if p.URL != "" {
		// Opening a page changes nothing about the booth: no busy row, no refresh.
		m.setStatus("", false)
		open, url := m.deps.Open, p.URL
		return m, func() tea.Msg { return openDoneMsg{name: name, plan: p, err: open(url)} }
	}
	if p.Interactive {
		m.setStatus("", false)
		done := func(err error) tea.Msg { return execDoneMsg{name: name, plan: p, err: err} }
		cmd := m.deps.Command(p.Dir, p.Args)
		if p.Hold {
			return m, tea.Exec(&holdOnFailure{cmd: cmd, what: p.Verb + " " + name}, done)
		}
		return m, tea.ExecProcess(cmd, done)
	}
	if p.Busy != "" {
		m.busy[key] = p.Busy
		m.setStatus("", false)
	}
	run := m.deps.Run
	return m, func() tea.Msg {
		output, err := run(p.Dir, p.Args)
		return actionDoneMsg{key: key, name: name, plan: p, output: output, err: err}
	}
}

func (m model) handlePickerKey(key string) (tea.Model, tea.Cmd) {
	picker := *m.picker
	switch key {
	case "esc", "q", keyPorts:
		m.picker = nil
		return m, nil
	case "ctrl+c":
		return m, tea.Quit
	case "up", "k":
		picker.cursor = max(0, picker.cursor-1)
	case "down", "j":
		picker.cursor = max(0, min(len(picker.ports)-1, picker.cursor+1))
	case "enter", keyOpen:
		if picker.cursor >= len(picker.ports) {
			return m, nil
		}
		url := picker.ports[picker.cursor].URL()
		m.picker = nil
		return m.execute(boothKey(picker.booth), picker.booth.Name, plan{Verb: "open", URL: url, Done: "Opened " + url + " in your browser."})
	}
	m.picker = &picker
	return m, nil
}

func (m *model) setStatus(status string, isErr bool) {
	m.status, m.statusErr = status, isErr
}

// currentRow is the selected row (never a header).
func (m model) currentRow() (row, bool) {
	if m.cursor < 0 || m.cursor >= len(m.rows) || m.rows[m.cursor].header {
		return row{}, false
	}
	return m.rows[m.cursor], true
}

// current is the selected booth, when the selected row has one.
func (m model) current() (lifecycle.Booth, bool) {
	r, ok := m.currentRow()
	if !ok || r.booth == nil {
		return lifecycle.Booth{}, false
	}
	return *r.booth, true
}

// move steps the cursor delta selectable rows, skipping headers.
func (m *model) move(delta int) {
	var selectable []int
	at := 0
	for i, r := range m.rows {
		if r.header {
			continue
		}
		if i <= m.cursor {
			at = len(selectable)
		}
		selectable = append(selectable, i)
	}
	if len(selectable) == 0 {
		return
	}
	m.cursor = selectable[max(0, min(len(selectable)-1, at+delta))]
	m.selected = m.rows[m.cursor].key()
	m.clampOffset()
}

// reselect keeps the cursor on the same row after a refresh. A worktree that
// gained a booth keeps the cursor on that booth; a row that is gone leaves it
// at the same place.
func (m *model) reselect() {
	for i, r := range m.rows {
		if !r.header && r.key() == m.selected {
			m.cursor = i
			m.clampOffset()
			return
		}
	}
	if strings.HasPrefix(m.selected, "worktree:") {
		path := strings.TrimPrefix(m.selected, "worktree:")
		for i, r := range m.rows {
			if !r.header && r.worktree != nil && r.worktree.Path == path {
				m.cursor = i
				m.selected = r.key()
				m.clampOffset()
				return
			}
		}
	}
	m.cursor = max(0, min(len(m.rows)-1, m.cursor))
	// Land on a selectable row: the next one, else the one before.
	m.move(0)
	if _, ok := m.currentRow(); !ok {
		m.move(1)
	}
	if r, ok := m.currentRow(); ok {
		m.selected = r.key()
	} else {
		m.selected = ""
	}
	m.clampOffset()
}

// keptWorktree is the status line when `booth worktree remove` refused: what
// is in the way (its "  - " lines), not only its closing advice.
func keptWorktree(name, output string, err error) string {
	var why []string
	for _, line := range strings.Split(output, "\n") {
		if reason, ok := strings.CutPrefix(line, "  - "); ok {
			why = append(why, strings.TrimSpace(reason))
		}
	}
	if len(why) == 0 {
		return failure("remove worktree", name, output, err)
	}
	return "Kept worktree " + name + ": " + strings.Join(why, "; ") + ". Nothing was removed."
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
