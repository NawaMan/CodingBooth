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

// repo makes a main clone with one commit under a fresh temp dir and returns (root, main).
func repo(t *testing.T) (string, string) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	main := filepath.Join(root, "proj")
	run(t, root, "init", "-q", "-b", "main", main)
	commit(t, main, "init")
	return root, main
}

func run(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func commit(t *testing.T, dir, msg string) {
	t.Helper()
	run(t, dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", msg)
}

func plan(t *testing.T, dir string, opts CreateOptions) Plan {
	t.Helper()
	entries, err := List(dir)
	if err != nil {
		t.Fatal(err)
	}
	p, err := PlanCreate(dir, entries, opts)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func TestPlanCreate_DefaultRootBesideMainClone(t *testing.T) {
	root, main := repo(t)
	p := plan(t, main, CreateOptions{Name: "feature/x"})
	if want := filepath.Join(root, "proj.worktrees", "feature", "x"); p.Path != want {
		t.Errorf("path: want %s, got %s", want, p.Path)
	}
	if want := filepath.Join(root, "proj.worktrees"); p.Top != want {
		t.Errorf("top: want %s (the root does not exist yet), got %s", want, p.Top)
	}
	if !p.NewBranch || p.ExcludeFile != "" {
		t.Errorf("want a new branch and no exclude for a root outside the repo: %+v", p)
	}
}

func TestPlanCreate_FollowsExistingWorktrees(t *testing.T) {
	_, main := repo(t)
	run(t, main, "worktree", "add", "-q", filepath.Join(main, "worktree", "one"), "-b", "one")
	run(t, main, "worktree", "add", "-q", filepath.Join(main, "worktree", "team", "two"), "-b", "team/two")
	run(t, main, "worktree", "add", "-q", filepath.Join(main, ".claude", "worktrees", "agent"), "-b", "agent")

	p := plan(t, main, CreateOptions{Name: "three"})
	if want := filepath.Join(main, "worktree", "three"); p.Path != want {
		t.Errorf("path: want %s (the shared root, .claude/ ignored), got %s", want, p.Path)
	}
	if p.ExcludeLine != "/worktree/" || !strings.HasSuffix(p.ExcludeFile, filepath.Join(".git", "info", "exclude")) {
		t.Errorf("a root inside the repo is excluded locally: %q in %q", p.ExcludeLine, p.ExcludeFile)
	}
}

func TestSharedRoot_Disagreeing(t *testing.T) {
	entries := []Entry{
		{Path: "/r", Branch: "main"},
		{Path: "/a/one", Branch: "one"},
		{Path: "/b/two", Branch: "two"},
	}
	if got := sharedRoot(entries); got != "" {
		t.Errorf("worktrees in two places: want no habit, got %q", got)
	}
}

func TestPlanCreate_GivenRootAndFrom(t *testing.T) {
	root, main := repo(t)
	first := run(t, main, "rev-parse", "HEAD")
	commit(t, main, "second")
	p := plan(t, main, CreateOptions{Name: "x", Root: filepath.Join(root, "elsewhere"), From: first})
	if p.Path != filepath.Join(root, "elsewhere", "x") || p.Base != first {
		t.Errorf("want <given root>/x from the first commit, got %+v", p)
	}
}

func TestPlanCreate_ExistingBranch(t *testing.T) {
	_, main := repo(t)
	run(t, main, "branch", "old")
	p := plan(t, main, CreateOptions{Name: "old"})
	if p.NewBranch {
		t.Error("an existing branch is checked out, not created")
	}
	entries, _ := List(main)
	if _, err := PlanCreate(main, entries, CreateOptions{Name: "old", From: "HEAD"}); err == nil {
		t.Error("--worktree-from with an existing branch should be refused")
	}
}

func TestPlanCreate_Refusals(t *testing.T) {
	root, main := repo(t)
	entries, _ := List(main)
	if err := os.MkdirAll(filepath.Join(root, "proj.worktrees", "taken"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, opts := range map[string]CreateOptions{
		"folder exists": {Name: "taken"},
		"bad branch":    {Name: "no..dots"},
		"bad from":      {Name: "y", From: "no-such-ref"},
	} {
		if _, err := PlanCreate(main, entries, opts); err == nil {
			t.Errorf("%s: want an error", name)
		}
	}
}

func TestCreateAndFinish_CleanRunRemovesEverything(t *testing.T) {
	root, main := repo(t)
	p := plan(t, main, CreateOptions{Name: "feature/x"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	if e, err := Resolve(main, "feature/x"); err != nil || e.Path != p.Path {
		t.Fatalf("the new worktree is found: %+v %v", e, err)
	}

	out := Finish(main, p, FinishOptions{})
	if !out.Removed || !out.BranchDeleted {
		t.Fatalf("want worktree and branch removed: %+v", out)
	}
	if exists(filepath.Join(root, "proj.worktrees", "feature")) || !exists(filepath.Join(root, "proj.worktrees")) {
		t.Error("want the folders creation made below the root removed, and the root kept")
	}
	if _, err := git(main, "rev-parse", "--verify", "--quiet", "refs/heads/feature/x"); err == nil {
		t.Error("the branch this run created is deleted")
	}
}

func TestFinish_KeepsWhatWouldBeLost(t *testing.T) {
	cases := map[string]struct {
		exitCode int
		change   func(t *testing.T, path string)
	}{
		"failed run": {exitCode: 3, change: func(*testing.T, string) {}},
		"uncommitted": {change: func(t *testing.T, path string) {
			if err := os.WriteFile(filepath.Join(path, "new.txt"), []byte("x"), 0o644); err != nil {
				t.Fatal(err)
			}
		}},
		"other branch": {change: func(t *testing.T, path string) { run(t, path, "checkout", "-q", "-b", "elsewhere") }},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			_, main := repo(t)
			p := plan(t, main, CreateOptions{Name: "w"})
			if err := Create(main, p); err != nil {
				t.Fatal(err)
			}
			c.change(t, p.Path)
			out := Finish(main, p, FinishOptions{ExitCode: c.exitCode})
			if out.Removed || !exists(p.Path) {
				t.Fatalf("want the worktree kept: %+v", out)
			}
			if len(out.Messages) != 1 || !strings.Contains(out.Messages[0], "Kept worktree "+p.Path) {
				t.Errorf("want one 'Kept worktree' line with the path, got %q", out.Messages)
			}
		})
	}
}

func TestFinish_CommitsKeepTheBranch(t *testing.T) {
	_, main := repo(t)
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	commit(t, p.Path, "work")
	out := Finish(main, p, FinishOptions{})
	if !out.Removed || out.BranchDeleted {
		t.Fatalf("want the worktree removed and the branch with its commit kept: %+v", out)
	}
	if _, err := git(main, "rev-parse", "--verify", "--quiet", "refs/heads/w"); err != nil {
		t.Error("branch w and its commit should still exist")
	}
}

func TestFinish_ExistingBranchIsNeverDeleted(t *testing.T) {
	_, main := repo(t)
	run(t, main, "branch", "old")
	p := plan(t, main, CreateOptions{Name: "old"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	out := Finish(main, p, FinishOptions{})
	if !out.Removed || out.BranchDeleted {
		t.Fatalf("want the worktree removed, the existing branch kept: %+v", out)
	}
}

func TestFinish_IgnoredFilesDoNotBlock(t *testing.T) {
	_, main := repo(t)
	if err := os.WriteFile(filepath.Join(main, ".gitignore"), []byte("build/\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	run(t, main, "add", ".gitignore")
	commit(t, main, "ignore")
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(p.Path, "build"), 0o755); err != nil {
		t.Fatal(err)
	}
	if out := Finish(main, p, FinishOptions{}); !out.Removed {
		t.Fatalf("ignored files are not work in progress; git removes them: %+v", out)
	}
}

func TestCreate_InsideRepoWritesExcludeOnce(t *testing.T) {
	_, main := repo(t)
	for _, name := range []string{"a", "b"} {
		p := plan(t, main, CreateOptions{Name: name, Root: filepath.Join(main, "wt")})
		if err := Create(main, p); err != nil {
			t.Fatal(err)
		}
	}
	data, err := os.ReadFile(filepath.Join(main, ".git", "info", "exclude"))
	if err != nil {
		t.Fatal(err)
	}
	if n := strings.Count(string(data), "/wt/\n"); n != 1 {
		t.Errorf("want /wt/ in .git/info/exclude once, got %d:\n%s", n, data)
	}
	if status := run(t, main, "status", "--porcelain"); status != "" {
		t.Errorf("the worktree root should not show in git status, got %q", status)
	}
}

func TestBelowRoot_KeepsTheRoot(t *testing.T) {
	root := filepath.Join("/r", "proj.worktrees")
	for _, c := range []struct{ top, branch, want string }{
		{root, "feature/x", filepath.Join(root, "feature")},
		{root, "w", filepath.Join(root, "w")},
		{filepath.Join(root, "feature"), "feature/x", filepath.Join(root, "feature")},
		{"", "w", ""},
	} {
		if got := belowRoot(c.top, root, c.branch); got != c.want {
			t.Errorf("belowRoot(%q, %q): want %q, got %q", c.top, c.branch, c.want, got)
		}
	}
}

func TestRemoveEmptyUpTo_StopsAtTop(t *testing.T) {
	root := t.TempDir()
	deep := filepath.Join(root, "keep", "top", "mid")
	if err := os.MkdirAll(deep, 0o755); err != nil {
		t.Fatal(err)
	}
	removeEmptyUpTo(deep, filepath.Join(root, "keep", "top"))
	if exists(filepath.Join(root, "keep", "top")) || !exists(filepath.Join(root, "keep")) {
		t.Error("want mid and top removed, keep left")
	}
	// A dir outside top is never touched.
	other := filepath.Join(root, "other")
	if err := os.MkdirAll(other, 0o755); err != nil {
		t.Fatal(err)
	}
	removeEmptyUpTo(other, filepath.Join(root, "keep"))
	if !exists(other) {
		t.Error("a folder outside top must stay")
	}
}

func TestFinish_BoothRuntimeFilesAreNotWork(t *testing.T) {
	_, main := repo(t)
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	log := filepath.Join(p.Path, ".booth", ".tmp", "lifecycle.log")
	if err := os.MkdirAll(filepath.Dir(log), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(log, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if out := Finish(main, p, FinishOptions{}); !out.Removed {
		t.Fatalf("booth's own .booth/.tmp files should not keep the worktree: %+v", out)
	}
}

func TestFinish_RuntimeFilesBesideWorkStillKeep(t *testing.T) {
	_, main := repo(t)
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	for _, f := range []string{".booth/.tmp/lifecycle.log", "notes.txt"} {
		path := filepath.Join(p.Path, filepath.FromSlash(f))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if out := Finish(main, p, FinishOptions{}); out.Removed {
		t.Fatal("notes.txt is work: the worktree should be kept")
	}
	if !exists(filepath.Join(p.Path, ".booth", ".tmp", "lifecycle.log")) {
		t.Error("a kept worktree keeps booth's log too")
	}
}

// withOrigin gives main a bare repository as its origin and returns the bare repository's path.
func withOrigin(t *testing.T, root, main string) string {
	t.Helper()
	bare := filepath.Join(root, "origin.git")
	run(t, root, "init", "-q", "--bare", bare)
	run(t, main, "remote", "add", "origin", bare)
	return bare
}

func onRemote(t *testing.T, bare, branch string) string {
	t.Helper()
	out, err := git(bare, "rev-parse", "--verify", "--quiet", "refs/heads/"+branch)
	if err != nil {
		return ""
	}
	return out
}

func TestFinish_PushThenRemoveEverything(t *testing.T) {
	root, main := repo(t)
	bare := withOrigin(t, root, main)
	p := plan(t, main, CreateOptions{Name: "feature/x"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	commit(t, p.Path, "work")
	head := run(t, p.Path, "rev-parse", "HEAD")

	out := Finish(main, p, FinishOptions{Push: true})
	if !out.Pushed || !out.Removed || !out.BranchDeleted || out.NotPushed {
		t.Fatalf("want pushed, worktree removed, local branch deleted: %+v", out)
	}
	if got := onRemote(t, bare, "feature/x"); got != head {
		t.Errorf("origin should have feature/x at %s, got %q", head, got)
	}
}

func TestFinish_PushUsesTheUpstream(t *testing.T) {
	root, main := repo(t)
	bare := withOrigin(t, root, main)
	other := filepath.Join(root, "other.git")
	run(t, root, "init", "-q", "--bare", other)
	run(t, main, "remote", "add", "other", other)
	run(t, main, "branch", "w")
	run(t, main, "push", "-q", "-u", "other", "w:upstream-name")
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	commit(t, p.Path, "work")
	head := run(t, p.Path, "rev-parse", "HEAD")

	if out := Finish(main, p, FinishOptions{Push: true}); !out.Pushed {
		t.Fatalf("want pushed: %+v", out)
	}
	if got := onRemote(t, other, "upstream-name"); got != head {
		t.Errorf("want the push on the upstream other/upstream-name at %s, got %q", head, got)
	}
	if onRemote(t, bare, "w") != "" {
		t.Error("origin is only the fallback; the upstream is used")
	}
}

func TestFinish_PushOnExistingWorktreeKeepsIt(t *testing.T) {
	root, main := repo(t)
	bare := withOrigin(t, root, main)
	path := filepath.Join(root, "mine")
	run(t, main, "worktree", "add", "-q", path, "-b", "mine")
	commit(t, path, "work")

	out := Finish(main, Plan{Path: path, Branch: "mine"}, FinishOptions{Push: true, Existing: true})
	if !out.Pushed || out.Removed || !exists(path) {
		t.Fatalf("want pushed and the existing worktree kept: %+v", out)
	}
	if onRemote(t, bare, "mine") == "" {
		t.Error("origin should have branch mine")
	}
}

func TestFinish_NoPushWhenTheRunDidNotSucceed(t *testing.T) {
	root, main := repo(t)
	bare := withOrigin(t, root, main)
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	commit(t, p.Path, "work")
	if err := os.WriteFile(filepath.Join(p.Path, "draft.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, opts := range []FinishOptions{{Push: true, ExitCode: 2}, {Push: true}} {
		out := Finish(main, p, opts)
		if out.Pushed || !out.NotPushed || out.Removed {
			t.Fatalf("%+v: want not pushed, and kept: %+v", opts, out)
		}
		if !strings.HasPrefix(out.Messages[0], "Did not push branch w: ") {
			t.Errorf("want the reason first, got %q", out.Messages)
		}
	}
	if onRemote(t, bare, "w") != "" {
		t.Error("nothing should reach origin")
	}
}

func TestFinish_PushRejectedKeepsEverything(t *testing.T) {
	_, main := repo(t) // no origin and no upstream
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	commit(t, p.Path, "work")
	out := Finish(main, p, FinishOptions{Push: true})
	if out.Pushed || !out.NotPushed || out.Removed || !exists(p.Path) {
		t.Fatalf("want not pushed and the worktree kept: %+v", out)
	}
	if !strings.Contains(strings.Join(out.Messages, "\n"), "no remote named origin") {
		t.Errorf("want git's reason in the messages, got %q", out.Messages)
	}
}

func TestFinish_PushNothingNew(t *testing.T) {
	root, main := repo(t)
	bare := withOrigin(t, root, main)
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	out := Finish(main, p, FinishOptions{Push: true})
	if out.Pushed || out.NotPushed || !out.Removed || !out.BranchDeleted {
		t.Fatalf("no new commits: nothing to push, and all removed: %+v", out)
	}
	if onRemote(t, bare, "w") != "" {
		t.Error("an empty new branch is not pushed")
	}
}

func TestFinish_PushWithKeepWorktree(t *testing.T) {
	root, main := repo(t)
	bare := withOrigin(t, root, main)
	p := plan(t, main, CreateOptions{Name: "w"})
	if err := Create(main, p); err != nil {
		t.Fatal(err)
	}
	commit(t, p.Path, "work")
	out := Finish(main, p, FinishOptions{Push: true, KeepWorktree: true})
	if !out.Pushed || out.Removed || !exists(p.Path) || onRemote(t, bare, "w") == "" {
		t.Fatalf("want pushed and kept: %+v", out)
	}
}
