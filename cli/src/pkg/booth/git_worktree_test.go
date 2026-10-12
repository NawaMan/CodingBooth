// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/nawaman/codingbooth/src/internal/hostskip"
)

// gitRepo makes a repo with one commit at dir. It skips the test when git is not installed.
func gitRepo(t *testing.T, dir string) {
	t.Helper()
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	runGit(t, "", "init", "-q", dir)
	runGit(t, dir, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init")
}

func runGit(t *testing.T, dir string, args ...string) {
	t.Helper()
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("git %v: %v\n%s", args, err, out)
	}
}

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// declinedOffUnix handles the hosts this feature cannot serve. The booth
// mirrors the main repository's .git at the host's own absolute path, which
// only works where that path is also a path a container can hold: a Windows
// gitdir ("C:/proj/.git") is not, so resolveGitWorktreeMount declines it and
// says why, rather than building a mount that cannot work (see
// git_worktree.go). That refusal is what there is to assert there.
func declinedOffUnix(t *testing.T, ok bool, warning string) bool {
	t.Helper()
	if hostskip.UnixPaths() {
		return false
	}
	if ok || warning == "" {
		t.Fatalf("ok=%v warning=%q, want the mount declined with a reason on %s",
			ok, warning, runtime.GOOS)
	}
	return true
}

func TestGitWorktreeMount_AbsoluteWorktree(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	main := filepath.Join(root, "main")
	gitRepo(t, main)
	wt := filepath.Join(root, "wt")
	runGit(t, main, "worktree", "add", "-q", wt, "-b", "wt")

	mount, ok, warning := resolveGitWorktreeMount(wt)
	if declinedOffUnix(t, ok, warning) {
		return
	}
	if !ok || warning != "" {
		t.Fatalf("ok=%v warning=%q, want a mount", ok, warning)
	}
	want := filepath.Join(main, ".git")
	if mount.hostPath != want || mount.containerPath != filepath.ToSlash(want) {
		t.Errorf("mount = %+v, want %s at the same path", mount, want)
	}
}

// git worktree add --relative-paths (git 2.48+) writes a relative gitdir, which resolves from
// /home/coder/code in the booth rather than from the host folder.
func TestGitWorktreeMount_RelativeWorktree(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	main := filepath.Join(root, "main")
	gitRepo(t, main)
	wt := filepath.Join(main, "worktree", "feature")
	cmd := exec.Command("git", "worktree", "add", "-q", "--relative-paths", wt, "-b", "feature")
	cmd.Dir = main
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("git without --relative-paths: %s", out)
	}

	mount, ok, warning := resolveGitWorktreeMount(wt)
	if declinedOffUnix(t, ok, warning) {
		return
	}
	if !ok || warning != "" {
		t.Fatalf("ok=%v warning=%q, want a mount", ok, warning)
	}
	// /home/coder/code/../../.git
	if mount.hostPath != filepath.Join(main, ".git") || mount.containerPath != "/home/.git" {
		t.Errorf("mount = %+v, want %s at /home/.git", mount, filepath.Join(main, ".git"))
	}
}

func TestGitWorktreeMount_NothingToDo(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())

	plain := filepath.Join(root, "plain")
	gitRepo(t, plain)
	if _, ok, warning := resolveGitWorktreeMount(plain); ok || warning != "" {
		t.Errorf("normal repo: ok=%v warning=%q, want nothing", ok, warning)
	}

	noRepo := filepath.Join(root, "norepo")
	if err := os.MkdirAll(noRepo, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, ok, warning := resolveGitWorktreeMount(noRepo); ok || warning != "" {
		t.Errorf("no repo: ok=%v warning=%q, want nothing", ok, warning)
	}

	// A submodule's git folder has no commondir: out of scope, and no warning.
	writeFile(t, filepath.Join(root, "super", ".git", "modules", "sub", "HEAD"), "ref: refs/heads/main\n")
	writeFile(t, filepath.Join(root, "super", "sub", ".git"), "gitdir: ../.git/modules/sub\n")
	if _, ok, warning := resolveGitWorktreeMount(filepath.Join(root, "super", "sub")); ok || warning != "" {
		t.Errorf("submodule: ok=%v warning=%q, want nothing", ok, warning)
	}

	// A common dir inside the workspace is already mounted.
	inner := filepath.Join(root, "inner")
	writeFile(t, filepath.Join(inner, ".git"), "gitdir: repo/worktrees/x\n")
	writeFile(t, filepath.Join(inner, "repo", "worktrees", "x", "commondir"), "../..\n")
	if _, ok, warning := resolveGitWorktreeMount(inner); ok || warning != "" {
		t.Errorf("common dir in the workspace: ok=%v warning=%q, want nothing", ok, warning)
	}
}

func TestGitWorktreeMount_Broken(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	cases := map[string]struct {
		gitfile string
		setup   func(dir string)
		warns   string
	}{
		"not a gitfile": {gitfile: "hello\n", warns: "not a gitfile"},
		"main repo gone": {
			gitfile: "gitdir: " + filepath.Join(root, "gone", ".git", "worktrees", "x") + "\n",
			setup: func(string) {
				writeFile(t, filepath.Join(root, "gone", ".git", "worktrees", "x", "commondir"), "../../../missing\n")
			},
			warns: "does not exist",
		},
		"gitdir outside the common dir": {
			gitfile: "gitdir: " + filepath.Join(root, "odd", "gitdir") + "\n",
			setup: func(string) {
				writeFile(t, filepath.Join(root, "odd", "gitdir", "commondir"), "../common\n")
				writeFile(t, filepath.Join(root, "odd", "common", "HEAD"), "x\n")
			},
			warns: "is not inside",
		},
		"resolves above the workspace": {
			// /home/coder/code/../above/x/../.. is /home/coder
			gitfile: "gitdir: ../above/x\n",
			setup: func(string) {
				writeFile(t, filepath.Join(root, "above", "x", "commondir"), "../..\n")
			},
			warns: "cover the workspace",
		},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			dir := filepath.Join(root, strings.ReplaceAll(name, " ", "-"))
			writeFile(t, filepath.Join(dir, ".git"), c.gitfile)
			if c.setup != nil {
				c.setup(dir)
			}
			_, ok, warning := resolveGitWorktreeMount(dir)
			if ok || !strings.Contains(warning, c.warns) {
				t.Errorf("ok=%v warning=%q, want a warning containing %q", ok, warning, c.warns)
			}
		})
	}
}

func TestUnusableGitMountTarget(t *testing.T) {
	for target, usable := range map[string]bool{
		"/home/nawa/dev/repo/.git": true,
		"/home/.git":               true,
		"/tmp/x/.git":              true,
		"/":                        false,
		"/home/coder":              false,
		"/etc/repo/.git":           false,
		"/proc/1":                  false,
	} {
		if got := unusableGitMountTarget(target) == ""; got != usable {
			t.Errorf("%s: usable=%v, want %v", target, got, usable)
		}
	}
}
