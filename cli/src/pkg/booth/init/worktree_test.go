// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

// TestInit_WorktreeSetsCodeAndConfig: --worktree picks the code path, and the worktree's own
// .booth/config.toml is the one read.
func TestInit_WorktreeSetsCodeAndConfig(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	main := filepath.Join(root, "proj")
	wt := filepath.Join(root, "proj.worktrees", "alpha")
	for _, args := range [][]string{
		{"init", "-q", "-b", "main", main},
		{"-C", main, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init"},
		{"-C", main, "worktree", "add", "-q", wt, "-b", "alpha"},
	} {
		if out, err := exec.Command("git", args...).CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	for dir, port := range map[string]string{main: "11111", wt: "12345"} {
		if err := os.MkdirAll(filepath.Join(dir, ".booth"), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(dir, ".booth", "config.toml"), []byte("port = \""+port+"\"\n"), 0o644); err != nil {
			t.Fatal(err)
		}
	}

	out := RunInitializeAppContext(t, TestInput{
		Args:        []string{"booth", "--worktree", "alpha"},
		CurrentPath: main,
		HostUID:     "1000", HostGID: "1000",
	})
	if out.Ctx.Code() != wt {
		t.Errorf("code: want %s, got %s", wt, out.Ctx.Code())
	}
	if out.Ctx.Port() != "12345" {
		t.Errorf("port: want the worktree's 12345, got %s", out.Ctx.Port())
	}
	if out.Ctx.Name() != "alpha" {
		t.Errorf("name: want the branch name alpha, got %s", out.Ctx.Name())
	}
}
