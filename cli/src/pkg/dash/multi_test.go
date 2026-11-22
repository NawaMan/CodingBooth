// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"errors"
	"os/exec"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// settle runs cmd and feeds back what an action on several rows produces: the
// worktrees' git check and each finished lane. The refreshes they ask for are
// not followed.
func settle(t *testing.T, m model, cmd tea.Cmd) model {
	t.Helper()
	queue := []tea.Cmd{cmd}
	for len(queue) > 0 {
		c := queue[0]
		queue = queue[1:]
		if c == nil {
			continue
		}
		switch msg := c().(type) {
		case tea.BatchMsg:
			queue = append(queue, msg...)
		case batchDoneMsg, deleteBatchCheckMsg:
			next, _ := m.Update(msg)
			m = next.(model)
		}
	}
	return m
}

func selectedNames(m model) []string {
	var names []string
	for _, r := range m.selection() {
		names = append(names, rowName(r))
	}
	return names
}

func TestShiftArrowsSelectARangeFromTheRowTheyStartOn(t *testing.T) {
	m := hideModel(&hideStore{}) // web, api, db
	if m.selection() != nil {
		t.Fatal("nothing is selected at first")
	}
	m, _ = press(t, m, "shift+down")
	if got := selectedNames(m); !reflect.DeepEqual(got, []string{"web", "api"}) {
		t.Fatalf("selected %v, want web and api", got)
	}
	view := stripANSI(m.View())
	for _, want := range []string{"2 selected", "2 selected: h hide · s start · x stop · r restart · del delete", "+ web"} {
		if !strings.Contains(view, want) {
			t.Errorf("view lacks %q:\n%s", want, view)
		}
	}
	m, _ = press(t, m, "shift+down")
	if got := selectedNames(m); !reflect.DeepEqual(got, []string{"web", "api", "db"}) {
		t.Fatalf("selected %v, want all three", got)
	}
	m, _ = press(t, m, "shift+up", "shift+up")
	if m.selection() != nil || m.cursor != 0 {
		t.Fatalf("back on the row it started on, one row is not a selection: %v", selectedNames(m))
	}
	// Upwards from the last row; a plain arrow, or esc, ends it.
	m, _ = press(t, m, "G", "shift+up")
	if got := selectedNames(m); !reflect.DeepEqual(got, []string{"api", "db"}) {
		t.Fatalf("selected %v, want api and db", got)
	}
	m, _ = press(t, m, "up")
	if m.selection() != nil || m.anchor != "" {
		t.Fatalf("a plain arrow must end the selection: %v", selectedNames(m))
	}
	m, _ = press(t, m, "shift+down", "esc")
	if m.selection() != nil || m.anchor != "" {
		t.Fatalf("esc must end the selection: %v", selectedNames(m))
	}
	if strings.Contains(stripANSI(m.View()), "selected") {
		t.Errorf("the view still talks of a selection:\n%s", stripANSI(m.View()))
	}
}

func TestSelectionStaysOnItsRowsAcrossARefresh(t *testing.T) {
	m := hideModel(&hideStore{})
	m, _ = press(t, m, "down", "shift+down") // api, db
	booths := []lifecycle.Booth{running("new"), running("web"), running("api"), running("db")}
	next, _ := m.Update(snapshotMsg{seq: 2, booths: booths, hidden: map[string]bool{}})
	m = next.(model)
	if got := selectedNames(m); !reflect.DeepEqual(got, []string{"api", "db"}) {
		t.Fatalf("selected %v after a refresh, want api and db", got)
	}
	// The row it started on is gone: so is the selection.
	next, _ = m.Update(snapshotMsg{seq: 3, booths: []lifecycle.Booth{running("web"), running("db")}, hidden: map[string]bool{}})
	m = next.(model)
	if m.selection() != nil || m.anchor != "" {
		t.Fatalf("selection survived its first row: %v", selectedNames(m))
	}
}

