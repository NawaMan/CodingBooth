// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/nawaman/codingbooth/src/pkg/gitworktree"
)

func TestReposOf(t *testing.T) {
	root := t.TempDir()
	mk := func(parts ...string) string {
		dir := filepath.Join(append([]string{root}, parts...)...)
		if err := os.MkdirAll(dir, 0o755); err != nil {
			t.Fatal(err)
		}
		return dir
	}
	here, hereWT, sub := mk("here"), mk("here", "worktree", "fix"), mk("here", "examples", "x")
	zed, apple, plain := mk("zed"), mk("apple"), mk("plain")

	asked := []string{}
	list := func(dir string) ([]gitworktree.Entry, error) {
		asked = append(asked, dir)
		switch {
		case Within(dir, here):
			return []gitworktree.Entry{{Path: here, Branch: "main"}, {Path: hereWT, Branch: "fix"}, {Path: "/gone", Prunable: true}}, nil
		case dir == zed:
			return []gitworktree.Entry{{Path: zed, Branch: "main"}}, nil
		case dir == apple:
			return []gitworktree.Entry{{Path: apple}, {Path: filepath.Join(root, "bare"), Bare: true}}, nil
		}
		return nil, errors.New("not a git repository")
	}

	repos := reposOf([]string{here, zed, sub, hereWT, plain, apple, "", filepath.Join(root, "missing")}, list)
	want := []Repo{
		{Name: "here", Root: here, Here: true, Worktrees: []Worktree{
			{Path: here, Branch: "main", Main: true}, {Path: hereWT, Branch: "fix"}, {Path: "/gone", Prunable: true}}},
		{Name: "apple", Root: apple, Worktrees: []Worktree{{Path: apple, Main: true}}},
		{Name: "zed", Root: zed, Worktrees: []Worktree{{Path: zed, Branch: "main", Main: true}}},
	}
	if !reflect.DeepEqual(repos, want) {
		t.Fatalf("repos =\n%+v\nwant\n%+v", repos, want)
	}
	// Folders inside a repository already found are not asked about again.
	if wantAsked := []string{here, zed, plain, apple}; !reflect.DeepEqual(asked, wantAsked) {
		t.Errorf("asked git about %v, want %v", asked, wantAsked)
	}
}

func TestReposOfWithoutHereRepo(t *testing.T) {
	root := t.TempDir()
	b, a := filepath.Join(root, "b"), filepath.Join(root, "a")
	for _, d := range []string{b, a} {
		_ = os.MkdirAll(d, 0o755)
	}
	list := func(dir string) ([]gitworktree.Entry, error) {
		if dir == root {
			return nil, errors.New("no")
		}
		return []gitworktree.Entry{{Path: dir}}, nil
	}
	repos := reposOf([]string{root, b, a}, list)
	if len(repos) != 2 || repos[0].Name != "a" || repos[1].Name != "b" || repos[0].Here {
		t.Fatalf("repos = %+v, want a then b, neither here", repos)
	}
}

func TestWorktreeName(t *testing.T) {
	if got := (Worktree{Path: "/r/worktree/fix", Branch: "feature/x"}).Name(); got != "feature/x" {
		t.Errorf("Name = %q", got)
	}
	if got := (Worktree{Path: "/r/worktree/fix"}).Name(); got != "fix" {
		t.Errorf("detached Name = %q", got)
	}
}
