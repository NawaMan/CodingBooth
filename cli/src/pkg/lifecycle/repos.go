// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/gitworktree"
)

// Worktree is one checkout of a repository, as `booth worktree list` shows it.
type Worktree struct {
	Path     string
	Branch   string // "" when detached
	Main     bool   // the main checkout, which `booth worktree remove` never removes
	Prunable bool   // the folder is gone; git keeps the record until a prune
}

// Name is what `booth --worktree` and `booth worktree remove` take for it:
// its branch, else its folder name.
func (w Worktree) Name() string {
	if w.Branch != "" {
		return w.Branch
	}
	return filepath.Base(w.Path)
}

// Repo is a git repository and its worktrees, the main checkout first.
type Repo struct {
	Name      string // the main checkout's folder name
	Root      string // the main checkout
	Here      bool   // holds the folder booth dashboard runs in
	Worktrees []Worktree
}

// Repos finds the repositories booth dashboard groups booths under: the one holding
// cwd, then those holding a booth's code path, by name. A folder in no
// repository (or no git on the host) adds none.
func Repos(booths []Booth, cwd string) []Repo {
	dirs := []string{cwd}
	for _, b := range booths {
		dirs = append(dirs, b.CodePath)
	}
	return reposOf(dirs, gitworktree.List)
}

func reposOf(dirs []string, list func(dir string) ([]gitworktree.Entry, error)) []Repo {
	var repos []Repo
	seen := map[string]bool{}
	for i, dir := range dirs {
		if dir == "" || covered(repos, dir) {
			continue
		}
		if info, err := os.Stat(dir); err != nil || !info.IsDir() {
			continue
		}
		entries, err := list(dir)
		if err != nil || len(entries) == 0 || seen[entries[0].Path] {
			continue
		}
		seen[entries[0].Path] = true
		repo := Repo{Name: filepath.Base(entries[0].Path), Root: entries[0].Path}
		for j, e := range entries {
			if e.Bare {
				continue
			}
			repo.Worktrees = append(repo.Worktrees, Worktree{Path: e.Path, Branch: e.Branch, Main: j == 0, Prunable: e.Prunable})
		}
		repo.Here = i == 0
		repos = append(repos, repo)
	}
	// The cwd's repository first, the others by name.
	rest := repos
	if len(rest) > 0 && rest[0].Here {
		rest = rest[1:]
	}
	sort.SliceStable(rest, func(i, j int) bool { return rest[i].Name < rest[j].Name })
	return repos
}

// covered: dir is in a worktree of a repository already found, so asking git
// again would only find it again.
func covered(repos []Repo, dir string) bool {
	for _, repo := range repos {
		for _, w := range repo.Worktrees {
			if Within(dir, w.Path) {
				return true
			}
		}
	}
	return false
}

// Within reports whether path is dir or inside it.
func Within(path, dir string) bool {
	path, dir = filepath.Clean(path), filepath.Clean(dir)
	return path == dir || strings.HasPrefix(path, dir+string(filepath.Separator))
}

// GitState is a worktree's git status (see gitworktree.State).
type GitState = gitworktree.State

// GitStatus reads w's git status for booth dashboard. A worktree counts ahead/behind against the
// main checkout's branch; the main checkout against its upstream (unpushed and unpulled commits),
// and only "dirty" when it has none. The main checkout is never "merged".
func GitStatus(repo Repo, w Worktree) (GitState, error) {
	base := ""
	switch {
	case w.Main:
		if w.Branch != "" {
			base = gitworktree.Upstream(w.Path, w.Branch)
		}
	case len(repo.Worktrees) > 0 && repo.Worktrees[0].Main:
		base = repo.Worktrees[0].Branch
	}
	state, err := gitworktree.Status(w.Path, w.Branch, base)
	if w.Main {
		state.Merged = false
	}
	return state, err
}