func TestHideHidesEverySelectedRow(t *testing.T) {
	store := &hideStore{}
	m := hideModel(store)
	m, _ = press(t, m, "shift+down", "h")
	if got := rowNames(m); !reflect.DeepEqual(got, []string{"db"}) {
		t.Fatalf("rows = %v, want only db", got)
	}
	if !store.keys["web@docker"] || !store.keys["api@docker"] || len(store.keys) != 2 {
		t.Errorf("stored %v, want web and api", store.keys)
	}
	if m.status != "Hid 2 rows. H shows the hidden rows." || m.selection() != nil {
		t.Errorf("status %q, selection %v", m.status, selectedNames(m))
	}
	m, _ = press(t, m, "H", "shift+down", "h")
	if len(store.keys) != 0 || m.status != "Unhid 2 rows." {
		t.Errorf("stored %v, status %q: want both shown again", store.keys, m.status)
	}
}

func TestStopAsksOnceAndStopsTheRunningOnes(t *testing.T) {
	f := &fakeDeps{}
	db := running("db")
	db.KeepAlive = false
	m := loaded(f, running("web"), stopped("api"), db)
	m, _ = press(t, m, "shift+down", "shift+down", "x")
	if m.confirm == nil || m.confirm.batch == nil {
		t.Fatalf("x on several rows must ask once: %+v", m.confirm)
	}
	want := "Stop 2 booths (web, db)? 1 not keep-alive: removed too. Leaving out api: not running."
	if m.confirm.plan.Confirm != want {
		t.Fatalf("question %q, want %q", m.confirm.plan.Confirm, want)
	}

	cancelled, _ := press(t, m, "n")
	if len(f.ran) != 0 || cancelled.status != "Cancelled." || len(cancelled.selection()) != 3 {
		t.Fatalf("n must run nothing and keep the selection: ran %v status %q", f.ran, cancelled.status)
	}

	m, cmd := press(t, m, "y")
	if m.busy["web@docker"] != "stopping…" || m.busy["db@docker"] != "stopping…" || m.busy["api@docker"] != "" {
		t.Fatalf("busy = %v, want web and db stopping", m.busy)
	}
	if m.selection() != nil {
		t.Errorf("the selection must end once the action runs")
	}
	m = settle(t, m, cmd)
	wantRan := [][]string{{"stop", "--name", "web", "--engine", "docker"}, {"stop", "--name", "db", "--engine", "docker"}}
	if !reflect.DeepEqual(f.ran, wantRan) {
		t.Fatalf("ran %v, want %v", f.ran, wantRan)
	}
	if len(m.busy) != 0 || m.statusErr || m.status != "Stopped 2 booths. Skipped api: not running." {
		t.Errorf("busy %v, status %q (err %v)", m.busy, m.status, m.statusErr)
	}
}

func TestRestartAndStopWithNothingRunningSaySo(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, stopped("web"), goneBooth())
	m, cmd := press(t, m, "shift+down", "r")
	if cmd != nil || m.confirm != nil || len(f.ran) != 0 {
		t.Fatalf("nothing to restart must not ask or run")
	}
	if want := "Nothing to restart in the 2 selected rows (web: not running; old: no container)."; m.status != want {
		t.Errorf("status %q, want %q", m.status, want)
	}
}

func TestFailedRowsOfABatchAreReported(t *testing.T) {
	f := &fakeDeps{runErr: errors.New("exit status 1"), runOut: "Error: the engine said no"}
	m := loaded(f, running("web"), running("api"))
	m, cmd := press(t, m, "shift+down", "r", "y")
	m = settle(t, m, cmd)
	want := "Restarted 0 of 2 booths. Error: the engine said no Error: the engine said no"
	if !m.statusErr || m.status != want || len(m.busy) != 0 {
		t.Errorf("status %q (err %v) busy %v, want %q", m.status, m.statusErr, m.busy, want)
	}
}

