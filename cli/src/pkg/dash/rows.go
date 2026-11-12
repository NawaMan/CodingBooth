// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// row is one line of the table: a repository's header, a booth, or a
// worktree that has no booth.
type row struct {
	header   bool                // the repository's header line; not selectable
	repo     *lifecycle.Repo     // the repository the row is under; nil when ungrouped
	booth    *lifecycle.Booth    // the booth on this row
	worktree *lifecycle.Worktree // the worktree the booth runs in, or the bare worktree
}

// key names a row across refreshes: its booth, else its worktree.
func (r row) key() string {
	switch {
	case r.booth != nil:
		return boothKey(*r.booth)
	case r.worktree != nil:
		return worktreeKey(*r.worktree)
	}
	return ""
}

func worktreeKey(w lifecycle.Worktree) string { return "worktree:" + w.Path }

// path is the folder the row is about: the booth's code, else the worktree.
func (r row) path() string {
	if r.booth != nil && r.booth.CodePath != "" {
		return r.booth.CodePath
	}
	if r.worktree != nil {
		return r.worktree.Path
	}
	return ""
}

// otherBooths heads the booths in no repository found.
var otherBooths = &lifecycle.Repo{Name: "Other booths"}

// buildRows lays the booths out under their repositories. Each worktree shows
// its booths (a booth belongs to the worktree holding its code path), or one
// row of its own when it has none. Booths in no repository come last under
// "Other booths". Without repositories the table is the plain booth list.
func buildRows(booths []lifecycle.Booth, repos []lifecycle.Repo) []row {
	if len(repos) == 0 {
		rows := make([]row, len(booths))
		for i := range booths {
			rows[i] = row{booth: &booths[i]}
		}
		return rows
	}

	// Each booth goes to the deepest worktree holding its code (a worktree may
	// sit inside the main checkout).
	type place struct{ repo, worktree int }
	placed := map[place][]int{}
	var others []int
	for i, b := range booths {
		best, depth := place{-1, -1}, -1
		for r := range repos {
			for w, wt := range repos[r].Worktrees {
				if b.CodePath != "" && lifecycle.Within(b.CodePath, wt.Path) && len(wt.Path) > depth {
					best, depth = place{r, w}, len(wt.Path)
				}
			}
		}
		if best.repo < 0 {
			others = append(others, i)
			continue
		}
		placed[best] = append(placed[best], i)
	}

	var rows []row
	for r := range repos {
		repo := &repos[r]
		rows = append(rows, row{header: true, repo: repo})
		for w := range repo.Worktrees {
			wt := &repo.Worktrees[w]
			in := placed[place{r, w}]
			if len(in) == 0 {
				rows = append(rows, row{repo: repo, worktree: wt})
				continue
			}
			for _, i := range in {
				rows = append(rows, row{repo: repo, worktree: wt, booth: &booths[i]})
			}
		}
	}
	if len(others) > 0 {
		rows = append(rows, row{header: true, repo: otherBooths})
		for _, i := range others {
			rows = append(rows, row{repo: otherBooths, booth: &booths[i]})
		}
	}
	return rows
}

// branchText is the WORKTREE cell: the branch, marked when it is the main
// checkout or detached.
func branchText(w *lifecycle.Worktree) string {
	if w == nil {
		return "-"
	}
	name := w.Branch
	if name == "" {
		name = "(detached)"
	}
	if w.Main {
		name += " (main checkout)"
	}
	return name
}

// planForWorktree is what a key does to a worktree row that has no booth.
func planForWorktree(key string, r row) (plan, string) {
	w := r.worktree
	switch key {
	case keyStart:
		if w.Prunable {
			return plan{}, fmt.Sprintf("%s's folder is gone; d removes the worktree record.", w.Name())
		}
		// The main checkout runs booth as it is; another worktree by name. It
		// already exists, so booth leaves it in place when the booth ends.
		// In the foreground, as every start is (see planFor).
		if w.Main {
			return plan{Verb: "start", Args: []string{"--daemon"}, Dir: w.Path, Interactive: true, Hold: true,
				Done: "Started a booth on " + branchText(w) + "."}, ""
		}
		return plan{Verb: "start", Args: []string{"--worktree", w.Name(), "--daemon"}, Dir: r.repo.Root,
			Interactive: true, Hold: true, Done: "Started a booth on " + w.Name() + "."}, ""

	case keyRemove:
		if w.Main {
			return plan{}, "The main checkout is not removed from here."
		}
		return plan{Verb: "remove worktree", Args: []string{"worktree", "remove", w.Name()}, Dir: r.repo.Root,
			Confirm: fmt.Sprintf("Remove worktree %s and its branch? Refused if anything would be lost; "+
				"a branch with commits found nowhere else is kept.", w.Name()),
			Busy: "removing…", Done: "Removed worktree " + w.Name() + "."}, ""

	case keyShell:
		if w.Prunable {
			return plan{}, fmt.Sprintf("%s's folder is gone; d removes the worktree record.", w.Name())
		}
		// `shell --run` creates a terminal (base) booth on the worktree and
		// removes it again when the shell ends; s starts the project's own.
		return plan{Verb: "open a shell in", Args: []string{"shell", "--run", "--code", w.Path}, Dir: w.Path,
			Interactive: true, Hold: true,
			Confirm: fmt.Sprintf("No booth on %s. Start a terminal booth for a shell? It is removed when the shell ends.",
				branchText(w))}, ""

	case keyStop, keyRestart, keyOpen, keyPorts, keyMessage, keyLog:
		return plan{}, fmt.Sprintf("No booth on %s; s starts one.", w.Name())
	}
	return plan{}, ""
}

// newWorktreePlan creates worktree name in repo, from its current HEAD, and
// starts its booth as a daemon. The worktree stays when the booth stops; d
// removes it.
func newWorktreePlan(repo *lifecycle.Repo, name string) plan {
	return plan{Verb: "create worktree", Args: []string{"--worktree", name, "--daemon"},
		Dir: repo.Root, Interactive: true, Hold: true, Done: "Created worktree " + name + " and started its booth."}
}
