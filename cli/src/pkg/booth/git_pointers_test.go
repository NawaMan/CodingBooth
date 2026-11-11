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

	"github.com/nawaman/codingbooth/src/internal/hostskip"
	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

func pointerMap(plan neutralGitPlan) map[string]string {
	m := map[string]string{}
	for _, p := range plan.pointers {
		m[p.containerPath] = p.content
	}
	return m
}

func assertPointers(t *testing.T, plan neutralGitPlan, want map[string]string) {
	t.Helper()
	got := pointerMap(plan)
	for at, content := range want {
		if got[at] != content {
			t.Errorf("pointer at %s = %q, want %q", at, got[at], content)
		}
	}
	if len(got) != len(want) {
		t.Errorf("got %d pointers, want %d: %v", len(got), len(want), got)
	}
}

// No pointer, mount or env names a host path: that is the point of the layout.
func assertNoHostPath(t *testing.T, plan neutralGitPlan, root string) {
	t.Helper()
	for _, p := range plan.pointers {
		if strings.Contains(p.containerPath, root) || strings.Contains(p.content, root) {
			t.Errorf("pointer %s = %q shows the host path %s", p.containerPath, p.content, root)
		}
	}
	if plan.common != nil && strings.Contains(plan.common.containerPath, root) {
		t.Errorf("common dir mounted at host path %s", plan.common.containerPath)
	}
}

// A booth on worktree a: the main clone's .git at the neutral path, a's .git file and record
// pointing within the booth, and b mirrored under the neutral root.
func TestNeutralGit_OnWorktree(t *testing.T) {
	root, main := mainWithWorktrees(t)
	plan, ok, warning := planNeutralGit(filepath.Join(root, "a"))
	if !ok || warning != "" {
		t.Fatalf("ok=%v warning=%q, want a plan", ok, warning)
	}
	common := neutralGitRoot + "/main/.git"
	if plan.common == nil || plan.common.hostPath != filepath.Join(main, ".git") || plan.common.containerPath != common {
		t.Errorf("common = %+v, want %s at %s", plan.common, filepath.Join(main, ".git"), common)
	}
	assertPointers(t, plan, map[string]string{
		containerCodePath + "/.git":               "gitdir: " + common + "/worktrees/a\n",
		common + "/worktrees/a/gitdir":            containerCodePath + "/.git\n",
		common + "/worktrees/b/gitdir":            neutralGitRoot + "/main/worktrees/b/.git\n",
		neutralGitRoot + "/main/worktrees/b/.git": "gitdir: " + common + "/worktrees/b\n",
	})
	if !plan.hasWorktrees || !plan.tmpfs {
		t.Errorf("hasWorktrees=%v tmpfs=%v, want both", plan.hasWorktrees, plan.tmpfs)
	}
	assertNoHostPath(t, plan, root)
}

// A booth on the main clone: its .git is in the workspace already; only the records and the
// worktrees' mirrors are covered.
func TestNeutralGit_OnMainClone(t *testing.T) {
	root, main := mainWithWorktrees(t)
	plan, ok, _ := planNeutralGit(main)
	if !ok || plan.common != nil {
		t.Fatalf("ok=%v common=%+v, want a plan with no extra mount", ok, plan.common)
	}
	common := containerCodePath + "/.git"
	assertPointers(t, plan, map[string]string{
		common + "/worktrees/a/gitdir":            neutralGitRoot + "/main/worktrees/a/.git\n",
		common + "/worktrees/b/gitdir":            neutralGitRoot + "/main/worktrees/b/.git\n",
		neutralGitRoot + "/main/worktrees/a/.git": "gitdir: " + common + "/worktrees/a\n",
		neutralGitRoot + "/main/worktrees/b/.git": "gitdir: " + common + "/worktrees/b\n",
	})
	assertNoHostPath(t, plan, root)
}

// A worktree nested in the workspace (this repo's own worktree/<name>/ layout) keeps its place
// there, and its .git file is covered so that git works in it from a booth on the main clone.
func TestNeutralGit_NestedWorktree(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	main := filepath.Join(root, "main")
	gitRepo(t, main)
	runGit(t, main, "worktree", "add", "-q", filepath.Join(main, "worktree", "f"), "-b", "f")

	plan, ok, _ := planNeutralGit(main)
	if !ok {
		t.Fatal("no plan")
	}
	common := containerCodePath + "/.git"
	assertPointers(t, plan, map[string]string{
		common + "/worktrees/f/gitdir":         containerCodePath + "/worktree/f/.git\n",
		containerCodePath + "/worktree/f/.git": "gitdir: " + common + "/worktrees/f\n",
	})
	if plan.tmpfs {
		t.Error("tmpfs = true, want nothing under the neutral root")
	}
}

