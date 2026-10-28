// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// booth leaves things the way it found them: a worktree this run created is removed when the booth
// exits, and one that already existed is never touched. Removal happens only when nothing would
// be lost, and goes through `git worktree remove` / `git branch -d` without --force, so git's own
// refusal is the last guard. Anything kept is reported with its path and the reason.

// Outcome is what Finish did with a created worktree.
type Outcome struct {
	Removed       bool
	BranchDeleted bool
	Messages      []string // one line each, for the user
}

// Finish ends the session for a worktree plan created, after a booth that exited with exitCode.
// dir is where git runs from (the directory booth started in).
func Finish(dir string, plan Plan, exitCode int) Outcome {
	var out Outcome
	keep := func(format string, args ...any) Outcome {
		out.Messages = append(out.Messages, fmt.Sprintf("Kept worktree %s: ", plan.Path)+fmt.Sprintf(format, args...))
		return out
	}

	if _, err := os.Stat(plan.Path); err != nil {
		return out // already gone
	}
	if exitCode != 0 {
		return keep("the booth exited with code %d. `booth --worktree %s` resumes it.", exitCode, plan.Branch)
	}
	status, err := git(plan.Path, "status", "--porcelain", "--untracked-files=all")
	if err != nil {
		return keep("%v", err)
	}
	work, boothOwn := splitBoothRuntime(status)
	if work {
		return keep("it has uncommitted changes. `booth --worktree %s` resumes it.", plan.Branch)
	}
	if head, err := git(plan.Path, "symbolic-ref", "--quiet", "--short", "HEAD"); err != nil || head != plan.Branch {
		return keep("it is no longer on branch %s.", plan.Branch)
	}
	count, err := git(plan.Path, "rev-list", "--count", plan.Base+"..HEAD")
	if err != nil {
		return keep("%v", err)
	}
	ahead, _ := strconv.Atoi(count)

	if boothOwn {
		// booth's own runtime files, untracked in a project with no .booth/.gitignore: not work,
		// and `git worktree remove` would refuse over them.
		_ = os.RemoveAll(filepath.Join(plan.Path, boothRuntimeDir))
		_ = os.Remove(filepath.Join(plan.Path, ".booth")) // only if that left it empty
	}
	if _, err := git(dir, "worktree", "remove", plan.Path); err != nil {
		return keep("%v", err)
	}
	out.Removed = true
	removeEmptyUpTo(filepath.Dir(plan.Path), plan.Top)
	out.Messages = append(out.Messages, fmt.Sprintf("Removed worktree %s.", plan.Path))

	switch {
	case !plan.NewBranch:
		// Not this run's branch: it stays as it was found.
	case ahead > 0:
		out.Messages = append(out.Messages,
			fmt.Sprintf("Kept branch %s: it has %d new commit(s).", plan.Branch, ahead))
	default:
		if _, err := git(dir, "branch", "-d", plan.Branch); err != nil {
			out.Messages = append(out.Messages, fmt.Sprintf("Kept branch %s: %v", plan.Branch, err))
		} else {
			out.BranchDeleted = true
			out.Messages = append(out.Messages, fmt.Sprintf("Deleted branch %s: it had no new commits.", plan.Branch))
		}
	}
	return out
}

// boothRuntimeDir is where booth writes its own per-run files in the code folder.
const boothRuntimeDir = ".booth/.tmp"

// splitBoothRuntime reads `git status --porcelain --untracked-files=all`: work is whether any line
// is something other than an untracked file of booth's own under .booth/.tmp/, and boothOwn is
// whether there are such files.
func splitBoothRuntime(status string) (work, boothOwn bool) {
	for _, line := range strings.Split(status, "\n") {
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "?? "+boothRuntimeDir+"/") {
			boothOwn = true
			continue
		}
		work = true
	}
	return work, boothOwn
}

// removeEmptyUpTo removes dir and its parents while they are empty, stopping after top: the
// folders creating the worktree made, like <root>/feature/ for feature/x, and no others.
func removeEmptyUpTo(dir, top string) {
	if top == "" {
		return
	}
	rel, err := filepath.Rel(top, dir)
	if err != nil || rel == ".." || filepath.IsAbs(rel) || (len(rel) >= 3 && rel[:3] == ".."+string(filepath.Separator)) {
		return // dir is not inside top: nothing of ours to remove
	}
	for {
		if err := os.Remove(dir); err != nil { // fails on a folder that is not empty
			return
		}
		if dir == top {
			return
		}
		dir = filepath.Dir(dir)
	}
}
