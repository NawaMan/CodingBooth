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

// mainWithWorktrees makes a main clone with worktrees a and b beside it, all at absolute paths.
func mainWithWorktrees(t *testing.T) (root, main string) {
	t.Helper()
	root, _ = filepath.EvalSymlinks(t.TempDir())
	main = filepath.Join(root, "main")
	gitRepo(t, main)
	runGit(t, main, "worktree", "add", "-q", filepath.Join(root, "a"), "-b", "a")
	runGit(t, main, "worktree", "add", "-q", filepath.Join(root, "b"), "-b", "b")
	return root, main
}

func mirrorTargets(mirrors []gitWorktreeMount) map[string]string {
	targets := map[string]string{}
	for _, m := range mirrors {
		targets[m.hostPath] = m.containerPath
	}
	return targets
}

// Every record's .git file is mirrored at the path the record names, so none looks stale in the
// booth -- from the main clone (its .git inside the workspace) or from a worktree.
func TestWorktreeMirrors_EveryWorktree(t *testing.T) {
	if !hostskip.UnixPaths() {
		t.Skip("records hold Windows paths, which a container cannot hold")
	}
	root, main := mainWithWorktrees(t)
	common := filepath.Join(main, ".git")

	for name, containerCommon := range map[string]string{
		"from the main clone": containerCodePath + "/.git",
		"from a worktree":     common,
	} {
		t.Run(name, func(t *testing.T) {
			mirrors, has := resolveWorktreeMirrors(common, containerCommon)
			if !has {
				t.Fatal("hasWorktrees = false, want true")
			}
			targets := mirrorTargets(mirrors)
			for _, wt := range []string{"a", "b"} {
				file := filepath.Join(root, wt, ".git")
				if targets[file] != file {
					t.Errorf("%s: mirrored at %q, want the same path; all: %v", wt, targets[file], targets)
				}
			}
			if len(mirrors) != 2 {
				t.Errorf("got %d mirrors, want 2: %v", len(mirrors), targets)
			}
		})
	}
}

// A worktree deleted on the host without `git worktree remove` really is stale: not mirrored, so
// prune can still drop it. A repository with no worktrees needs nothing at all.
func TestWorktreeMirrors_StaleAndNone(t *testing.T) {
	if !hostskip.UnixPaths() {
		t.Skip("records hold Windows paths, which a container cannot hold")
	}
	root, main := mainWithWorktrees(t)
	if err := os.RemoveAll(filepath.Join(root, "b")); err != nil {
		t.Fatal(err)
	}
	mirrors, has := resolveWorktreeMirrors(filepath.Join(main, ".git"), containerCodePath+"/.git")
	if !has || len(mirrors) != 1 || mirrors[0].hostPath != filepath.Join(root, "a", ".git") {
		t.Errorf("has=%v mirrors=%v, want only a", has, mirrorTargets(mirrors))
	}

	plain := filepath.Join(root, "plain")
	gitRepo(t, plain)
	if mirrors, has := resolveWorktreeMirrors(filepath.Join(plain, ".git"), containerCodePath+"/.git"); has || len(mirrors) != 0 {
		t.Errorf("no worktrees: has=%v mirrors=%v, want nothing", has, mirrors)
	}
}

// With --relative-paths a record resolves from the git folder's place in the booth. From the main
// clone that lands in the workspace mount, which already holds the file.
func TestWorktreeMirrors_RelativeInsideWorkspace(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	main := filepath.Join(root, "main")
	gitRepo(t, main)
	cmd := exec.Command("git", "worktree", "add", "-q", "--relative-paths", filepath.Join(main, "worktree", "f"), "-b", "f")
	cmd.Dir = main
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("git without --relative-paths: %s", out)
	}
	mirrors, has := resolveWorktreeMirrors(filepath.Join(main, ".git"), containerCodePath+"/.git")
	if !has || len(mirrors) != 0 {
		t.Errorf("has=%v mirrors=%v, want the record counted and nothing mounted", has, mirrorTargets(mirrors))
	}
}

