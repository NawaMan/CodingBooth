// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// The GIT column: each worktree's dirty files, ahead/behind and merged. It costs a few git
// calls per worktree, too much for every 2-second refresh, so it is read lazily: only for the
// worktrees on screen, in the background, a few at a time, and kept for GitInterval. An action,
// a shell, an editor or R marks every entry stale, to be read again; until then it still shows.

// gitInFlight is how many worktrees are read at once.
const gitInFlight = 4

// gitEntry is one worktree's cached status.
type gitEntry struct {
	state   lifecycle.GitState
	err     error
	loaded  bool
	loading bool
	stale   bool
	at      int64 // when it was read, unix nanos of deps.Now
}

type gitMsg struct {
	path  string
	state lifecycle.GitState
	err   error
}

// gitShown: the column is there — repositories to show, and a way to read them.
func (m model) gitShown() bool { return m.deps.GitStatus != nil && len(m.repos) > 0 }

// syncGit reads the status of the worktrees on screen that have none, or an old or stale one.
func (m model) syncGit() (model, tea.Cmd) {
	if !m.gitShown() {
		return m, nil
	}
	now := m.deps.Now().UnixNano()
	inFlight := 0
	for _, e := range m.git {
		if e.loading {
			inFlight++
		}
	}
	var cmds []tea.Cmd
	end := min(len(m.rows), m.offset+m.tableRows())
	for i := m.offset; i < end && inFlight < gitInFlight; i++ {
		r := m.rows[i]
		if r.header || r.worktree == nil || r.worktree.Prunable || r.repo == nil {
			continue
		}
		path := r.worktree.Path
		e := m.git[path]
		if e.loading || (e.loaded && !e.stale && now-e.at < m.deps.GitInterval.Nanoseconds()) {
			continue
		}
		e.loading, e.stale = true, false
		m.git[path] = e
		inFlight++
		read, repo, wt := m.deps.GitStatus, *r.repo, *r.worktree
		cmds = append(cmds, func() tea.Msg {
			state, err := read(repo, wt)
			return gitMsg{path: wt.Path, state: state, err: err}
		})
	}
	return m, tea.Batch(cmds...)
}

// applyGit keeps a read that landed. Marked stale while it was out, it is read again.
func (m model) applyGit(msg gitMsg) model {
	stale := m.git[msg.path].stale
	m.git[msg.path] = gitEntry{state: msg.state, err: msg.err, loaded: true, stale: stale,
		at: m.deps.Now().UnixNano()}
	return m
}

// staleGit marks every status to be read again (one being read is read again after it lands).
func (m model) staleGit() {
	for path, e := range m.git {
		e.stale = true
		m.git[path] = e
	}
}

// gitCell is the GIT cell of a row.
func (m model) gitCell(r row) string {
	if r.worktree == nil || r.worktree.Prunable {
		return "-"
	}
	e, ok := m.git[r.worktree.Path]
	switch {
	case !ok || !e.loaded:
		return "…"
	case e.err != nil:
		return "?"
	}
	return gitText(e.state)
}

// gitText: "*3" files changed, "↑2" commits ahead, "↓5" behind, "merged" when the branch has
// landed and has nothing new; "clean" when there is nothing to say.
func gitText(s lifecycle.GitState) string {
	var parts []string
	if s.Dirty > 0 {
		parts = append(parts, fmt.Sprintf("*%d", s.Dirty))
	}
	if s.Merged {
		parts = append(parts, "merged")
	} else {
		if s.Ahead > 0 {
			parts = append(parts, fmt.Sprintf("↑%d", s.Ahead))
		}
		if s.Behind > 0 {
			parts = append(parts, fmt.Sprintf("↓%d", s.Behind))
		}
	}
	if len(parts) == 0 {
		return "clean"
	}
	return strings.Join(parts, " ")
}

// gitDirty: the worktree has uncommitted work, drawn in the warning colour.
func (m model) gitDirty(r row) bool {
	if r.worktree == nil {
		return false
	}
	e := m.git[r.worktree.Path]
	return e.loaded && e.err == nil && e.state.Dirty > 0
}
