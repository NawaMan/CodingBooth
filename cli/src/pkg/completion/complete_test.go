// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package completion

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"

	"github.com/stretchr/testify/assert"
)

type fakeSources struct {
	booths   []string
	profiles []string
	seen     *Context // the context the last call was given
}

func (f fakeSources) Booths(ctx Context) []string {
	if f.seen != nil {
		*f.seen = ctx
	}
	return f.booths
}

func (f fakeSources) Templates(ctx Context) []TemplateInfo {
	if f.seen != nil {
		*f.seen = ctx
	}
	return []TemplateInfo{
		{Name: "go", Desc: "Go", Extensions: []string{"vscode-ext", "linter"}},
		{Name: "python", Desc: "Python", Extensions: []string{"uv"}},
		{Name: "pycharm", Desc: "PyCharm"},
	}
}

func (f fakeSources) Profiles(ctx Context) []string { return f.profiles }
func (f fakeSources) ConfigKeys() []string          { return []string{"variant", "port", "verbose"} }
func (f fakeSources) Worktrees(ctx Context) []Item {
	return []Item{{"feature/x", "worktree /r/x"}, {"fix-1", "worktree /r/fix-1"}, {"old", "branch: makes a new worktree"}}
}

func complete(words ...string) Result {
	return Complete(Spec(), words, fakeSources{booths: []string{"web", "api", "worker"}, profiles: []string{"gpu", "ci"}})
}

func itemValues(r Result) []string {
	var out []string
	for _, it := range r.Items {
		out = append(out, it.Value)
	}
	return out
}

func TestCommandsByPrefix(t *testing.T) {
	assert.Equal(t, []string{"start", "stop", "stats"}, itemValues(complete("st")))
}

func TestHiddenCommandIsNotOffered(t *testing.T) {
	assert.NotContains(t, itemValues(complete("")), "__complete")
	assert.Contains(t, itemValues(complete("")), "install", "wrapper commands are offered too")
}

func TestRootFlagsAreRunFlags(t *testing.T) {
	assert.Equal(t, []string{"--verbose", "--variant", "--version", "--vm-memory", "--vm-cpus", "--vm-shm-size"}, itemValues(complete("--v")))
}

func TestEnumValueAfterFlag(t *testing.T) {
	assert.Equal(t, []string{"docker", "podman", "apple"}, itemValues(complete("stop", "--engine", "")))
	assert.Equal(t, []string{"--engine=podman"}, itemValues(complete("stop", "--engine=p")))
}

func TestBoothNamesForNameFlagAndPositional(t *testing.T) {
	assert.Equal(t, []string{"web", "worker"}, itemValues(complete("stop", "--name", "w")))
	assert.Equal(t, []string{"api", "web", "worker"}, itemValues(complete("stop", "")))
}

func TestPositionalStopsAfterItsArgs(t *testing.T) {
	// stop takes one name; after it, the flags are what is left.
	assert.Equal(t, []string{"--engine", "--name", "--force", "--timeout"}, itemValues(complete("stop", "web", "")))
	// remove takes any number.
	assert.Equal(t, []string{"api", "web", "worker"}, itemValues(complete("remove", "web", "")))
}

func TestFlagValueIsNotCountedAsPositional(t *testing.T) {
	assert.Equal(t, []string{"api", "web", "worker"}, itemValues(complete("stop", "--timeout", "5", "")))
}

func TestSubcommands(t *testing.T) {
	assert.Equal(t, []string{"search", "show"}, itemValues(complete("template", "s")))
	assert.Equal(t, []string{"list"}, itemValues(complete("expose", "l")))
}

func TestAliasIsFollowed(t *testing.T) {
	assert.Equal(t, []string{"--json"}, itemValues(complete("expose", "ls", "--j")))
}

func TestFilesAndDirs(t *testing.T) {
	assert.Equal(t, Dirs, complete("config", "").Directive)
	assert.Equal(t, Files, complete("--boothfile", "").Directive)
	assert.Equal(t, Files, complete("--variant", "base", "--", "l").Directive, "after -- the rest goes into the booth")
}

func TestTextValueOffersNothing(t *testing.T) {
	r := complete("--image", "")
	assert.Empty(t, r.Items)
	assert.Equal(t, Words, r.Directive)
}