// With --relative-paths the host's pointers are relative; the generated ones are absolute in the
// booth all the same.
func TestNeutralGit_RelativePaths(t *testing.T) {
	root, _ := filepath.EvalSymlinks(t.TempDir())
	main := filepath.Join(root, "main")
	gitRepo(t, main)
	wt := filepath.Join(root, "wt")
	cmd := exec.Command("git", "worktree", "add", "-q", "--relative-paths", wt, "-b", "wt")
	cmd.Dir = main
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Skipf("git without --relative-paths: %s", out)
	}
	plan, ok, _ := planNeutralGit(wt)
	if !ok || plan.common == nil || plan.common.hostPath != filepath.Join(main, ".git") {
		t.Fatalf("ok=%v common=%+v", ok, plan.common)
	}
	common := neutralGitRoot + "/main/.git"
	assertPointers(t, plan, map[string]string{
		containerCodePath + "/.git":     "gitdir: " + common + "/worktrees/wt\n",
		common + "/worktrees/wt/gitdir": containerCodePath + "/.git\n",
	})
}

// A worktree deleted on the host is really stale: no pointer, so prune may drop it. A plain repo,
// no repo and a submodule need nothing; a broken gitfile warns.
func TestNeutralGit_NothingToCover(t *testing.T) {
	root, main := mainWithWorktrees(t)
	if err := os.RemoveAll(filepath.Join(root, "b")); err != nil {
		t.Fatal(err)
	}
	plan, _, _ := planNeutralGit(filepath.Join(root, "a"))
	for at := range pointerMap(plan) {
		if strings.Contains(at, "/worktrees/b") {
			t.Errorf("pointer for the deleted worktree b at %s", at)
		}
	}

	plain := filepath.Join(root, "plain")
	gitRepo(t, plain)
	if plan, ok, _ := planNeutralGit(plain); !ok || plan.hasWorktrees || len(plan.pointers) != 0 {
		t.Errorf("plain repo: ok=%v plan=%+v, want an empty plan", ok, plan)
	}
	if _, ok, warning := planNeutralGit(filepath.Join(root, "nowhere")); ok || warning != "" {
		t.Errorf("no repo: ok=%v warning=%q", ok, warning)
	}
	writeFile(t, filepath.Join(root, "super", ".git", "modules", "sub", "HEAD"), "ref: refs/heads/main\n")
	writeFile(t, filepath.Join(root, "super", "sub", ".git"), "gitdir: ../.git/modules/sub\n")
	if _, ok, warning := planNeutralGit(filepath.Join(root, "super", "sub")); ok || warning != "" {
		t.Errorf("submodule: ok=%v warning=%q", ok, warning)
	}
	writeFile(t, filepath.Join(root, "broken", ".git"), "hello\n")
	if _, ok, warning := planNeutralGit(filepath.Join(root, "broken")); ok || !strings.Contains(warning, "not a gitfile") {
		t.Errorf("broken gitfile: ok=%v warning=%q", ok, warning)
	}
	_ = main
}

func TestGitRepoName(t *testing.T) {
	for in, want := range map[string]string{
		"/x/EnvFolio/.git":  "EnvFolio",
		"/x/proj.git":       "proj",
		"/x/my repo:1/.git": "my-repo-1",
		"/x/../.git":        "repo",
		"/x/.../.git":       "repo",
	} {
		if got := gitRepoName(filepath.FromSlash(in)); got != want {
			t.Errorf("gitRepoName(%s) = %q, want %q", in, got, want)
		}
	}
}

// A `git worktree add` in a booth on worktree a writes the booth's paths; the next booth on a
// writes the host's back, and git on the host then works in the new worktree.
func TestHealBoothAddedWorktrees(t *testing.T) {
	if !hostskip.UnixPaths() {
		t.Skip("the booth's paths are Unix paths")
	}
	root, main := mainWithWorktrees(t)
	common := filepath.Join(main, ".git")
	wt := filepath.Join(root, "a")
	runGit(t, wt, "worktree", "add", "-q", filepath.Join(wt, "in", "c"), "-b", "c")
	admin := filepath.Join(common, "worktrees", "c")
	record := filepath.Join(admin, "gitdir")
	gitFile := filepath.Join(wt, "in", "c", ".git")

	// What the booth on a wrote.
	writeFile(t, record, containerCodePath+"/in/c/.git\n")
	writeFile(t, gitFile, "gitdir: "+neutralGitRoot+"/main/.git/worktrees/c\n")

	// A booth on another folder cannot tell: it leaves them.
	if healed, err := healBoothAddedWorktrees(filepath.Join(root, "b"), common); err != nil || len(healed) != 0 {
		t.Fatalf("booth on b healed %v, %v; want nothing", healed, err)
	}
	healed, err := healBoothAddedWorktrees(wt, common)
	if err != nil || len(healed) != 2 {
		t.Fatalf("healed %v, %v; want the .git file and the record", healed, err)
	}
	if data, _ := os.ReadFile(gitFile); string(data) != "gitdir: "+admin+"\n" {
		t.Errorf(".git = %q", data)
	}
	if data, _ := os.ReadFile(record); string(data) != gitFile+"\n" {
		t.Errorf("record = %q", data)
	}
	runGit(t, filepath.Join(wt, "in", "c"), "status")
	runGit(t, main, "worktree", "prune")
	if _, err := os.Stat(record); err != nil {
		t.Errorf("prune dropped the healed record: %v", err)
	}

	// Healthy records are left alone.
	if healed, _ := healBoothAddedWorktrees(wt, common); len(healed) != 0 {
		t.Errorf("healed %v from healthy records, want nothing", healed)
	}
}

