// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"os"
	"path/filepath"
)

// worktreesKeepFile holds the repository's .git/worktrees/ open once its last worktree is removed.
// Git deletes that folder when it empties; the next worktree recreates it, and Docker Desktop on
// macOS (VirtioFS) cannot mount under a folder deleted and recreated within about a minute -- and a
// booth on a worktree mounts git's pointer files at .git/worktrees/<id>/. `git worktree remove`
// only rmdirs the folder, so the file keeps it. `git worktree prune` (and gc) drops it as "not a
// valid directory"; the next worktree booth creates or removes puts it back.
const worktreesKeepFile = ".codingbooth-keep"

// keepWorktreesDir writes worktreesKeepFile into the .git/worktrees/ of the repository at dir,
// when that folder exists. It is best effort: a folder it cannot keep only means that a booth
// started within the minute after the last worktree goes may fail to mount.
func keepWorktreesDir(dir string) {
	common, err := git(dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
	if err != nil {
		return
	}
	worktrees := filepath.Join(common, "worktrees")
	if !isDir(worktrees) {
		return
	}
	keep := filepath.Join(worktrees, worktreesKeepFile)
	if _, err := os.Lstat(keep); err == nil {
		return
	}
	_ = os.WriteFile(keep, []byte("Keeps this folder when its last worktree is removed: see CodingBooth's docs/BOOTH_WORKTREE.md.\n"), 0o644)
}

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}