func TestStartStartsDaemonBoothsOneAfterAnother(t *testing.T) {
	f := &fakeDeps{}
	daemon := func(name string) lifecycle.Booth {
		b := stopped(name)
		b.Daemon = true
		return b
	}
	m := loaded(f, daemon("a"), stopped("b"), running("c"), daemon("d"))
	m, cmd := press(t, m, "shift+down", "shift+down", "shift+down", "s")
	if cmd == nil || m.confirm != nil {
		t.Fatalf("s must start at once, in the terminal: cmd %v confirm %+v", cmd != nil, m.confirm)
	}
	want := [][]string{
		{"start", "--name", "a", "--engine", "docker", "--daemon"},
		{"start", "--name", "d", "--engine", "docker", "--daemon"},
	}
	if !reflect.DeepEqual(f.execed, want) {
		t.Fatalf("execed %v, want %v (b is interactive, c runs)", f.execed, want)
	}
	if m.selection() != nil {
		t.Errorf("the selection must end once the action runs")
	}

	// Nothing to start says why.
	m = loaded(&fakeDeps{}, stopped("b"), running("c"))
	m, cmd = press(t, m, "shift+down", "s")
	wantStatus := "Nothing to start in the 2 selected rows (b: interactive, start it on its own; c: already running)."
	if cmd != nil || m.status != wantStatus {
		t.Errorf("status %q, want %q", m.status, wantStatus)
	}
}

func TestRunAllStopsAtTheFirstFailure(t *testing.T) {
	var out strings.Builder
	run := &runAll{verb: "start", names: []string{"a", "b", "c"},
		cmds: []*exec.Cmd{exec.Command("true"), exec.Command("false"), exec.Command("true")}}
	run.SetStdin(strings.NewReader("\n"))
	run.SetStdout(&out)
	run.SetStderr(&out)
	if err := run.Run(); err == nil || run.failed != "b" {
		t.Fatalf("err %v failed %q, want b's failure", err, run.failed)
	}
	if run.cmds[2].ProcessState != nil {
		t.Errorf("c ran after b failed")
	}
	for _, want := range []string{"── start a (1 of 3) ──", "── start b (2 of 3) ──",
		"Could not start b (exit status 1). The 1 after it were not started. Press Enter to return to booth dashboard."} {
		if !strings.Contains(out.String(), want) {
			t.Errorf("out lacks %q:\n%s", want, out.String())
		}
	}
	if strings.Contains(out.String(), "start c") {
		t.Errorf("c was announced:\n%s", out.String())
	}

	ok := &runAll{verb: "start", names: []string{"a", "b"}, cmds: []*exec.Cmd{exec.Command("true"), exec.Command("true")}}
	ok.SetStdin(strings.NewReader(""))
	ok.SetStdout(&out)
	if err := ok.Run(); err != nil || ok.failed != "" {
		t.Errorf("err %v failed %q, want none", err, ok.failed)
	}
}

func TestDeleteAsksOnceForBoothsAndGoneBooths(t *testing.T) {
	f := &fakeDeps{}
	var forgot []string
	deps := f.deps()
	deps.Forget = func(b lifecycle.Booth) error { forgot = append(forgot, b.Name+"@"+b.Engine); return nil }
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, booths: []lifecycle.Booth{running("web"), goneBooth(), stopped("api")}})
	m, _ = press(t, next.(model), "shift+down", "shift+down", "delete")
	if m.confirm == nil || m.confirm.batch == nil || m.confirm.plan.Danger {
		t.Fatalf("confirm %+v", m.confirm)
	}
	want := "Delete 2 booths and their home volumes (web, api; running, so force-deleted: web); forget 1 booth (old)?"
	if m.confirm.plan.Confirm != want {
		t.Fatalf("question %q, want %q", m.confirm.plan.Confirm, want)
	}
	m, cmd := press(t, m, "y")
	if m.busy["old@docker"] != "forgetting…" || m.busy["web@docker"] != "deleting…" {
		t.Errorf("busy %v", m.busy)
	}
	m = settle(t, m, cmd)
	wantRan := [][]string{
		{"remove", "--name", "web", "--engine", "docker", "--force"},
		{"remove", "--name", "api", "--engine", "docker"},
	}
	if !reflect.DeepEqual(f.ran, wantRan) || !reflect.DeepEqual(forgot, []string{"old@docker"}) {
		t.Fatalf("ran %v forgot %v", f.ran, forgot)
	}
	if m.status != "Deleted 3 rows." || m.statusErr {
		t.Errorf("status %q (err %v)", m.status, m.statusErr)
	}
}

