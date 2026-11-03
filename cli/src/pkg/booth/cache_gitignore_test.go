// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// newCacheRepo builds a project with .booth/cache/home/coder/.claude/.credentials.json in it.
// boothGitignore is written to .booth/.gitignore when non-empty. gitInit controls whether the
// project is a git repo at all.
func newCacheRepo(t *testing.T, gitInit bool, boothGitignore string) (codeDir, cacheDir string) {
	t.Helper()

	codeDir = t.TempDir()
	cacheDir = filepath.Join(codeDir, ".booth", "cache")
	claudeDir := filepath.Join(cacheDir, "home", "coder", ".claude")
	if err := os.MkdirAll(claudeDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(claudeDir, ".credentials.json"), []byte(`{"token":"secret"}`), 0600); err != nil {
		t.Fatal(err)
	}
	if boothGitignore != "" {
		if err := os.WriteFile(filepath.Join(codeDir, ".booth", ".gitignore"), []byte(boothGitignore), 0644); err != nil {
			t.Fatal(err)
		}
	}

	if gitInit {
		git(t, codeDir, "init")
		git(t, codeDir, "config", "user.email", "test@example.com")
		git(t, codeDir, "config", "user.name", "Test")
	}
	return codeDir, cacheDir
}

func git(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %s: %v\n%s", strings.Join(args, " "), err, out)
	}
}

func TestValidateCacheGitignore_NotAGitRepo(t *testing.T) {
	_, cacheDir := newCacheRepo(t, false, "")
	// Nothing to commit to, so nothing to guard against.
	if err := validateCacheGitignore(cacheDir); err != nil {
		t.Fatalf("expected nil for non-git project, got %v", err)
	}
}

func TestValidateCacheGitignore_Ignored(t *testing.T) {
	_, cacheDir := newCacheRepo(t, true, "cache/\n")
	if err := validateCacheGitignore(cacheDir); err != nil {
		t.Fatalf("expected nil for gitignored cache, got %v", err)
	}
}

func TestValidateCacheGitignore_NotIgnored(t *testing.T) {
	_, cacheDir := newCacheRepo(t, true, "")
	err := validateCacheGitignore(cacheDir)
	if err == nil {
		t.Fatal("expected an error when the cache is not gitignored")
	}
	if !strings.Contains(err.Error(), "NOT gitignored") {
		t.Fatalf("expected a 'NOT gitignored' error, got %q", err)
	}
}

// The regression this guard exists for: a "cache/" rule is present and a grep-based check
// would pass, but the cache was committed before the rule existed. Gitignore does not apply
// to tracked files, so git keeps committing the credential on every commit.
func TestValidateCacheGitignore_TrackedDespiteIgnoreRule(t *testing.T) {
	codeDir, cacheDir := newCacheRepo(t, true, "cache/\n")
	git(t, codeDir, "add", "-f", ".booth/cache")
	git(t, codeDir, "commit", "-m", "oops")

	err := validateCacheGitignore(cacheDir)
	if err == nil {
		t.Fatal("expected an error when cache files are tracked, even with a 'cache/' rule present")
	}
	if !strings.Contains(err.Error(), "tracked by git") {
		t.Fatalf("expected a 'tracked by git' error, got %q", err)
	}
	// The message must point at untracking; adding a gitignore rule cannot fix this.
	if !strings.Contains(err.Error(), "git rm -r --cached") {
		t.Fatalf("expected the error to give the untrack remedy, got %q", err)
	}
}

// A --booth-dir is checked against the repo it sits in, not the project's. One inside a
// repo that does not ignore it is refused like a project .booth/cache/ would be.
func TestValidateCacheGitignore_BoothDirInOtherRepo(t *testing.T) {
	other := t.TempDir()
	git(t, other, "init")
	cacheDir := filepath.Join(other, "specs", ".booth", "cache")
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		t.Fatal(err)
	}
	err := validateCacheGitignore(cacheDir)
	if err == nil || !strings.Contains(err.Error(), "NOT gitignored") {
		t.Fatalf("expected a 'NOT gitignored' error for a booth dir inside a repo, got %v", err)
	}
	if !strings.Contains(err.Error(), "specs/.booth/cache/") {
		t.Fatalf("expected the path relative to that repo, got %q", err)
	}

	if err := os.WriteFile(filepath.Join(other, "specs", ".booth", ".gitignore"), []byte("cache/\n"), 0644); err != nil {
		t.Fatal(err)
	}
	if err := validateCacheGitignore(cacheDir); err != nil {
		t.Fatalf("expected nil once that repo ignores it, got %v", err)
	}
}

