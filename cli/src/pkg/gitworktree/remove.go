// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// `booth worktree remove` ends a worktree on purpose, whoever made it. Without --force it removes
// only what loses nothing; Loss says what that would be, so the caller can refuse or ask.

// Loss is what removing a worktree and its branch would throw away.
type Loss struct {
	Changes    []string // `git status --porcelain` lines: uncommitted and untracked files
	HeadOnly   int      // detached: commits at HEAD that no branch, remote or tag has
	BranchOnly int      // commits on the branch that no other branch, remote or tag has
}

// Worktree is whether removing the worktree folder loses work. BranchOnly is lost only with the
// branch.
func (l Loss) Worktree() bool { return len(l.Changes) > 0 || l.HeadOnly > 0 }

// Assess reports what removing e, and deleting its branch, would lose. Booth's own runtime files
// (.booth/.tmp/) are not work, as at exit.
func Assess(dir string, e Entry) (Loss, error) {
	var loss Loss
	status, err := git(e.Path, "status", "--porcelain", "--untracked-files=all")
	if err != nil {
		return loss, err
	}
	for _, line := range strings.Split(status, "\n") {
		if line != "" && !strings.HasPrefix(line, "?? "+boothRuntimeDir+"/") {
			loss.Changes = append(loss.Changes, line)
		}
	}
	if e.Branch == "" {
		loss.HeadOnly, err = countOnly(e.Path, "HEAD")
		return loss, err
	}
	loss.BranchOnly, err = countOnly(dir, "refs/heads/"+e.Branch, e.Branch)
	return loss, err
}

// countOnly counts the commits reachable from rev (read in at) that no other local branch,
// remote-tracking branch or tag reaches. ownBranch, when given, is rev's own branch, left out of
// "other" (git's --exclude takes it without refs/heads/ before --branches).
func countOnly(at, rev string, ownBranch ...string) (int, error) {
	args := []string{"rev-list", "--count", rev, "--not"}
	for _, b := range ownBranch {
		args = append(args, "--exclude="+b)
	}
	args = append(args, "--branches", "--remotes", "--tags")
	out, err := git(at, args...)
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(out)
}

// Remove removes worktree e (--force: even with changes), then the empty folders its branch
// path made (<root>/feature/ for feature/x). The root stays, even empty (see belowRoot).
func Remove(dir string, e Entry, force bool) error {
	if !force {
		// booth's own runtime files: not work, and `git worktree remove` would refuse over them.
		_ = os.RemoveAll(filepath.Join(e.Path, boothRuntimeDir))
		_ = os.Remove(filepath.Join(e.Path, ".booth")) // only if that left it empty
	}
	args := []string{"worktree", "remove"}
	if force {
		args = append(args, "--force")
	}
	if _, err := git(dir, append(args, e.Path)...); err != nil {
		return err
	}
	if branch := filepath.FromSlash(e.Branch); strings.Contains(e.Branch, "/") &&
		strings.HasSuffix(e.Path, string(filepath.Separator)+branch) {
		root := strings.TrimSuffix(e.Path, string(filepath.Separator)+branch)
		first := strings.SplitN(e.Branch, "/", 2)[0]
		removeEmptyUpTo(filepath.Dir(e.Path), filepath.Join(root, first))
	}
	return nil
}

// DeleteBranch deletes branch with -D: the caller has checked with Assess what that loses.
func DeleteBranch(dir, branch string) error {
	_, err := git(dir, "branch", "-D", branch)
	return err
}

// Upstream is branch's upstream as "<remote>/<branch>", or "" when it has none.
func Upstream(dir, branch string) string {
	out, err := git(dir, "rev-parse", "--abbrev-ref", "--symbolic-full-name", branch+"@{upstream}")
	if err != nil {
		return ""
	}
	return out
}
