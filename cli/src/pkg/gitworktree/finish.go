// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

// booth leaves things the way it found them: a worktree this run created is removed when the booth
// exits, and one that already existed is never touched. Removal happens only when nothing would
// be lost, and goes through `git worktree remove` / `git branch -d` without --force, so git's own
// refusal is the last guard. Anything kept is reported with its path and the reason.

// FinishOptions says how a session ends, besides the booth's exit code.
type FinishOptions struct {
	ExitCode     int
	Push         bool // --push: push the branch when the run succeeded
	KeepWorktree bool // --keep-worktree: keep the worktree this run created
	Existing     bool // the worktree existed before this run: never removed
}

// Outcome is what Finish did with a session's worktree.
type Outcome struct {
	Removed       bool
	BranchDeleted bool
	Pushed        bool
	NotPushed     bool     // --push was given and the branch was not pushed, for a reason to look at
	Messages      []string // one line each, for the user
}

// Finish ends the session on plan's worktree, after a booth that exited with opts.ExitCode.
// dir is where git runs from (the directory booth started in). For an existing worktree, plan
// needs only Path and Branch.
//
// A run succeeds when the booth exited 0, the tree is clean, and HEAD is still on the branch.
// Only then is anything pushed or removed; otherwise everything stays and Finish says why.
func Finish(dir string, plan Plan, opts FinishOptions) Outcome {
	var out Outcome
	say := func(format string, args ...any) {
		out.Messages = append(out.Messages, fmt.Sprintf(format, args...))
	}
	kept := func() Outcome {
		if opts.KeepWorktree && !opts.Existing {
			say("Kept worktree %s (--keep-worktree).", plan.Path)
		}
		return out
	}
	stop := func(reason, resume string) Outcome { // the run did not succeed: keep everything
		if opts.Push {
			out.NotPushed = true
			say("Did not push branch %s: %s.", plan.Branch, reason)
		}
		if opts.Existing || opts.KeepWorktree {
			return kept()
		}
		say("Kept worktree %s: %s.%s", plan.Path, reason, resume)
		return out
	}
	resume := fmt.Sprintf(" `booth --worktree %s` resumes it.", plan.Branch)

	if _, err := os.Stat(plan.Path); err != nil {
		return out // already gone
	}
	if !opts.Push && (opts.Existing || opts.KeepWorktree) {
		return kept() // nothing to push, nothing to remove
	}
	if opts.ExitCode != 0 {
		return stop(fmt.Sprintf("the booth exited with code %d", opts.ExitCode), resume)
	}
	status, err := git(plan.Path, "status", "--porcelain", "--untracked-files=all")
	if err != nil {
		return stop(err.Error(), "")
	}
	work, boothOwn := splitBoothRuntime(status)
	if work {
		return stop("it has uncommitted changes", resume)
	}
	if head, err := git(plan.Path, "symbolic-ref", "--quiet", "--short", "HEAD"); err != nil || head != plan.Branch {
		return stop(fmt.Sprintf("it is no longer on branch %s", plan.Branch), "")
	}
	ahead := -1 // unknown: an existing worktree has no base
	if plan.Base != "" {
		count, err := git(plan.Path, "rev-list", "--count", plan.Base+"..HEAD")
		if err != nil {
			return stop(err.Error(), "")
		}
		ahead, _ = strconv.Atoi(count)
	}

	remote := ""
	if opts.Push {
		if plan.NewBranch && ahead == 0 {
			say("Nothing to push: branch %s has no new commits.", plan.Branch)
		} else if remote, err = push(dir, plan.Branch, &out); err != nil {
			return stop("the push failed", resume)
		}
	}

	if opts.Existing || opts.KeepWorktree {
		return kept()
	}
	if boothOwn {
		// booth's own runtime files, untracked in a project with no .booth/.gitignore: not work,
		// and `git worktree remove` would refuse over them.
		_ = os.RemoveAll(filepath.Join(plan.Path, boothRuntimeDir))
		_ = os.Remove(filepath.Join(plan.Path, ".booth")) // only if that left it empty
	}
	if _, err := git(dir, "worktree", "remove", plan.Path); err != nil {
		say("Kept worktree %s: %v", plan.Path, err)
		return out
	}
	out.Removed = true
	removeEmptyUpTo(filepath.Dir(plan.Path), plan.Top)
	say("Removed worktree %s.", plan.Path)

	switch {
	case !plan.NewBranch:
		// Not this run's branch: it stays as it was found.
	case out.Pushed:
		// -d deletes it only when it matches what was pushed (its upstream).
		if _, err := git(dir, "branch", "-d", plan.Branch); err != nil {
			say("Kept branch %s: %v", plan.Branch, err)
		} else {
			out.BranchDeleted = true
			say("Deleted local branch %s: it is on %s.", plan.Branch, remote)
		}
	case ahead > 0:
		say("Kept branch %s: it has %d new commit(s).", plan.Branch, ahead)
	default:
		if _, err := git(dir, "branch", "-d", plan.Branch); err != nil {
			say("Kept branch %s: %v", plan.Branch, err)
		} else {
			out.BranchDeleted = true
			say("Deleted branch %s: it had no new commits.", plan.Branch)
		}
	}
	return out
}

// push pushes branch to its upstream, or else to origin, setting that as its upstream. It
// reports to out, and returns the remote pushed to.
func push(dir, branch string, out *Outcome) (string, error) {
	remote, _ := git(dir, "config", "--get", "branch."+branch+".remote")
	merge, _ := git(dir, "config", "--get", "branch."+branch+".merge")
	args := []string{"push"}
	if remote != "" && remote != "." && merge != "" {
		args = append(args, remote, "refs/heads/"+branch+":"+merge)
	} else {
		if _, err := git(dir, "remote", "get-url", "origin"); err != nil {
			err = fmt.Errorf("branch %s has no upstream, and there is no remote named origin", branch)
			out.Messages = append(out.Messages, err.Error())
			return "", err
		}
		remote = "origin"
		args = append(args, "--set-upstream", remote, "refs/heads/"+branch+":refs/heads/"+branch)
	}
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		err = fmt.Errorf("git push: %s", strings.TrimSpace(stderr.String()))
		out.Messages = append(out.Messages, err.Error())
		return "", err
	}
	out.Pushed = true
	out.Messages = append(out.Messages, fmt.Sprintf("Pushed branch %s to %s.", branch, remote))
	// The host's own hints, such as GitHub's link to open a pull request.
	for _, line := range strings.Split(stderr.String(), "\n") {
		if hint := strings.TrimSpace(strings.TrimPrefix(line, "remote:")); hint != "" && strings.HasPrefix(line, "remote:") {
			out.Messages = append(out.Messages, "  "+hint)
		}
	}
	return remote, nil
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