func TestSelectTemplatesAndExtensions(t *testing.T) {
	assert.Equal(t, []string{"python", "pycharm"}, itemValues(complete("config", "--select", "py")))
	assert.Equal(t, []string{"go+vscode-ext", "go+linter"}, itemValues(complete("config", "--select", "go+")))
	assert.Equal(t, []string{"go+linter,python+uv"}, itemValues(complete("config", "--select", "go+linter,python+")))
	assert.Equal(t, []string{"go,python"}, itemValues(complete("config", "--select", "go,pyt")))
}

func TestProfilesAsCommaList(t *testing.T) {
	assert.Equal(t, []string{"ci", "gpu"}, itemValues(complete("--profile", "")))
	assert.Equal(t, []string{"gpu,ci"}, itemValues(complete("--profile", "gpu,")))
}

func TestConfigSetOffersKeysWithoutSpace(t *testing.T) {
	r := complete("config", "--set", "v")
	assert.Equal(t, []string{"variant=", "verbose="}, itemValues(r))
	assert.True(t, r.NoSpace)
	assert.Empty(t, complete("config", "--set", "variant=").Items)
}

func TestShortAliasOnlyWhenTyped(t *testing.T) {
	assert.NotContains(t, itemValues(complete("stop", "-")), "-f")
	assert.Equal(t, []string{"-f"}, itemValues(complete("stop", "-f")))
	assert.Equal(t, []string{"-it"}, itemValues(complete("exec", "-i")), "a flag with no long name is always offered")
}

func TestHelpCompletesCommandNames(t *testing.T) {
	assert.Equal(t, []string{"express", "exec", "expose", "example"}, itemValues(complete("help", "ex")))
}

func TestContextReachesSources(t *testing.T) {
	var seen Context
	src := fakeSources{seen: &seen}
	Complete(Spec(), []string{"config", "--templates-path", "/t", "--version=1.2.3", "--select", ""}, src)
	assert.Equal(t, Context{TemplatesPath: "/t", Version: "1.2.3"}, seen)

	Complete(Spec(), []string{"stop", "--engine", "podman", ""}, src)
	assert.Equal(t, "podman", seen.Engine)
}

func TestWriteFormat(t *testing.T) {
	var out bytes.Buffer
	Write(&out, Result{Items: []Item{{"go", "Go"}, {"x", ""}}, Directive: Words, NoSpace: true})
	assert.Equal(t, "go\tGo\nx\n:words,nospace\n", out.String())
}

func TestLiveProfilesReadTheBoothDir(t *testing.T) {
	dir := t.TempDir()
	booth := filepath.Join(dir, ".booth")
	assert.NoError(t, os.MkdirAll(booth, 0o755))
	for _, name := range []string{"gpu--config.toml", ".ci--env", ".gpu--env", "config.toml"} {
		assert.NoError(t, os.WriteFile(filepath.Join(booth, name), nil, 0o644))
	}
	got := LiveSources{}.Profiles(Context{Code: dir})
	assert.ElementsMatch(t, []string{"gpu", "ci"}, got)
}

func TestWorktreeNames(t *testing.T) {
	assert.Equal(t, []string{"feature/x", "fix-1", "old"}, itemValues(complete("--worktree", "")))
	assert.Equal(t, []string{"fix-1"}, itemValues(complete("--worktree", "fi")))
	assert.Equal(t, []string{"--worktree=old"}, itemValues(complete("--worktree=o")))
}

func TestWorktreeListCommand(t *testing.T) {
	assert.Equal(t, []string{"list", "help"}, itemValues(complete("worktree", "")))
	assert.Contains(t, itemValues(complete("worktree", "list", "--")), "--json")
}

func TestLiveWorktrees(t *testing.T) {
	if _, err := exec.LookPath("git"); err != nil {
		t.Skip("git not installed")
	}
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	main := filepath.Join(root, "proj")
	gitRun := func(dir string, args ...string) {
		t.Helper()
		cmd := exec.Command("git", args...)
		cmd.Dir = dir
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("git %v: %v\n%s", args, err, out)
		}
	}
	gitRun(root, "init", "-q", "-b", "main", main)
	gitRun(main, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "init")
	gitRun(main, "worktree", "add", "-q", filepath.Join(root, "wt", "a"), "-b", "feature/a")
	gitRun(main, "branch", "spare")

	got := LiveSources{}.Worktrees(Context{Code: main})
	assert.Equal(t, []Item{
		{"feature/a", "worktree " + filepath.Join(root, "wt", "a")},
		{"spare", "branch: makes a new worktree"},
	}, got, "the main checkout's branch is left out")
}
