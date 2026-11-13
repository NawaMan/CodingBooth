// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// gitFake answers GitStatus from states, by path, and records what was read.
type gitFake struct {
	states map[string]lifecycle.GitState
	read   []string
	now    time.Time
}

func gitModel(g *gitFake, repos []lifecycle.Repo, height int, booths ...lifecycle.Booth) (model, tea.Cmd) {
	f := &fakeDeps{repos: repos}
	deps := f.deps()
	g.now = testNow
	deps.Now = func() time.Time { return g.now }
	deps.GitStatus = func(_ lifecycle.Repo, w lifecycle.Worktree) (lifecycle.GitState, error) {
		g.read = append(g.read, w.Path)
		return g.states[w.Path], nil
	}
	m := newModel(deps)
	if height > 0 {
		next, _ := m.Update(tea.WindowSizeMsg{Width: 120, Height: height})
		m = next.(model)
	}
	next, cmd := m.Update(snapshotMsg{seq: 1, booths: booths, repos: repos})
	return next.(model), cmd
}

// drainGit runs cmd and feeds back every message it makes, but no tick: those wait for real time.
func drainGit(t *testing.T, m model, cmd tea.Cmd) model {
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
		case gitMsg, snapshotMsg:
			next, more := m.Update(msg)
			m = next.(model)
			queue = append(queue, more)
		}
	}
	return m
}

func sorted(paths []string) []string {
	out := append([]string(nil), paths...)
	sort.Strings(out)
	return out
}

func TestGitColumnShowsEachWorktreesStatus(t *testing.T) {
	g := &gitFake{states: map[string]lifecycle.GitState{
		"/home/u/dev/proj":                {Base: "origin/main", Ahead: 1},
		"/home/u/dev/proj/worktree/fix":   {Base: "main", Dirty: 2, Ahead: 3, Behind: 1},
		"/home/u/dev/proj.worktrees/idea": {Base: "main", Behind: 4, Merged: true},
	}}
	m, cmd := gitModel(g, testRepos(), 0, boothAt("fixer", "/home/u/dev/proj/worktree/fix"))
	if !strings.Contains(stripANSI(m.View()), "GIT") {
		t.Fatal("no GIT column")
	}
	if cell := m.gitCell(m.rows[1]); cell != "…" {
		t.Errorf("before it is read the cell is %q, want …", cell)
	}

	m = drainGit(t, m, cmd)
	view := stripANSI(m.View())
	for _, want := range []string{"main      ↑1", "fix       *2 ↑3 ↓1", "idea      merged"} {
		if !strings.Contains(view, want) {
			t.Errorf("view lacks %q:\n%s", want, view)
		}
	}
	if !m.gitDirty(m.rows[1]) || m.gitDirty(m.rows[0]) {
		t.Error("only the worktree with changes is drawn as dirty")
	}
}

func TestGitStatusIsCachedThenReadAgain(t *testing.T) {
	g := &gitFake{}
	m, cmd := gitModel(g, testRepos(), 0)
	m = drainGit(t, m, cmd)
	if len(g.read) != 3 {
		t.Fatalf("read %v, want each worktree once", g.read)
	}

	m, cmd = press(t, m, "down")
	m = drainGit(t, m, cmd)
	if len(g.read) != 3 {
		t.Errorf("a key read again within GitInterval: %v", g.read)
	}

	g.now = testNow.Add(11 * time.Second)
	m, cmd = press(t, m, "down")
	m = drainGit(t, m, cmd)
	if len(g.read) != 6 {
		t.Errorf("after GitInterval every worktree is read again: %v", g.read)
	}

	m, cmd = press(t, m, "R")
	_ = drainGit(t, m, cmd)
	if len(g.read) != 9 {
		t.Errorf("R reads every worktree again at once: %v", g.read)
	}
}

func TestGitReadsOnlyWorktreesOnScreenAFewAtATime(t *testing.T) {
	repo := lifecycle.Repo{Name: "big", Root: "/r/big", Here: true}
	for i := range 10 {
		repo.Worktrees = append(repo.Worktrees, lifecycle.Worktree{Path: fmt.Sprintf("/r/big/w%d", i), Branch: fmt.Sprintf("w%d", i), Main: i == 0})
	}
	repos := []lifecycle.Repo{repo}

	// Room for 4 rows: four worktrees (no header line).
	g := &gitFake{}
	m, cmd := gitModel(g, repos, chromeLines+4)
	if m.tableRows() != 4 {
		t.Fatalf("tableRows = %d", m.tableRows())
	}
	_ = drainGit(t, m, cmd)
	if want := []string{"/r/big/w0", "/r/big/w1", "/r/big/w2", "/r/big/w3"}; !reflect.DeepEqual(sorted(g.read), want) {
		t.Errorf("read %v, want only the rows on screen %v", g.read, want)
	}

	// All on screen: at most gitInFlight at once, the rest as those land.
	g = &gitFake{}
	m, cmd = gitModel(g, repos, 0)
	if len(cmd().(tea.BatchMsg)) == 0 {
		t.Fatal("nothing read")
	}
	inFlight := 0
	for _, e := range m.git {
		if e.loading {
			inFlight++
		}
	}
	if inFlight != gitInFlight {
		t.Errorf("%d read at once, want %d", inFlight, gitInFlight)
	}
}

func TestGitMarkedStaleWhileReadIsReadAgain(t *testing.T) {
	g := &gitFake{}
	m, cmd := gitModel(g, testRepos()[:1], 0)
	// The reads are out; an action ends before they land.
	next, _ := m.Update(actionDoneMsg{key: "x", name: "x", plan: plan{Done: "done"}})
	m = next.(model)
	m = drainGit(t, m, cmd)
	if len(g.read) != 6 {
		t.Errorf("a read that began before the action is read again: %v", g.read)
	}
}

func TestGitHiddenWithoutRepositoriesOrReader(t *testing.T) {
	f := &fakeDeps{repos: testRepos()}
	m := loaded(f)
	if strings.Contains(stripANSI(m.View()), "GIT") {
		t.Error("GIT column without a reader")
	}
	g := &gitFake{}
	m, _ = gitModel(g, nil, 0, running("web"))
	if strings.Contains(stripANSI(m.View()), "GIT") || len(g.read) != 0 {
		t.Error("GIT column without repositories")
	}
}

func TestGitText(t *testing.T) {
	for _, c := range []struct {
		state lifecycle.GitState
		want  string
	}{
		{lifecycle.GitState{}, "clean"},
		{lifecycle.GitState{Dirty: 3}, "*3"},
		{lifecycle.GitState{Ahead: 2, Behind: 5}, "↑2 ↓5"},
		{lifecycle.GitState{Behind: 2, Merged: true}, "merged"},
		{lifecycle.GitState{Dirty: 1, Merged: true}, "*1 merged"},
	} {
		if got := gitText(c.state); got != c.want {
			t.Errorf("gitText(%+v) = %q, want %q", c.state, got, c.want)
		}
	}
}