// `git worktree repair` in a booth points the record at /home/coder/code/.git; the next booth
// writes the host path back. A healthy record, a plain repo, and no repo are left alone.
func TestHealWorktreeBackLink(t *testing.T) {
	if !hostskip.UnixPaths() {
		t.Skip("the broken record is a Unix path")
	}
	root, main := mainWithWorktrees(t)
	wt := filepath.Join(root, "a")
	record := filepath.Join(main, ".git", "worktrees", "a", "gitdir")

	if got, err := healWorktreeBackLink(wt); got != "" || err != nil {
		t.Fatalf("healthy: got %q, %v; want nothing", got, err)
	}
	saved, _ := os.ReadFile(filepath.Join(main, ".git", "worktrees", "a", worktreeHostPathFile))
	if want := filepath.Join(wt, ".git") + "\n"; string(saved) != want {
		t.Errorf("%s = %q, want %q", worktreeHostPathFile, saved, want)
	}

	writeFile(t, record, containerCodePath+"/.git\n")
	got, err := healWorktreeBackLink(wt)
	if err != nil || got != record {
		t.Fatalf("broken: got %q, %v; want %s", got, err, record)
	}
	data, _ := os.ReadFile(record)
	if want := filepath.Join(wt, ".git") + "\n"; string(data) != want {
		t.Errorf("record = %q, want %q", data, want)
	}
	runGit(t, main, "worktree", "prune")
	if _, err := os.Stat(record); err != nil {
		t.Errorf("after the heal, prune still dropped the record: %v", err)
	}

	if got, _ := healWorktreeBackLink(main); got != "" {
		t.Errorf("main clone: got %q, want nothing", got)
	}
	if got, _ := healWorktreeBackLink(filepath.Join(root, "nowhere")); got != "" {
		t.Errorf("no repo: got %q, want nothing", got)
	}
}

// A booth on the main clone heals a record that a booth on the worktree broke, from the path that
// booth left beside it -- before, the main clone's booth saw a "duplicate entry" and pruned it.
func TestHealWorktreeRecords(t *testing.T) {
	if !hostskip.UnixPaths() {
		t.Skip("the broken record is a Unix path")
	}
	root, main := mainWithWorktrees(t)
	common := filepath.Join(main, ".git")
	recordA := filepath.Join(common, "worktrees", "a", "gitdir")
	recordB := filepath.Join(common, "worktrees", "b", "gitdir")
	for _, wt := range []string{"a", "b"} {
		if _, err := healWorktreeBackLink(filepath.Join(root, wt)); err != nil { // a booth on each
			t.Fatal(err)
		}
	}

	// b's saved path leads to a's .git, as if b were moved and a took its place: not trusted.
	writeFile(t, filepath.Join(common, "worktrees", "b", worktreeHostPathFile), filepath.Join(root, "a", ".git")+"\n")
	writeFile(t, recordA, boothRecordPath+"\n")
	writeFile(t, recordB, boothRecordPath+"\n")

	healed, err := healWorktreeRecords(common, boothRecordPath)
	if err != nil || len(healed) != 1 || healed[0] != recordA {
		t.Fatalf("healed %v, %v; want only %s", healed, err, recordA)
	}
	if data, _ := os.ReadFile(recordA); string(data) != filepath.Join(root, "a", ".git")+"\n" {
		t.Errorf("record a = %q", data)
	}
	if data, _ := os.ReadFile(recordB); string(data) != boothRecordPath+"\n" {
		t.Errorf("record b = %q, want it left alone", data)
	}

	// Without a saved path there is nothing to heal from.
	if err := os.Remove(filepath.Join(common, "worktrees", "b", worktreeHostPathFile)); err != nil {
		t.Fatal(err)
	}
	if healed, _ := healWorktreeRecords(common, boothRecordPath); len(healed) != 0 {
		t.Errorf("healed %v with no saved path, want nothing", healed)
	}

	// Healthy records are not touched, and the saved path survives git's own commands.
	writeFile(t, recordB, filepath.Join(root, "b", ".git")+"\n")
	if healed, _ := healWorktreeRecords(common, boothRecordPath); len(healed) != 0 {
		t.Errorf("healed %v from healthy records, want nothing", healed)
	}
	runGit(t, main, "worktree", "prune")
	runGit(t, main, "worktree", "list")
	if _, err := os.Stat(filepath.Join(common, "worktrees", "a", worktreeHostPathFile)); err != nil {
		t.Errorf("saved path gone after prune/list: %v", err)
	}
	runGit(t, main, "worktree", "remove", filepath.Join(root, "a"))
	if _, err := os.Stat(filepath.Join(common, "worktrees", "a")); !os.IsNotExist(err) {
		t.Errorf("record folder of a removed worktree still there (err=%v)", err)
	}
}
