// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"bufio"
	"fmt"
	"io"
	"os/exec"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// Selecting several rows (shift+↑/↓) extends a range from the row the first
// shift+arrow was pressed on (the anchor) to the cursor. While more than one
// row is selected, h, s, x, r, delete and ctrl+↑/↓ act on all of them; every other
// key still acts on the row under the cursor. A plain ↑/↓ or esc ends it, and
// so does an action once it is carried out (moving the rows keeps it, to move
// them again). The range is held by row key, so it stays on its rows across
// refreshes.

const (
	keyExtendUp   = "shift+up"
	keyExtendDown = "shift+down"
)

// selectionRange is the first and last selected row; ok is false when fewer
// than two rows are selected.
func (m model) selectionRange() (lo, hi int, ok bool) {
	if m.anchor == "" || m.cursor < 0 || m.cursor >= len(m.rows) {
		return 0, 0, false
	}
	for i, r := range m.rows {
		if r.key() == m.anchor {
			if i == m.cursor {
				return 0, 0, false
			}
			return min(i, m.cursor), max(i, m.cursor), true
		}
	}
	return 0, 0, false
}

// selection is the selected rows, top to bottom; nil when fewer than two are.
func (m model) selection() []row {
	lo, hi, ok := m.selectionRange()
	if !ok {
		return nil
	}
	return m.rows[lo : hi+1]
}

// extend moves the cursor delta rows and keeps the rows from the anchor to it
// selected. The first shift+arrow makes the row it starts on the anchor.
func (m model) extend(delta int) (tea.Model, tea.Cmd) {
	r, ok := m.currentRow()
	if !ok {
		return m, nil
	}
	if !m.hasRow(m.anchor) {
		m.anchor = r.key()
	}
	m.move(delta)
	m.setStatus("", false)
	return m, nil
}

func (m model) hasRow(key string) bool {
	if key == "" {
		return false
	}
	for _, r := range m.rows {
		if r.key() == key {
			return true
		}
	}
	return false
}

// skips collects the selected rows an action leaves out, by reason.
type skips struct {
	reasons []string
	names   map[string][]string
}

func (s *skips) add(reason, name string) {
	if s.names == nil {
		s.names = map[string][]string{}
	}
	if _, had := s.names[reason]; !had {
		s.reasons = append(s.reasons, reason)
	}
	s.names[reason] = append(s.names[reason], name)
}

// String is "web, api: not running; fix: no booth"; "" when nothing is left out.
func (s skips) String() string {
	parts := make([]string, 0, len(s.reasons))
	for _, reason := range s.reasons {
		parts = append(parts, strings.Join(s.names[reason], ", ")+": "+reason)
	}
	return strings.Join(parts, "; ")
}

// batch is one action on several rows, once it is known which rows it is for.
type batch struct {
	verb  string // "stop": names a failure
	done  string // "Stopped": the status line once it is done ("Stopped 3 booths.")
	noun  string // what is counted: "booth", "row"
	items []batchItem
	// separators are deleted with the rows (delete); they need no command.
	separators []string
	skipped    string
}

// batchItem is one row's part of a batch.
type batchItem struct {
	key, name string
	plan      plan
	// lane: items in the same lane run one after another, in their order
	// (two writes of one file, two changes to one repository); the others
	// run at the same time. "" is a lane of its own.
	lane string
}

// batchRun is a batch being carried out.
type batchRun struct {
	batch    batch
	left, ok int
	failures []string
}

type (
	batchResult struct {
		item   batchItem
		output string
		err    error
	}
	// batchDoneMsg is one lane of a batch, finished.
	batchDoneMsg struct {
		id      int
		results []batchResult
	}
	// deleteBatchCheckMsg is the git status of the selected worktrees, read
	// fresh for delete's question.
	deleteBatchCheckMsg struct {
		draft  deleteDraft
		rows   []row
		states []lifecycle.GitState
		errs   []error
	}
)

// summary is the status line for n rows done: "Stopped 3 booths. Skipped web: not running."
func (b batch) summary(n int) string {
	text := b.done + " " + plural(n, b.noun) + "."
	if b.skipped != "" {
		text += " Skipped " + b.skipped + "."
	}
	return text
}