func TestDeleteLeavesOutAWorktreeWithWorkAndNeverForces(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	deps := f.deps()
	deps.GitStatus = func(_ lifecycle.Repo, w lifecycle.Worktree) (lifecycle.GitState, error) {
		if w.Branch == "idea" {
			return lifecycle.GitState{Dirty: 2, Ahead: 1}, nil
		}
		return lifecycle.GitState{}, nil
	}
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, repos: f.repos})
	m, cmd := press(t, next.(model), "shift+down", "shift+down", "delete") // main, fix, idea
	if cmd == nil || m.confirm != nil || m.busy["worktree:/home/u/dev/proj/worktree/fix"] != "checking…" {
		t.Fatalf("d must read the worktrees first: cmd %v confirm %+v busy %v", cmd != nil, m.confirm, m.busy)
	}
	m = settle(t, m, cmd)
	want := "Delete 1 worktree and its branch (fix)? Leaving out main: the main checkout; " +
		"idea: 2 uncommitted files and 1 unmerged commit, delete it on its own."
	if m.confirm == nil || m.confirm.plan.Confirm != want || m.confirm.plan.Danger {
		t.Fatalf("confirm %+v, want %q", m.confirm, want)
	}
	if len(m.busy) != 0 {
		t.Errorf("busy %v after the check", m.busy)
	}
	m, cmd = press(t, m, "y")
	m = settle(t, m, cmd)
	if want := [][]string{{"worktree", "remove", "fix"}}; !reflect.DeepEqual(f.ran, want) || f.ranIn[0] != "/home/u/dev/proj" {
		t.Fatalf("ran %v in %v, want %v in the repository (no --force)", f.ran, f.ranIn, want)
	}
	if !strings.HasPrefix(m.status, "Deleted 1 row. Skipped main: the main checkout; idea:") {
		t.Errorf("status %q", m.status)
	}
}

func TestDeleteOnOnlyWorktreesWithWorkDeletesNothing(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	deps := f.deps()
	deps.GitStatus = func(lifecycle.Repo, lifecycle.Worktree) (lifecycle.GitState, error) {
		return lifecycle.GitState{}, errors.New("not a git repository")
	}
	m := newModel(deps)
	next, _ := m.Update(snapshotMsg{seq: 1, repos: f.repos})
	m, cmd := press(t, next.(model), "down", "shift+down", "delete") // fix, idea
	m = settle(t, m, cmd)
	if m.confirm != nil || len(f.ran) != 0 || !strings.HasPrefix(m.status, "Nothing to delete in the 2 selected rows (fix, idea: its git status cannot be read") {
		t.Fatalf("confirm %+v ran %v status %q", m.confirm, f.ran, m.status)
	}
}

func TestDeleteOnSeparatorsAloneDeletesThemAtOnce(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "-", "-") // two separators below alpha, the cursor on the second
	m, cmd := press(t, m, "shift+up", "delete")
	if cmd != nil || m.confirm != nil {
		t.Fatalf("separators are deleted without a question")
	}
	for _, k := range store.keys() {
		if strings.HasPrefix(k, separatorPrefix) {
			t.Fatalf("a separator is left: %v", store.keys())
		}
	}
	if m.status != "Deleted 2 rows." {
		t.Errorf("status %q", m.status)
	}
}