// A booth dir in no repo (express's temp spec) has nothing to be committed to.
func TestValidateCacheGitignore_BoothDirInNoRepo(t *testing.T) {
	cacheDir := filepath.Join(t.TempDir(), ".booth", "cache")
	if err := os.MkdirAll(cacheDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := validateCacheGitignore(cacheDir); err != nil {
		t.Fatalf("expected nil for a booth dir outside any repo, got %v", err)
	}
}

// A git hook runs with GIT_DIR exported, and a booth started from it inherits that. The
// check must still find the repo from the cache folder, not treat the folder as the top of
// the work tree -- which listed every tracked file as "inside the cache".
func TestValidateCacheGitignore_InheritedGitDir(t *testing.T) {
	codeDir, cacheDir := newCacheRepo(t, true, "cache/\n")
	if err := os.WriteFile(filepath.Join(codeDir, "main.go"), []byte("package main\n"), 0644); err != nil {
		t.Fatal(err)
	}
	git(t, codeDir, "add", "main.go", ".booth/.gitignore")
	git(t, codeDir, "commit", "-m", "init")

	t.Setenv("GIT_DIR", filepath.Join(codeDir, ".git"))
	if err := validateCacheGitignore(cacheDir); err != nil {
		t.Fatalf("expected nil with an inherited GIT_DIR, got %v", err)
	}
}

// Without git the check cannot run: it says so instead of passing in silence.
func TestValidateCacheGitignore_NoGitWarns(t *testing.T) {
	_, cacheDir := newCacheRepo(t, false, "")
	t.Setenv("PATH", t.TempDir())

	var err error
	stderr := captureStderr(t, func() { err = validateCacheGitignore(cacheDir) })
	if err != nil {
		t.Fatalf("expected nil without git, got %v", err)
	}
	if !strings.Contains(stderr, "git not found") {
		t.Fatalf("expected a warning without git, got %q", stderr)
	}
}

// The call site: a --booth-dir inside a repo that does not ignore its cache must stop
// the start. addCacheAndSharedMounts exits the process, so it runs in a child test
// process.
func TestAddCacheAndSharedMounts_BoothDirCacheNotIgnoredRefuses(t *testing.T) {
	if boothDir := os.Getenv("CB_TEST_BOOTH_DIR"); boothDir != "" {
		builder := &appctx.AppContextBuilder{
			CommonArgs: ilist.NewAppendableList[ilist.List[string]](),
			RunArgs:    ilist.NewAppendableList[ilist.List[string]](),
			BoothDir:   boothDir,
		}
		addCacheAndSharedMounts(builder, t.TempDir(), "docker", "")
		os.Exit(0)
	}

	repo := t.TempDir()
	git(t, repo, "init")
	boothDir := filepath.Join(repo, "spec", ".booth")
	if err := os.MkdirAll(filepath.Join(boothDir, "cache", "home", "coder", ".claude"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(boothDir, "cache", "home", "coder", ".claude", ".mount-this"), nil, 0644); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command(os.Args[0], "-test.run=^TestAddCacheAndSharedMounts_BoothDirCacheNotIgnoredRefuses$")
	cmd.Env = append(os.Environ(), "CB_TEST_BOOTH_DIR="+boothDir)
	out, err := cmd.CombinedOutput()
	if exit, ok := err.(*exec.ExitError); !ok || exit.ExitCode() != 1 {
		t.Fatalf("expected the start to stop with exit 1, got %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "NOT gitignored") {
		t.Fatalf("expected a 'NOT gitignored' error, got:\n%s", out)
	}
}

func captureStderr(t *testing.T, fn func()) string {
	t.Helper()
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	orig := os.Stderr
	os.Stderr = w
	defer func() { os.Stderr = orig }()
	fn()
	w.Close()
	out, _ := io.ReadAll(r)
	return string(out)
}