// ask asks question before carrying b out.
func (m model) ask(b batch, question string) (tea.Model, tea.Cmd) {
	if b.skipped != "" {
		question += " Leaving out " + b.skipped + "."
	}
	m.confirm = &pendingConfirm{plan: plan{Verb: b.verb, Confirm: question}, batch: &b}
	m.clampOffset() // a wrapped question takes rows from the table
	return m, nil
}

// executeBatch carries b out: separators at once, the rest in the background,
// each row busy until its own command ends.
func (m model) executeBatch(b batch) (tea.Model, tea.Cmd) {
	m.anchor = ""
	done := 0
	if len(b.separators) > 0 {
		drop := map[string]bool{}
		for _, key := range b.separators {
			drop[key] = true
		}
		saved := m.savedOrder()
		order := make([]lifecycle.OrderEntry, 0, len(saved))
		for _, e := range saved {
			if !drop[e.Key] {
				order = append(order, e)
			}
		}
		if err := m.saveOrder(order); err != nil {
			m.setStatus("Could not delete the separators: "+err.Error(), true)
			return m, nil
		}
		done = len(b.separators)
		m.layout()
	}
	if len(b.items) == 0 {
		m.setStatus(b.summary(done), false)
		return m, nil
	}

	m.batchSeq++
	id := m.batchSeq
	m.batches[id] = &batchRun{batch: b, left: len(b.items), ok: done}
	var lanes [][]batchItem
	at := map[string]int{}
	for _, item := range b.items {
		busy := item.plan.Busy
		if busy == "" {
			busy = "working…"
		}
		m.busy[item.key] = busy
		if i, ok := at[item.lane]; ok && item.lane != "" {
			lanes[i] = append(lanes[i], item)
			continue
		}
		at[item.lane] = len(lanes)
		lanes = append(lanes, []batchItem{item})
	}
	run, forget := m.deps.Run, m.deps.Forget
	cmds := make([]tea.Cmd, 0, len(lanes))
	for _, lane := range lanes {
		cmds = append(cmds, func() tea.Msg {
			results := make([]batchResult, 0, len(lane))
			for _, item := range lane {
				res := batchResult{item: item}
				switch {
				case item.plan.Forget == nil:
					res.output, res.err = run(item.plan.Dir, item.plan.Args)
				case forget != nil:
					res.err = forget(*item.plan.Forget)
				}
				results = append(results, res)
			}
			return batchDoneMsg{id: id, results: results}
		})
	}
	m.setStatus("", false)
	return m, tea.Batch(cmds...)
}

// batchDone takes a finished lane: its rows are no longer busy, and once the
// whole batch is in, the status line says how it went.
func (m model) batchDone(msg batchDoneMsg) (tea.Model, tea.Cmd) {
	run := m.batches[msg.id]
	if run == nil {
		return m, nil
	}
	for _, res := range msg.results {
		delete(m.busy, res.item.key)
		run.left--
		switch {
		case res.err == nil:
			run.ok++
		case res.item.plan.Verb == "delete worktree":
			run.failures = append(run.failures, keptWorktree(res.item.name, res.output, res.err))
		default:
			run.failures = append(run.failures, failure(res.item.plan.Verb, res.item.name, res.output, res.err))
		}
	}
	m.staleGit()
	if run.left <= 0 {
		delete(m.batches, msg.id)
		total := len(run.batch.items) + len(run.batch.separators)
		if len(run.failures) > 0 {
			m.setStatus(fmt.Sprintf("%s %d of %s. %s", run.batch.done, run.ok, plural(total, run.batch.noun),
				strings.Join(run.failures, " ")), true)
		} else {
			m.setStatus(run.batch.summary(run.ok), false)
		}
	}
	return m.refresh(true)
}

// boothSkip says why a key that needs a container leaves r out; "" when r has
// a booth with a container that is not busy.
func (m model) boothSkip(r row) string {
	switch {
	case r.booth == nil:
		return "no booth"
	case m.busy[r.key()] != "":
		return "busy"
	case r.booth.Gone():
		return "no container"
	}
	return ""
}