func TestCtrlArrowsMoveTheSelectedGroupsTogether(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	m := orderModel(store, booths, repos)
	m, _ = press(t, m, "g", "shift+down", "ctrl+down") // alpha and Mid, past zeta
	want := []string{"(none) @main", "(none) @a-idea", "fixer @b-fix", "(none) @main", "Mid"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) || m.rows[0].repo.Name != "zeta" {
		t.Fatalf("rows = %v, want %v with zeta first", got, want)
	}
	if got := selectedNames(m); !reflect.DeepEqual(got, []string{"main", "Mid"}) || m.rows[3].repo.Name != "alpha" {
		t.Fatalf("selected %v, want alpha and Mid still", got)
	}
	wantKeys := []string{"repo:/home/u/dev/zeta", "repo:/home/u/dev/alpha", "Mid@docker"}
	if got := store.keys()[:3]; !reflect.DeepEqual(got, wantKeys) {
		t.Errorf("saved %v, want %v", got, wantKeys)
	}
	saves := store.saves
	m, _ = press(t, m, "ctrl+down") // already last
	if store.saves != saves {
		t.Errorf("moving past the bottom saved the order")
	}
	m, _ = press(t, m, "ctrl+up")
	if m.rows[0].repo.Name != "alpha" || rowName(m.rows[1]) != "Mid" || m.rows[2].repo.Name != "zeta" {
		t.Errorf("ctrl+up did not move them back: %v", rowSummary(m.rows))
	}
}

func TestCtrlArrowsMoveTheSelectedWorktreesWithinTheirRepository(t *testing.T) {
	store := &orderStore{}
	booths, repos := orderRepos()
	repos[0].Worktrees = append(repos[0].Worktrees, lifecycle.Worktree{Path: "/home/u/dev/zeta.wt/c-more", Branch: "c-more"})
	m := orderModel(store, booths, repos)
	before := []string{"(none) @main", "Mid", "(none) @main", "(none) @a-idea", "fixer @b-fix", "(none) @c-more"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, before) {
		t.Fatalf("rows = %v, want %v", got, before)
	}
	m, _ = press(t, m, "down", "shift+down", "ctrl+down") // a-idea and b-fix, past c-more
	want := []string{"(none) @main", "Mid", "(none) @main", "(none) @c-more", "(none) @a-idea", "fixer @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	m, _ = press(t, m, "ctrl+up", "ctrl+up") // back, then stopped by the main checkout
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, before) {
		t.Errorf("rows = %v, want %v (the main checkout leads, the group stays)", got, before)
	}
}

func TestCtrlArrowsMoveTheSelectedBoothsOnACheckout(t *testing.T) {
	store := &orderStore{}
	m := siblingModel(t, store, nil)
	m, _ = press(t, selectRow(t, m, "one"), "shift+down", "ctrl+down") // one and two, past three
	want := []string{"(none) @main", "Mid", "three @main", "one @main", "two @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
	if got := selectedNames(m); !reflect.DeepEqual(got, []string{"one", "two"}) {
		t.Fatalf("selected %v, want one and two still", got)
	}
	// Back up, then at the top of the checkout the group moves, above Mid.
	m, _ = press(t, m, "ctrl+up", "ctrl+up")
	want = []string{"(none) @main", "one @main", "two @main", "three @main",
		"(none) @a-idea", "fixer @b-fix", "helper @b-fix", "Mid"}
	if got := rowSummary(m.rows); !reflect.DeepEqual(got, want) {
		t.Fatalf("rows = %v, want %v", got, want)
	}
}

func TestOtherKeysActOnTheRowUnderTheCursor(t *testing.T) {
	f := &fakeDeps{}
	m := loaded(f, running("web"), running("api"))
	m, _ = press(t, m, "shift+down", "e")
	if !reflect.DeepEqual(f.edited, []string{"/home/u/dev/api"}) {
		t.Errorf("edited %v, want only the row under the cursor", f.edited)
	}
}
