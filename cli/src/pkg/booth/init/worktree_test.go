// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// porcelain builds `git worktree list --porcelain -z` output from records of lines.
func porcelain(records ...[]string) string {
	var b strings.Builder
	for _, record := range records {
		for _, line := range record {
			b.WriteString(line + "\x00")
		}
		b.WriteString("\x00")
	}
	return b.String()
}

func TestParseWorktreeList(t *testing.T) {
	entries := parseWorktreeList(porcelain(
		[]string{"worktree /repo", "HEAD 1111", "branch refs/heads/main"},
		[]string{"worktree /repo/worktree/a b", "HEAD 2222", "branch refs/heads/feature/x"},
		[]string{"worktree /elsewhere/det", "HEAD 3333", "detached"},
		[]string{"worktree /gone", "HEAD 4444", "branch refs/heads/gone", "prunable gitdir file points to non-existent location"},
	))
	if len(entries) != 4 {
		t.Fatalf("want 4 entries, got %d: %+v", len(entries), entries)
	}
	want := []worktreeEntry{
		{path: "/repo", branch: "main"},
		{path: "/repo/worktree/a b", branch: "feature/x"},
		{path: "/elsewhere/det"},
		{path: "/gone", branch: "gone", prunable: true},
	}
	for i, w := range want {
		if entries[i] != w {
			t.Errorf("entry %d: want %+v, got %+v", i, w, entries[i])
		}
	}
}

func TestParseWorktreeList_Bare(t *testing.T) {
	entries := parseWorktreeList(porcelain(
		[]string{"worktree /repo.git", "bare"},
		[]string{"worktree /wt/a", "HEAD 1111", "branch refs/heads/a"},
	))
	if len(entries) != 2 || !entries[0].bare || entries[1].bare {
		t.Fatalf("bare flag not read: %+v", entries)
	}
}

var sampleWorktrees = []worktreeEntry{
	{path: "/repo", branch: "main"},
	{path: "/repo/worktree/fix-1", branch: "fix-1"},
	{path: "/other/place/topic", branch: "feature/topic"},
	{path: "/repo/.claude/worktrees/agent-x"},
	{path: "/gone/old", branch: "old", prunable: true},
}

func TestMatchWorktree_ByBranch(t *testing.T) {
	got, err := matchWorktree(sampleWorktrees, "feature/topic")
	if err != nil || got != "/other/place/topic" {
		t.Fatalf("want /other/place/topic, got %q (%v)", got, err)
	}
}

func TestMatchWorktree_ByFolder(t *testing.T) {
	for name, want := range map[string]string{
		"topic":   "/other/place/topic", // branch is feature/topic: matched by folder
		"agent-x": "/repo/.claude/worktrees/agent-x",
		"fix-1":   "/repo/worktree/fix-1",
	} {
		got, err := matchWorktree(sampleWorktrees, name)
		if err != nil || got != want {
			t.Errorf("%s: want %q, got %q (%v)", name, want, got, err)
		}
	}
}

func TestMatchWorktree_BranchBeatsFolder(t *testing.T) {
	entries := []worktreeEntry{
		{path: "/repo", branch: "main"},
		{path: "/wt/x", branch: "other"}, // folder named x
		{path: "/wt/y", branch: "x"},     // branch named x
	}
	got, err := matchWorktree(entries, "x")
	if err != nil || got != "/wt/y" {
		t.Fatalf("branch match should win: got %q (%v)", got, err)
	}
}

func TestMatchWorktree_Errors(t *testing.T) {
	ambiguous := []worktreeEntry{
		{path: "/repo", branch: "main"},
		{path: "/a/same", branch: "p"},
		{path: "/b/same", branch: "q"},
	}
	cases := []struct {
		name    string
		entries []worktreeEntry
		arg     string
		want    string
	}{
		{"none", sampleWorktrees, "nope", "no worktree has the branch or folder name"},
		{"main by branch", sampleWorktrees, "main", "is the main checkout"},
		{"main by folder", sampleWorktrees, "repo", "is the main checkout"},
		{"prunable", sampleWorktrees, "old", "that folder is gone"},
		{"ambiguous", ambiguous, "same", "/a/same"},
	}
	for _, c := range cases {
		got, err := matchWorktree(c.entries, c.arg)
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: want error containing %q, got %q (%v)", c.name, c.want, got, err)
		}
	}
}

func TestMatchWorktree_SkipsBare(t *testing.T) {
	entries := []worktreeEntry{
		{path: "/srv/repo.git", bare: true},
		{path: "/wt/repo.git-copy", branch: "work"},
	}
	if _, err := matchWorktree(entries, "repo.git"); err == nil ||
		!strings.Contains(err.Error(), "no worktree") {
		t.Fatalf("a bare main should never match, got %v", err)
	}
	got, err := matchWorktree(entries, "work")
	if err != nil || got != "/wt/repo.git-copy" {
		t.Fatalf("want /wt/repo.git-copy, got %q (%v)", got, err)
	}
}

// TestResolveWorktreeCode runs real git: lookup from the main clone and from inside another worktree.
func TestResolveWorktreeCode(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	root := t.TempDir()
	main := filepath.Join(root, "proj")
	git := func(dir string, args ...string) {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	git(root, "init", "-q", "-b", "main", main)
	git(main, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init")
	sibling := filepath.Join(root, "proj.worktrees", "alpha")
	nested := filepath.Join(main, "worktree", "beta")
	git(main, "worktree", "add", "-q", sibling, "-b", "alpha")
	git(main, "worktree", "add", "-q", nested, "-b", "feature/beta")

	eval := func(p string) string {
		r, err := filepath.EvalSymlinks(p)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	for _, c := range []struct{ from, name, want string }{
		{main, "alpha", sibling},
		{main, "feature/beta", nested},
		{main, "beta", nested},
		{sibling, "beta", nested}, // from inside another worktree
		{filepath.Join(nested), "alpha", sibling},
	} {
		got, err := resolveWorktreeCode(c.from, c.name)
		if err != nil {
			t.Errorf("from %s, %s: %v", c.from, c.name, err)
			continue
		}
		if eval(got) != eval(c.want) {
			t.Errorf("from %s, %s: want %s, got %s", c.from, c.name, c.want, got)
		}
	}

	if _, err := resolveWorktreeCode(main, "main"); err == nil {
		t.Error("main should be refused")
	}

	plain := filepath.Join(root, "plain")
	if err := os.MkdirAll(plain, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := resolveWorktreeCode(plain, "alpha"); err == nil ||
		!strings.Contains(err.Error(), "not in one") {
		t.Errorf("outside a repo: want a not-a-repository error, got %v", err)
	}
}

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
		t.Errorf("name: want the worktree folder name alpha, got %s", out.Ctx.Name())
	}
}