// stopRows is x or r on several rows: the running booths among them, after
// one question.
func (m model) stopRows(key string, sel []row) (tea.Model, tea.Cmd) {
	b := batch{verb: "stop", done: "Stopped", noun: "booth"}
	if key == keyRestart {
		b.verb, b.done = "restart", "Restarted"
	}
	var left skips
	var names []string
	removed := 0
	for _, r := range sel {
		if r.sep != "" {
			continue
		}
		reason := m.boothSkip(r)
		if reason == "" && !r.booth.Running() {
			reason = "not running"
		}
		if reason != "" {
			left.add(reason, rowName(r))
			continue
		}
		p, _ := planFor(key, *r.booth)
		p.Confirm = ""
		if !r.booth.KeepAlive {
			removed++
		}
		names = append(names, r.booth.Name)
		b.items = append(b.items, batchItem{key: r.key(), name: r.booth.Name, plan: p})
	}
	b.skipped = left.String()
	if len(b.items) == 0 {
		m.setStatus(fmt.Sprintf("Nothing to %s in the %d selected rows (%s).", b.verb, len(sel), b.skipped), false)
		return m, nil
	}
	question := fmt.Sprintf("%s %s (%s)?", capital(b.verb), plural(len(names), "booth"), strings.Join(names, ", "))
	if key == keyStop && removed > 0 {
		question += fmt.Sprintf(" %d not keep-alive: removed too.", removed)
	}
	return m.ask(b, question)
}

// startRows is s on several rows: the stopped daemon booths and the worktrees
// with no booth among them, one after another in the terminal, as each start
// takes it. An interactive booth's start is its session, which would hold the
// others up until it ends, so it is left out.
func (m model) startRows(sel []row) (tea.Model, tea.Cmd) {
	var left skips
	run := &runAll{verb: "start"}
	for _, r := range sel {
		if r.sep != "" {
			continue
		}
		var p plan
		switch {
		case m.busy[r.key()] != "":
			left.add("busy", rowName(r))
			continue
		case r.booth == nil:
			var reason string
			if p, reason = planForWorktree(keyStart, r); reason != "" {
				left.add("folder gone", rowName(r))
				continue
			}
		case r.booth.Gone():
			left.add("no container", rowName(r))
			continue
		case r.booth.Running():
			left.add("already running", rowName(r))
			continue
		case !r.booth.Daemon:
			left.add("interactive, start it on its own", rowName(r))
			continue
		default:
			p, _ = planFor(keyStart, *r.booth)
		}
		run.names = append(run.names, rowName(r))
		run.cmds = append(run.cmds, m.deps.Command(p.Dir, p.Args))
	}
	b := batch{verb: "start", done: "Started", noun: "booth", skipped: left.String()}
	if len(run.cmds) == 0 {
		m.setStatus(fmt.Sprintf("Nothing to start in the %d selected rows (%s).", len(sel), b.skipped), false)
		return m, nil
	}
	m.anchor = ""
	m.setStatus("", false)
	done := b.summary(len(run.cmds))
	return m, tea.Exec(run, func(err error) tea.Msg {
		return execDoneMsg{name: run.failed, plan: plan{Verb: "start", Done: done}, err: err}
	})
}

// runAll runs commands one after another in the dashboard's terminal. The
// first to fail ends the run, after waiting for Enter so its reason can be
// read (see holdOnFailure).
type runAll struct {
	verb   string
	names  []string
	cmds   []*exec.Cmd
	failed string // the name whose command failed
	in     io.Reader
	out    io.Writer
	err    io.Writer
}

func (r *runAll) SetStdin(in io.Reader)   { r.in = in }
func (r *runAll) SetStdout(out io.Writer) { r.out = out }
func (r *runAll) SetStderr(err io.Writer) { r.err = err }

