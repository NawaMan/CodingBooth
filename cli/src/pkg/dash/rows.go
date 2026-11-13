// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// row is one line of the table: a booth, or a worktree that has no booth.
// Every row is selectable; there are no heading lines.
type row struct {
	repo     *lifecycle.Repo     // the repository the row is under; nil when ungrouped
	booth    *lifecycle.Booth    // the booth on this row
	worktree *lifecycle.Worktree // the worktree the booth runs in, or the bare worktree
	// main: a row that leads its group — a repository's main checkout, or a
	// booth in no repository (NAME in the group colour, not indented; a
	// repository's linked worktrees are).
	main bool
	// sep: a separator line the user put between groups (its key in the
	// saved order, "separator:<n>"); it has no booth, worktree or repository.
	sep string
}

// key names a row across refreshes: its booth, else its worktree.
func (r row) key() string {
	switch {
	case r.sep != "":
		return r.sep
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

	// No heading lines: each repository's main checkout leads its group and
	// its linked worktrees follow; booths in no repository come last, each
	// leading a group of its own.
	var rows []row
	for r := range repos {
		repo := &repos[r]
		for w := range repo.Worktrees {
			wt := &repo.Worktrees[w]
			lead := w == 0 // the main checkout comes first (a bare repository's first worktree stands in)
			in := placed[place{r, w}]
			if len(in) == 0 {
				rows = append(rows, row{repo: repo, worktree: wt, main: lead})
				continue
			}
			for _, i := range in {
				rows = append(rows, row{repo: repo, worktree: wt, booth: &booths[i], main: lead})
			}
		}
	}
	for _, i := range others {
		rows = append(rows, row{repo: otherBooths, booth: &booths[i], main: true})
	}
	return rows
}

// branchText is the WORKTREE cell: the branch, or "(detached)". The main
// checkout is not marked; it already leads its group.
func branchText(w *lifecycle.Worktree) string {
	if w == nil {
		return "-"
	}
	name := w.Branch
	if name == "" {
		name = "(detached)"
	}
	return name
}

// planForWorktree is what a key does to a worktree row that has no booth.
func planForWorktree(key string, r row) (plan, string) {
	w := r.worktree
	switch key {
	case keyStart:
		if w.Prunable {
			return plan{}, fmt.Sprintf("%s's folder is gone; d deletes the worktree record.", w.Name())
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
			return plan{}, "The main checkout is not deleted from here."
		}
		// A worktree whose folder is gone has no work left to read: delete
		// its record. Any other is read first (see deleteWorktreePlan).
		return deleteWorktreePlan(r, gitworktreeClean, nil), ""

	case keyShell:
		if w.Prunable {
			return plan{}, fmt.Sprintf("%s's folder is gone; d deletes the worktree record.", w.Name())
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

// gitworktreeClean is the state of a worktree with nothing to lose.
var gitworktreeClean = lifecycle.GitState{}

// deleteWorktreePlan is d on a worktree row, once its git status is read:
// state, or err when it could not be. A clean worktree is deleted as
// `booth worktree remove` does it, keeping a branch with commits found nowhere
// else. One with uncommitted files or unmerged commits, or whose status is not
// known, is force-deleted, after a question that says what is lost and urges a
// last look.
func deleteWorktreePlan(r row, state lifecycle.GitState, err error) plan {
	w := r.worktree
	done := "Deleted worktree " + w.Name() + "."
	args := []string{"worktree", "remove", w.Name()}
	var lost []string
	if state.Dirty > 0 {
		lost = append(lost, plural(state.Dirty, "uncommitted file"))
	}
	if state.Ahead > 0 {
		lost = append(lost, plural(state.Ahead, "unmerged commit"))
	}
	if err == nil && len(lost) == 0 {
		return plan{Verb: "delete worktree", Args: args, Dir: r.repo.Root,
			Confirm: fmt.Sprintf("Delete worktree %s and its branch? A branch with commits found nowhere else is kept.", w.Name()),
			Busy:    "deleting…", Done: done}
	}
	what := "work git could not read (" + errText(err) + ")"
	if err == nil {
		what = strings.Join(lost, " and ")
	}
	return plan{Verb: "delete worktree", Args: append(args, "--force", "--yes"), Dir: r.repo.Root, Danger: true,
		Confirm: fmt.Sprintf("⚠ %s has %s. Deleting it DISCARDS them for good, with its branch and its booths' volumes. "+
			"Look again first (t terminal, e editor, K GitKraken). Force delete?", w.Name(), what),
		Busy: "deleting…", Done: done}
}

func plural(n int, noun string) string {
	if n == 1 {
		return "1 " + noun
	}
	return fmt.Sprintf("%d %ss", n, noun)
}

func errText(err error) string {
	if err == nil {
		return ""
	}
	return err.Error()
}
