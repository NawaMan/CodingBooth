// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"fmt"
	"strconv"
	"strings"
)

// State is a worktree's git status, as booth dashboard shows it. It reads local refs only: nothing
// is fetched, so ahead/behind is against what this clone last saw.
type State struct {
	Dirty  int    // changed and untracked files; booth's own runtime files are not counted
	Base   string // what Ahead and Behind count against; "" when there is none
	Ahead  int    // commits on HEAD that Base lacks
	Behind int    // commits on Base that HEAD lacks
	// Merged: nothing ahead of Base, and the branch has had commits of its own, so they landed.
	// A branch that never had any is just behind; the two look the same to ancestry alone.
	Merged bool
}

// Status reads the git status of the worktree at path, on branch ("" when detached), against
// base ("" for none: then only Dirty is read).
func Status(path, branch, base string) (State, error) {
	state := State{Base: base}
	// --no-optional-locks: this runs in the background, again and again, and must never take
	// index.lock from a git the user runs at the same time.
	status, err := git(path, "--no-optional-locks", "status", "--porcelain", "--untracked-files=all")
	if err != nil {
		return state, err
	}
	for _, line := range strings.Split(status, "\n") {
		if line != "" && !strings.HasPrefix(line, "?? "+boothRuntimeDir+"/") {
			state.Dirty++
		}
	}
	if base == "" {
		return state, nil
	}

	counts, err := git(path, "rev-list", "--left-right", "--count", base+"...HEAD")
	if err != nil {
		return state, err
	}
	fields := strings.Fields(counts)
	if len(fields) != 2 {
		return state, fmt.Errorf("git rev-list --left-right --count: unexpected %q", counts)
	}
	if state.Behind, err = strconv.Atoi(fields[0]); err != nil {
		return state, err
	}
	if state.Ahead, err = strconv.Atoi(fields[1]); err != nil {
		return state, err
	}
	if state.Ahead == 0 && branch != "" && branch != base {
		state.Merged = hadCommits(path, branch)
	}
	return state, nil
}

// hadCommits: branch's reflog shows a commit made on it (commit, merge, cherry-pick), not only
// its creation or a reset. No reflog (expired, or core.logAllRefUpdates off) says no.
func hadCommits(path, branch string) bool {
	log, err := git(path, "reflog", "show", "--format=%gs", "refs/heads/"+branch, "--")
	if err != nil {
		return false
	}
	for _, line := range strings.Split(log, "\n") {
		for _, prefix := range []string{"commit", "merge", "cherry-pick"} {
			if strings.HasPrefix(line, prefix) {
				return true
			}
		}
	}
	return false
}