func (r *runAll) Run() error {
	for i, cmd := range r.cmds {
		if r.out != nil {
			fmt.Fprintf(r.out, "── %s %s (%d of %d) ──\n", r.verb, r.names[i], i+1, len(r.cmds))
		}
		cmd.Stdin, cmd.Stdout, cmd.Stderr = r.in, r.out, r.err
		if err := cmd.Run(); err != nil {
			r.failed = r.names[i]
			if r.in != nil && r.out != nil {
				rest := ""
				if n := len(r.cmds) - i - 1; n > 0 {
					rest = fmt.Sprintf(" The %d after it were not started.", n)
				}
				fmt.Fprintf(r.out, "\nCould not %s %s (%v).%s Press Enter to return to booth dashboard.",
					r.verb, r.names[i], err, rest)
				_, _ = bufio.NewReader(r.in).ReadString('\n')
			}
			return err
		}
	}
	return nil
}

// deleteDraft is delete on several rows, while its question is put together.
type deleteDraft struct {
	batch                    batch
	left                     skips
	booths, running, forgets []string
	worktrees                []string
	selected                 int
}

// deleteRows is delete on several rows: booths (with their home volumes), gone
// booths (forgotten), separators and worktrees with no booth. A worktree is
// read first, as for one row, and only a clean one is deleted here: one with
// work to lose is left out and named, so that discarding work stays a
// question of its own, on that row.
func (m model) deleteRows(sel []row) (tea.Model, tea.Cmd) {
	d := deleteDraft{batch: batch{verb: "delete", done: "Deleted", noun: "row"}, selected: len(sel)}
	var check []row
	for _, r := range sel {
		name := rowName(r)
		switch {
		case r.sep == separatorTop:
			d.left.add("it stays while the table has a separator", "the top line")
		case r.sep != "":
			d.batch.separators = append(d.batch.separators, r.sep)
		case m.busy[r.key()] != "":
			d.left.add("busy", name)
		case r.booth != nil && r.booth.Gone():
			p, _ := planFor(keyRemove, *r.booth)
			p.Confirm, p.Busy = "", "forgetting…"
			d.forgets = append(d.forgets, name)
			d.batch.items = append(d.batch.items, batchItem{key: r.key(), name: name, plan: p, lane: "forget"})
		case r.booth != nil:
			p, _ := planFor(keyRemove, *r.booth)
			p.Confirm = ""
			d.booths = append(d.booths, name)
			if r.booth.Running() {
				d.running = append(d.running, name)
			}
			d.batch.items = append(d.batch.items, batchItem{key: r.key(), name: name, plan: p})
		case r.worktree == nil || r.repo == nil:
		case r.worktree.Main:
			d.left.add("the main checkout", name)
		case r.worktree.Prunable:
			d.addWorktree(r) // its folder is gone: only the record is left
		case m.deps.GitStatus == nil:
			d.left.add("its git status cannot be read, delete it on its own", name)
		default:
			check = append(check, r)
		}
	}
	if len(check) == 0 {
		return m.askDelete(d)
	}
	for _, r := range check {
		m.busy[r.key()] = "checking…"
	}
	m.setStatus("", false)
	read := m.deps.GitStatus
	return m, func() tea.Msg {
		msg := deleteBatchCheckMsg{draft: d, rows: check}
		for _, r := range check {
			state, err := read(*r.repo, *r.worktree)
			msg.states, msg.errs = append(msg.states, state), append(msg.errs, err)
		}
		return msg
	}
}

func (d *deleteDraft) addWorktree(r row) {
	p := deleteWorktreePlan(r, gitworktreeClean, nil)
	p.Confirm = ""
	d.worktrees = append(d.worktrees, r.worktree.Name())
	// One repository's worktrees are removed one after another.
	d.batch.items = append(d.batch.items, batchItem{key: r.key(), name: r.worktree.Name(), plan: p,
		lane: "worktree:" + r.repo.Root})
}

