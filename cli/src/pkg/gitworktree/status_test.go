// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"os"
	"path/filepath"
	"testing"
)

func status(t *testing.T, path, branch, base string) State {
	t.Helper()
	s, err := Status(path, branch, base)
	if err != nil {
		t.Fatal(err)
	}
	return s
}

func TestStatus_AheadBehindDirty(t *testing.T) {
	root, main := repo(t)
	e := worktree(t, main, filepath.Join(root, "wt", "w"), "w")

	if s := status(t, e.Path, "w", "main"); s != (State{Base: "main"}) {
		t.Fatalf("a fresh worktree is even and clean: %+v", s)
	}

	commit(t, e.Path, "one")
	commit(t, e.Path, "two")
	commit(t, main, "elsewhere")
	if s := status(t, e.Path, "w", "main"); s.Ahead != 2 || s.Behind != 1 || s.Merged {
		t.Errorf("want 2 ahead, 1 behind, not merged: %+v", s)
	}

	if err := os.WriteFile(filepath.Join(e.Path, "draft.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(e.Path, ".booth", ".tmp"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(e.Path, ".booth", ".tmp", "ports.json"), []byte("{}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if s := status(t, e.Path, "w", "main"); s.Dirty != 1 {
		t.Errorf("one file of work; booth's runtime files are not counted: %+v", s)
	}
}

func TestStatus_MergedVersusFresh(t *testing.T) {
	root, main := repo(t)
	landed := worktree(t, main, filepath.Join(root, "wt", "landed"), "landed")
	fresh := worktree(t, main, filepath.Join(root, "wt", "fresh"), "fresh")

	commit(t, landed.Path, "work")
	run(t, main, "-c", "user.email=t@t", "-c", "user.name=t", "merge", "-q", "--no-ff", "-m", "land", "landed")

	if s := status(t, landed.Path, "landed", "main"); !s.Merged || s.Ahead != 0 || s.Behind != 1 {
		t.Errorf("a landed branch is merged, behind by the merge commit: %+v", s)
	}
	if s := status(t, fresh.Path, "fresh", "main"); s.Merged || s.Behind != 2 {
		t.Errorf("a branch that never had a commit is behind, not merged: %+v", s)
	}
}

func TestStatus_FastForwardIsMerged(t *testing.T) {
	root, main := repo(t)
	e := worktree(t, main, filepath.Join(root, "wt", "ff"), "ff")
	commit(t, e.Path, "work")
	run(t, main, "merge", "-q", "--ff-only", "ff")

	if s := status(t, e.Path, "ff", "main"); !s.Merged || s.Ahead != 0 || s.Behind != 0 {
		t.Errorf("a fast-forwarded branch is merged and even: %+v", s)
	}
}

func TestStatus_NoBase(t *testing.T) {
	_, main := repo(t)
	if err := os.WriteFile(filepath.Join(main, "a.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if s := status(t, main, "main", ""); s != (State{Dirty: 1}) {
		t.Errorf("without a base only Dirty is read: %+v", s)
	}
}

func TestStatus_MainAgainstUpstream(t *testing.T) {
	root, main := repo(t)
	clone := filepath.Join(root, "clone")
	run(t, root, "clone", "-q", main, clone)
	commit(t, clone, "unpushed")

	base := Upstream(clone, "main")
	if base != "origin/main" {
		t.Fatalf("upstream: %q", base)
	}
	// main is the base's own branch name on the remote, never "merged" with itself.
	if s := status(t, clone, "main", base); s.Ahead != 1 || s.Behind != 0 || s.Merged {
		t.Errorf("one unpushed commit: %+v", s)
	}
}
