// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
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
	codeDir, cacheDir := newCacheRepo(t, false, "")
	// Nothing to commit to, so nothing to guard against.
	if err := validateCacheGitignore(codeDir, cacheDir); err != nil {
		t.Fatalf("expected nil for non-git project, got %v", err)
	}
}

func TestValidateCacheGitignore_Ignored(t *testing.T) {
	codeDir, cacheDir := newCacheRepo(t, true, "cache/\n")
	if err := validateCacheGitignore(codeDir, cacheDir); err != nil {
		t.Fatalf("expected nil for gitignored cache, got %v", err)
	}
}

func TestValidateCacheGitignore_NotIgnored(t *testing.T) {
	codeDir, cacheDir := newCacheRepo(t, true, "")
	err := validateCacheGitignore(codeDir, cacheDir)
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

	err := validateCacheGitignore(codeDir, cacheDir)
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