// deleteChecked takes the worktrees' git status and asks delete's question.
func (m model) deleteChecked(msg deleteBatchCheckMsg) (tea.Model, tea.Cmd) {
	d := msg.draft
	for i, r := range msg.rows {
		delete(m.busy, r.key())
		state, err := msg.states[i], msg.errs[i]
		var lost []string
		if state.Dirty > 0 {
			lost = append(lost, plural(state.Dirty, "uncommitted file"))
		}
		if state.Ahead > 0 {
			lost = append(lost, plural(state.Ahead, "unmerged commit"))
		}
		switch {
		case err != nil:
			d.left.add("its git status cannot be read, delete it on its own", r.worktree.Name())
		case len(lost) > 0:
			d.left.add(strings.Join(lost, " and ")+", delete it on its own", r.worktree.Name())
		default:
			d.addWorktree(r)
		}
	}
	if m.confirm != nil || m.prompt != nil || m.compose != nil || m.picker != nil {
		return m, nil // something else took the status line meanwhile
	}
	return m.askDelete(d)
}

// askDelete asks delete's question; separators alone are deleted at once, as one is.
func (m model) askDelete(d deleteDraft) (tea.Model, tea.Cmd) {
	d.batch.skipped = d.left.String()
	if len(d.batch.items) == 0 {
		if len(d.batch.separators) > 0 {
			return m.executeBatch(d.batch)
		}
		m.setStatus(fmt.Sprintf("Nothing to delete in the %d selected rows (%s).", d.selected, d.batch.skipped), false)
		return m, nil
	}
	var parts []string
	if len(d.booths) > 0 {
		part := fmt.Sprintf("delete %s and %s (%s", plural(len(d.booths), "booth"),
			oneOrMany(len(d.booths), "its home volume", "their home volumes"), strings.Join(d.booths, ", "))
		if len(d.running) > 0 {
			part += "; running, so force-deleted: " + strings.Join(d.running, ", ")
		}
		parts = append(parts, part+")")
	}
	if len(d.forgets) > 0 {
		parts = append(parts, fmt.Sprintf("forget %s (%s)", plural(len(d.forgets), "booth"), strings.Join(d.forgets, ", ")))
	}
	if len(d.worktrees) > 0 {
		parts = append(parts, fmt.Sprintf("delete %s and %s (%s)", plural(len(d.worktrees), "worktree"),
			oneOrMany(len(d.worktrees), "its branch", "their branches"), strings.Join(d.worktrees, ", ")))
	}
	if n := len(d.batch.separators); n > 0 {
		parts = append(parts, "delete "+plural(n, "separator"))
	}
	return m.ask(d.batch, capital(strings.Join(parts, "; "))+"?")
}

// hideRows is h on several rows: all of them hidden, or under H shown again.
func (m model) hideRows(sel []row) (tea.Model, tea.Cmd) {
	if m.deps.Hide == nil {
		return m, nil
	}
	hide := !m.showHidden
	hidden := make(map[string]bool, len(m.hidden)+len(sel))
	for k, v := range m.hidden {
		hidden[k] = v
	}
	done := 0
	var failed error
	for _, r := range sel {
		if r.sep != "" {
			continue
		}
		if failed = m.deps.Hide(r.key(), r.path(), hide); failed != nil {
			break
		}
		if hide {
			hidden[r.key()] = true
		} else {
			delete(hidden, r.key())
		}
		done++
	}
	if done > 0 {
		m.hidden = hidden
		m.hiddenGen++
	}
	m.anchor = ""
	m.layout()
	verb, did := "hide", "Hid"
	if !hide {
		verb, did = "unhide", "Unhid"
	}
	switch {
	case failed != nil:
		m.setStatus(fmt.Sprintf("Could not %s every row (%s done): %s", verb, plural(done, "row"), failed.Error()), true)
	case done == 0:
		m.setStatus("A separator is not hidden; delete deletes it.", false)
	case hide:
		m.setStatus(did+" "+plural(done, "row")+". H shows the hidden rows.", false)
	default:
		m.setStatus(did+" "+plural(done, "row")+".", false)
	}
	return m, nil
}

// reorderLevel is one kind of place in the order: of names a row's, in says
// which rows are ordered among each other there.
type reorderLevel struct {
	of func(row) string
	in func(row) bool
	// add: places not saved yet are added first, as the rows are now (a
	// booth's among the booths on its checkout: see reorderBooth).
	add bool
}

