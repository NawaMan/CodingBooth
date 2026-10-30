// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

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
	entries := parseList(porcelain(
		[]string{"worktree /repo", "HEAD 1111", "branch refs/heads/main"},
		[]string{"worktree /repo/worktree/a b", "HEAD 2222", "branch refs/heads/feature/x"},
		[]string{"worktree /elsewhere/det", "HEAD 3333", "detached"},
		[]string{"worktree /gone", "HEAD 4444", "branch refs/heads/gone", "prunable gitdir file points to non-existent location"},
	))
	if len(entries) != 4 {
		t.Fatalf("want 4 entries, got %d: %+v", len(entries), entries)
	}
	want := []Entry{
		{Path: "/repo", Branch: "main"},
		{Path: "/repo/worktree/a b", Branch: "feature/x"},
		{Path: "/elsewhere/det"},
		{Path: "/gone", Branch: "gone", Prunable: true},
	}
	for i, w := range want {
		w.Path = filepath.FromSlash(w.Path) // git's / becomes \ on Windows
		if entries[i] != w {
			t.Errorf("entry %d: want %+v, got %+v", i, w, entries[i])
		}
	}
}

func TestParseWorktreeList_Bare(t *testing.T) {
	entries := parseList(porcelain(
		[]string{"worktree /repo.git", "bare"},
		[]string{"worktree /wt/a", "HEAD 1111", "branch refs/heads/a"},
	))
	if len(entries) != 2 || !entries[0].Bare || entries[1].Bare {
		t.Fatalf("bare flag not read: %+v", entries)
	}
}

var sampleWorktrees = []Entry{
	{Path: "/repo", Branch: "main"},
	{Path: "/repo/worktree/fix-1", Branch: "fix-1"},
	{Path: "/other/place/topic", Branch: "feature/topic"},
	{Path: "/repo/.claude/worktrees/agent-x"},
	{Path: "/gone/old", Branch: "old", Prunable: true},
}

func TestMatchWorktree_ByBranch(t *testing.T) {
	got, err := findPath(sampleWorktrees, "feature/topic")
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
		got, err := findPath(sampleWorktrees, name)
		if err != nil || got != want {
			t.Errorf("%s: want %q, got %q (%v)", name, want, got, err)
		}
	}
}

func TestMatchWorktree_BranchBeatsFolder(t *testing.T) {
	entries := []Entry{
		{Path: "/repo", Branch: "main"},
		{Path: "/wt/x", Branch: "other"}, // folder named x
		{Path: "/wt/y", Branch: "x"},     // branch named x
	}
	got, err := findPath(entries, "x")
	if err != nil || got != "/wt/y" {
		t.Fatalf("branch match should win: got %q (%v)", got, err)
	}
}

func TestMatchWorktree_Errors(t *testing.T) {
	ambiguous := []Entry{
		{Path: "/repo", Branch: "main"},
		{Path: "/a/same", Branch: "p"},
		{Path: "/b/same", Branch: "q"},
	}
	cases := []struct {
		name    string
		entries []Entry
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
		got, err := findPath(c.entries, c.arg)
		if err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%s: want error containing %q, got %q (%v)", c.name, c.want, got, err)
		}
	}
}

func TestMatchWorktree_SkipsBare(t *testing.T) {
	entries := []Entry{
		{Path: "/srv/repo.git", Bare: true},
		{Path: "/wt/repo.git-copy", Branch: "work"},
	}
	if _, err := findPath(entries, "repo.git"); err == nil ||
		!strings.Contains(err.Error(), "no worktree") {
		t.Fatalf("a bare main should never match, got %v", err)
	}
	got, err := findPath(entries, "work")
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
		got, err := resolvePath(c.from, c.name)
		if err != nil {
			t.Errorf("from %s, %s: %v", c.from, c.name, err)
			continue
		}
		if eval(got) != eval(c.want) {
			t.Errorf("from %s, %s: want %s, got %s", c.from, c.name, c.want, got)
		}
	}

	if _, err := resolvePath(main, "main"); err == nil {
		t.Error("main should be refused")
	}

	plain := filepath.Join(root, "plain")
	if err := os.MkdirAll(plain, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := resolvePath(plain, "alpha"); err == nil ||
		!strings.Contains(err.Error(), "not in one") {
		t.Errorf("outside a repo: want a not-a-repository error, got %v", err)
	}
}

// findPath and resolvePath are Find and Resolve, reduced to the path the tests compare.
func findPath(entries []Entry, name string) (string, error) {
	e, err := Find(entries, name)
	return e.Path, err
}

func resolvePath(dir, name string) (string, error) {
	e, err := Resolve(dir, name)
	return e.Path, err
}

func TestBoothName(t *testing.T) {
	for _, c := range []struct {
		entry Entry
		want  string
	}{
		{Entry{Path: "/r/feature/x", Branch: "feature/x"}, "feature-x"},
		{Entry{Path: "/r/whatever", Branch: "fix-1"}, "fix-1"},
		{Entry{Path: "/r/det"}, "det"},
		{Entry{Path: "/r/a", Branch: "user@host/odd+name"}, "user-host-odd-name"},
	} {
		if got := BoothName(c.entry); got != c.want {
			t.Errorf("%+v: want %q, got %q", c.entry, c.want, got)
		}
	}
}
