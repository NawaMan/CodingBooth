// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package showcase

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func mustRunGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v failed: %v\n%s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func newTestRepo(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	mustRunGit(t, dir, "init")
	mustRunGit(t, dir, "checkout", "-b", "main")
	mustRunGit(t, dir, "config", "user.email", "test@example.com")
	mustRunGit(t, dir, "config", "user.name", "Test")
	return dir
}

func commitFile(t *testing.T, dir, name, content string) string {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0644); err != nil {
		t.Fatalf("write file: %v", err)
	}
	mustRunGit(t, dir, "add", name)
	mustRunGit(t, dir, "commit", "-m", "commit "+name)
	return mustRunGit(t, dir, "rev-parse", "HEAD")
}

func TestCloneAtCommit_PinsExactCommit(t *testing.T) {
	src := newTestRepo(t)
	firstSHA := commitFile(t, src, "a.txt", "first")
	commitFile(t, src, "b.txt", "second") // advances main past firstSHA

	dest := filepath.Join(t.TempDir(), "clone")
	if err := CloneAtCommit(src, "main", firstSHA, dest); err != nil {
		t.Fatalf("CloneAtCommit failed: %v", err)
	}

	gotSHA := mustRunGit(t, dest, "rev-parse", "HEAD")
	if gotSHA != firstSHA {
		t.Errorf("HEAD = %s, want pinned commit %s", gotSHA, firstSHA)
	}
	if _, err := os.Stat(filepath.Join(dest, "b.txt")); err == nil {
		t.Errorf("b.txt should not exist when pinned before its commit")
	}
}

func TestCloneAtCommit_FallsBackWhenCommitOnAnotherBranch(t *testing.T) {
	src := newTestRepo(t)
	commitFile(t, src, "a.txt", "on main")

	mustRunGit(t, src, "checkout", "-b", "feature")
	featureSHA := commitFile(t, src, "feature.txt", "on feature")
	mustRunGit(t, src, "checkout", "main")

	dest := filepath.Join(t.TempDir(), "clone")
	// Ask for a commit that only exists on "feature" while pointing the
	// import at "main" (simulates the branch having moved since publish).
	if err := CloneAtCommit(src, "main", featureSHA, dest); err != nil {
		t.Fatalf("CloneAtCommit fallback failed: %v", err)
	}

	gotSHA := mustRunGit(t, dest, "rev-parse", "HEAD")
	if gotSHA != featureSHA {
		t.Errorf("HEAD = %s, want %s", gotSHA, featureSHA)
	}
}

func TestCloneAtCommit_UnknownCommitFails(t *testing.T) {
	src := newTestRepo(t)
	commitFile(t, src, "a.txt", "first")

	dest := filepath.Join(t.TempDir(), "clone")
	err := CloneAtCommit(src, "main", "0000000000000000000000000000000000000000", dest)
	if err == nil {
		t.Fatal("expected an error for an unknown commit")
	}
}