// reorderBlock is ctrl+↑/↓ on several rows: they move together, past the next
// one shown, in the widest unit they touch. Booths on one checkout move among
// the booths there (and at its edge as that checkout does); worktrees of one
// repository move within it; anything wider moves the groups the rows are in.
func (m model) reorderBlock(delta int) (tea.Model, tea.Cmd) {
	if m.deps.SaveOrder == nil {
		return m, nil
	}
	// Move among the rows as they are now: another dashboard may have moved
	// them since the last snapshot.
	m.order = m.savedOrder()
	m.layout()
	sel := m.selection()
	if len(sel) < 2 {
		return m.reorder(delta)
	}
	first := sel[0]
	booths, inners := true, true
	for _, r := range sel {
		booths = booths && sameCheckout(first, r)
		inners = inners && innerKey(r) != "" && groupKey(r) == groupKey(first)
	}
	var levels []reorderLevel
	if booths {
		levels = append(levels, reorderLevel{of: siblingKey, in: func(x row) bool { return sameCheckout(first, x) }, add: true})
	}
	if inners {
		levels = append(levels, reorderLevel{of: innerKey, in: func(x row) bool { return groupKey(x) == groupKey(first) }})
	} else {
		levels = append(levels, reorderLevel{of: groupKey, in: func(row) bool { return true }})
	}
	for _, level := range levels {
		moved, err := m.moveBlock(sel, level, delta)
		if err != nil {
			m.setStatus("Could not save the row order: "+err.Error(), true)
			return m, nil
		}
		if moved {
			m.setStatus("", false)
			m.layout()
			break
		}
	}
	return m, nil
}

// moveBlock moves sel's units of level past their neighbour on delta's side,
// and saves the order. The units and the neighbour trade the places they hold
// in the saved order, so what is hidden between them stays put. It reports
// false, with nothing changed, when there is no neighbour on that side.
func (m *model) moveBlock(sel []row, level reorderLevel, delta int) (bool, error) {
	var units []string
	shown := map[string]bool{}
	for _, x := range m.rows {
		if k := level.of(x); k != "" && level.in(x) && !shown[k] {
			shown[k] = true
			units = append(units, k)
		}
	}
	block := map[string]bool{}
	for _, r := range sel {
		block[level.of(r)] = true
	}
	lo, hi := -1, -1
	for i, k := range units {
		if block[k] {
			if lo < 0 {
				lo = i
			}
			hi = i
		}
	}
	if lo < 0 {
		return false, nil
	}
	neighbour := hi + 1
	if delta < 0 {
		neighbour = lo - 1
	}
	if neighbour < 0 || neighbour >= len(units) {
		return false, nil
	}

	order := append([]lifecycle.OrderEntry{}, m.order...)
	pos := make(map[string]int, len(order))
	for i, e := range order {
		pos[e.Key] = i
	}
	if level.add {
		all := m.arrange(append(buildRows(m.booths, m.repos), m.separatorRows()...))
		for _, x := range all {
			k := level.of(x)
			if _, known := pos[k]; k != "" && level.in(x) && !known {
				pos[k] = len(order)
				order = append(order, lifecycle.OrderEntry{Key: k, Path: x.path()})
			}
		}
	}
	// after is the units as they will be, top to bottom; places are the
	// places they hold now, top to bottom.
	after := append([]string{}, units[lo:hi+1]...)
	if delta < 0 {
		after = append(after, units[neighbour])
	} else {
		after = append([]string{units[neighbour]}, after...)
	}
	places := make([]int, 0, len(after))
	entries := map[string]lifecycle.OrderEntry{}
	for _, k := range after {
		at, known := pos[k]
		if !known {
			return false, nil
		}
		places = append(places, at)
		entries[k] = order[at]
	}
	sort.Ints(places)
	for i, k := range after {
		order[places[i]] = entries[k]
	}
	if err := m.saveOrder(order); err != nil {
		return false, err
	}
	return true, nil
}

func capital(s string) string {
	if s == "" {
		return s
	}
	return strings.ToUpper(s[:1]) + s[1:]
}

func oneOrMany(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}
