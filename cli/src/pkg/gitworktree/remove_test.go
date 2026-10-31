// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"os"
	"path/filepath"
	"testing"
)

func worktree(t *testing.T, main, path, branch string) Entry {
	t.Helper()
	run(t, main, "worktree", "add", "-q", path, "-b", branch)
	e, err := Resolve(main, branch)
	if err != nil {
		t.Fatal(err)
	}
	return e
}

func TestAssess(t *testing.T) {
	root, main := repo(t)
	e := worktree(t, main, filepath.Join(root, "wt", "w"), "w")

	loss, err := Assess(main, e)
	if err != nil || loss.Worktree() || loss.BranchOnly != 0 {
		t.Fatalf("a fresh worktree loses nothing: %+v %v", loss, err)
	}

	commit(t, e.Path, "one")
	commit(t, e.Path, "two")
	if err := os.WriteFile(filepath.Join(e.Path, "draft.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if loss, _ = Assess(main, e); loss.BranchOnly != 2 || len(loss.Changes) != 1 {
		t.Fatalf("want 2 commits only on w and 1 untracked file: %+v", loss)
	}

	run(t, main, "branch", "copy", "w") // another branch has them now
	if loss, _ = Assess(main, e); loss.BranchOnly != 0 {
		t.Errorf("commits another branch has are not lost: %+v", loss)
	}
}

func TestAssess_DetachedHead(t *testing.T) {
	root, main := repo(t)
	path := filepath.Join(root, "wt", "d")
	run(t, main, "worktree", "add", "-q", "--detach", path)
	commit(t, path, "stray")
	e, err := Resolve(main, "d")
	if err != nil {
		t.Fatal(err)
	}
	if loss, _ := Assess(main, e); loss.HeadOnly != 1 || !loss.Worktree() {
		t.Errorf("a commit only at a detached HEAD goes with the worktree: %+v", loss)
	}
}

func TestRemove_TidiesBranchFoldersAndKeepsRoot(t *testing.T) {
	root, main := repo(t)
	wtRoot := filepath.Join(root, "proj.worktrees")
	e := worktree(t, main, filepath.Join(wtRoot, "feature", "x"), "feature/x")
	if err := Remove(main, e, false); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(wtRoot, "feature")) || !exists(wtRoot) {
		t.Error("want the empty feature/ folder removed, and booth's default root kept")
	}

	userRoot := filepath.Join(root, "mine")
	e = worktree(t, main, filepath.Join(userRoot, "team", "y"), "team/y")
	if err := Remove(main, e, false); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(userRoot, "team")) || !exists(userRoot) {
		t.Error("want team/ removed, and the user's own root kept")
	}
}

func TestRemove_RefusesChangesUnlessForced(t *testing.T) {
	root, main := repo(t)
	e := worktree(t, main, filepath.Join(root, "wt", "w"), "w")
	if err := os.WriteFile(filepath.Join(e.Path, "draft.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Remove(main, e, false); err == nil || !exists(e.Path) {
		t.Fatal("git refuses a worktree with changes, without --force")
	}
	if err := Remove(main, e, true); err != nil || exists(e.Path) {
		t.Fatalf("--force removes it: %v", err)
	}
	if err := DeleteBranch(main, "w"); err != nil {
		t.Fatal(err)
	}
}