// The same from a booth on the main clone, where git saw its folder at /home/coder/code/.git and
// wrote a relative path into the .git file (worktree.useRelativePaths).
func TestHealBoothAddedWorktrees_MainCloneRelative(t *testing.T) {
	if !hostskip.UnixPaths() {
		t.Skip("the booth's paths are Unix paths")
	}
	root, _ := filepath.EvalSymlinks(t.TempDir())
	main := filepath.Join(root, "main")
	gitRepo(t, main)
	runGit(t, main, "worktree", "add", "-q", filepath.Join(main, "worktree", "c"), "-b", "c")
	common := filepath.Join(main, ".git")
	admin := filepath.Join(common, "worktrees", "c")
	gitFile := filepath.Join(main, "worktree", "c", ".git")
	writeFile(t, filepath.Join(admin, "gitdir"), containerCodePath+"/worktree/c/.git\n")
	writeFile(t, gitFile, "gitdir: ../../.git/worktrees/c\n")

	// A .git file that leads to another record is not trusted.
	other := filepath.Join(main, "worktree", "d")
	runGit(t, main, "worktree", "add", "-q", other, "-b", "d")
	writeFile(t, filepath.Join(common, "worktrees", "d", "gitdir"), containerCodePath+"/worktree/d/.git\n")
	writeFile(t, filepath.Join(other, ".git"), "gitdir: ../../.git/worktrees/c\n")

	healed, err := healBoothAddedWorktrees(main, common)
	if err != nil || len(healed) != 2 || healed[0] != gitFile {
		t.Fatalf("healed %v, %v; want only c", healed, err)
	}
	runGit(t, filepath.Join(main, "worktree", "c"), "status")
	if data, _ := os.ReadFile(filepath.Join(other, ".git")); string(data) != "gitdir: ../../.git/worktrees/c\n" {
		t.Errorf("d's .git was changed: %q", data)
	}
}

// The pointer files are kept per folder, and a file whose content is unchanged keeps its inode,
// so a booth already running on it keeps seeing it.
func TestWriteGitPointers(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	dir, inBooth, err := gitPointerDir("/some/project", "")
	if err != nil || inBooth {
		t.Fatalf("dir %s inBooth=%v err=%v, want the cache", dir, inBooth, err)
	}
	if other, _, _ := gitPointerDir("/other/project", ""); other == dir {
		t.Error("two folders share a pointer dir")
	}
	pointers := []gitPointer{{"/home/coder/code/.git", "gitdir: x\n"}, {"/opt/y", "z\n"}}
	files, err := writeGitPointers(dir, pointers)
	if err != nil || len(files) != 2 || files[0] == files[1] {
		t.Fatalf("files %v, %v", files, err)
	}
	before, _ := os.Stat(files[0])
	again, _ := writeGitPointers(dir, pointers)
	after, _ := os.Stat(again[0])
	if again[0] != files[0] || !os.SameFile(before, after) {
		t.Error("rewriting unchanged content replaced the file")
	}
	if data, _ := os.ReadFile(files[1]); string(data) != "z\n" {
		t.Errorf("content = %q", data)
	}
}

// A workspace with its own .booth/ keeps the pointers there, so they go with the folder; one
// whose booth folder is elsewhere (--booth-dir), or that has none, uses the cache.
func TestGitPointerDir_InBooth(t *testing.T) {
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	code := t.TempDir()
	if _, inBooth, _ := gitPointerDir(code, ""); inBooth {
		t.Error("no .booth/: want the cache")
	}
	if err := os.Mkdir(filepath.Join(code, ".booth"), 0o755); err != nil {
		t.Fatal(err)
	}
	dir, inBooth, err := gitPointerDir(code, "")
	if want := filepath.Join(code, ".booth", ".tmp", GitPointersTmpName); err != nil || !inBooth || dir != want {
		t.Errorf("dir %s inBooth=%v err=%v, want %s", dir, inBooth, err, want)
	}
	if _, inBooth, _ := gitPointerDir(code, filepath.Join(code, ".booth")); !inBooth {
		t.Error("--booth-dir naming the workspace's own .booth/: want it")
	}
	if dir, inBooth, _ := gitPointerDir(code, t.TempDir()); inBooth || !strings.HasPrefix(dir, cache) {
		t.Errorf("another booth folder: dir %s inBooth=%v, want the cache", dir, inBooth)
	}
}

