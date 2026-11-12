// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"path/filepath"
	"strings"
	"testing"
)

func TestFinish_LastWorktreeKeepsGitWorktreesDir(t *testing.T) {
	_, main := repo(t)
	worktrees := filepath.Join(main, ".git", "worktrees")
	p := plan(t, main, CreateOptions{Name: "x"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	// A prune in between drops the keep file; the removal puts it back first.
	if !exists(filepath.Join(worktrees, worktreesKeepFile)) {
		t.Fatal("want Create to write the keep file")
	}
	run(t, main, "worktree", "prune")
	if exists(filepath.Join(worktrees, worktreesKeepFile)) {
		t.Fatal("expected git's prune to drop the keep file")
	}
	if out := Finish(main, p, FinishOptions{Remove: true}); !out.Removed {
		t.Fatalf("want the worktree removed: %+v", out)
	}
	if !isDir(worktrees) || !exists(filepath.Join(worktrees, worktreesKeepFile)) {
		t.Error("want .git/worktrees/ kept, holding only the keep file, after the last worktree goes")
	}
}

func TestRemove_LastWorktreeKeepsGitWorktreesDir(t *testing.T) {
	root, main := repo(t)
	e := worktree(t, main, filepath.Join(root, "wt", "w"), "w")
	if err := Remove(main, e, false); err != nil {
		t.Fatal(err)
	}
	if !exists(filepath.Join(main, ".git", "worktrees", worktreesKeepFile)) {
		t.Error("want .git/worktrees/ kept after the last worktree goes")
	}
}

func TestKeepWorktreesDir_InvisibleToGit(t *testing.T) {
	root, main := repo(t)
	worktree(t, main, filepath.Join(root, "wt", "w"), "w")
	keepWorktreesDir(main)
	entries, err := List(main)
	if err != nil || len(entries) != 2 {
		t.Fatalf("want main and w listed, nothing for the keep file: %+v %v", entries, err)
	}
	if status := run(t, main, "status", "--porcelain"); strings.TrimSpace(status) != "" {
		t.Errorf("want a clean status: %q", status)
	}
}