// A booth on a worktree with .booth/ mounts pointers from .booth/.tmp/git-pointers/, covers that
// folder read-only, and leaves the cache untouched.
func TestAddNeutralGitMounts_InBooth(t *testing.T) {
	if !hostskip.UnixPaths() {
		t.Skip("the neutral layout is not used on a Windows host")
	}
	cache := t.TempDir()
	t.Setenv("XDG_CACHE_HOME", cache)
	root, _ := mainWithWorktrees(t)
	code := filepath.Join(root, "a")
	if err := os.Mkdir(filepath.Join(code, ".booth"), 0o755); err != nil {
		t.Fatal(err)
	}
	builder := &appctx.AppContextBuilder{CommonArgs: ilist.NewAppendableList[ilist.List[string]]()}
	if !addNeutralGitMounts(builder, code, false) {
		t.Fatal("addNeutralGitMounts returned false")
	}
	args := builder.CommonArgs.String()
	dir := filepath.Join(code, ".booth", ".tmp", GitPointersTmpName)
	if !strings.Contains(args, dir+":"+gitPointersContainerDir+":ro") {
		t.Errorf("no read-only cover of %s in %s", dir, args)
	}
	if !strings.Contains(args, dir+"/") {
		t.Errorf("pointers not mounted from %s: %s", dir, args)
	}
	if entries, _ := os.ReadDir(filepath.Join(cache, "codingbooth", "git-pointers")); len(entries) != 0 {
		t.Errorf("cache written: %v", entries)
	}
}

// Emptying .booth/.tmp/ keeps the pointer folder: another booth on the folder mounts it.
func TestBoothTmpCleanup_KeepsGitPointers(t *testing.T) {
	code := t.TempDir()
	pointers := filepath.Join(code, ".booth", ".tmp", GitPointersTmpName)
	other := filepath.Join(code, ".booth", ".tmp", "other.txt")
	if err := os.MkdirAll(pointers, 0o755); err != nil {
		t.Fatal(err)
	}
	os.WriteFile(filepath.Join(pointers, "p"), []byte("x\n"), 0o644)
	os.WriteFile(other, []byte("x\n"), 0o644)

	PrepareBoothTmp(buildTmpCtx(code, false, false, false))
	if _, err := os.Stat(other); !os.IsNotExist(err) {
		t.Error("start did not empty .booth/.tmp/")
	}
	if _, err := os.Stat(filepath.Join(pointers, "p")); err != nil {
		t.Errorf("start removed the pointers: %v", err)
	}
	cleanupBoothTmp(buildTmpCtx(code, false, false, false))
	if _, err := os.Stat(filepath.Join(pointers, "p")); err != nil {
		t.Errorf("exit removed the pointers: %v", err)
	}
}

// A cache folder goes once the folder it names is gone; one whose folder exists, or that names
// none (written before the label), stays -- except the current folder's, which gets labelled.
func TestPruneGitPointerCache(t *testing.T) {
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	root, _ := gitPointerCacheRoot()
	alive, gone, current := t.TempDir(), filepath.Join(t.TempDir(), "gone"), t.TempDir()
	label := func(codePath string) string {
		dir, _, _ := gitPointerDir(codePath, "")
		if _, err := writeGitPointers(dir, []gitPointer{{"/x", "y\n"}}); err != nil {
			t.Fatal(err)
		}
		os.WriteFile(filepath.Join(dir, gitPointersCodePathFile), []byte(codePath+"\n"), 0o644)
		return dir
	}
	aliveDir, goneDir := label(alive), label(gone)
	legacy := filepath.Join(root, "0123456789abcdef")
	os.MkdirAll(legacy, 0o755)
	currentDir, _, _ := gitPointerDir(current, "")
	os.MkdirAll(currentDir, 0o755)

	pruneGitPointerCache(current)
	for dir, want := range map[string]bool{aliveDir: true, goneDir: false, legacy: true, currentDir: true} {
		if got := isDir(dir); got != want {
			t.Errorf("%s exists = %v, want %v", dir, got, want)
		}
	}
	if data, _ := os.ReadFile(filepath.Join(currentDir, gitPointersCodePathFile)); string(data) != current+"\n" {
		t.Errorf("current folder's label = %q", data)
	}
}
