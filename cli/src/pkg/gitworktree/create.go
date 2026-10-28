// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package gitworktree

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// CreateOptions is what `--worktree` was given for a worktree that does not exist yet.
type CreateOptions struct {
	Name string // the branch: a new one, or an existing branch no worktree has checked out
	Root string // --worktree-root; empty picks one (see chooseRoot)
	From string // --worktree-from; the new branch's start point, default HEAD
}

// Plan is a worktree to create, worked out before anything is written.
type Plan struct {
	Path      string // <root>/<branch>, nested for a branch with "/"
	Root      string
	Branch    string
	NewBranch bool   // false: an existing branch is checked out
	Base      string // the commit the worktree starts at
	// Top is the outermost folder `git worktree add` will create: Path itself, or a parent
	// that did not exist. Removal takes away the empty folders up to it, and no further.
	Top string
	// ExcludeFile and ExcludeLine keep a root inside the repository out of `git status`, in the
	// local .git/info/exclude (never a committed .gitignore). Empty when the root is outside.
	ExcludeFile string
	ExcludeLine string
}

// PlanCreate works out where and how the worktree for opts.Name is created, from dir in the
// repository whose worktrees are entries. It writes nothing.
func PlanCreate(dir string, entries []Entry, opts CreateOptions) (Plan, error) {
	if len(entries) == 0 {
		return Plan{}, fmt.Errorf("--worktree: git listed no worktrees for %s", dir)
	}
	if _, err := git(dir, "check-ref-format", "--branch", opts.Name); err != nil {
		return Plan{}, fmt.Errorf("--worktree %q is not a valid branch name", opts.Name)
	}

	main := entries[0]
	root, err := chooseRoot(dir, main, entries, opts.Root)
	if err != nil {
		return Plan{}, err
	}
	plan := Plan{
		Root:   root,
		Path:   filepath.Join(root, filepath.FromSlash(opts.Name)),
		Branch: opts.Name,
	}
	if _, err := os.Lstat(plan.Path); err == nil {
		return Plan{}, fmt.Errorf("--worktree %q: %s already exists and is not a worktree of this repository",
			opts.Name, plan.Path)
	}
	plan.Top = outermostMissing(plan.Path)

	if tip, err := git(dir, "rev-parse", "--verify", "--quiet", "refs/heads/"+opts.Name); err == nil {
		if opts.From != "" {
			return Plan{}, fmt.Errorf("--worktree-from only applies to a new branch, and branch %q exists", opts.Name)
		}
		plan.Base = tip
	} else {
		from := opts.From
		if from == "" {
			from = "HEAD"
		}
		base, err := git(dir, "rev-parse", "--verify", "--quiet", from+"^{commit}")
		if err != nil {
			return Plan{}, fmt.Errorf("--worktree-from %q is not a commit in this repository", from)
		}
		plan.NewBranch = true
		plan.Base = base
	}

	if !main.Bare {
		if rel, err := filepath.Rel(main.Path, root); err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
			common, err := git(dir, "rev-parse", "--path-format=absolute", "--git-common-dir")
			if err != nil {
				return Plan{}, err
			}
			plan.ExcludeFile = filepath.Join(common, "info", "exclude")
			plan.ExcludeLine = "/" + filepath.ToSlash(rel) + "/"
		}
	}
	return plan, nil
}

// chooseRoot is the folder new worktrees go in: the --worktree-root given; else the one the
// repository's other worktrees already share; else <project>.worktrees beside the main clone.
func chooseRoot(dir string, main Entry, entries []Entry, given string) (string, error) {
	if given != "" {
		if filepath.IsAbs(given) {
			return filepath.Clean(given), nil
		}
		return filepath.Join(dir, given), nil
	}
	if habit := sharedRoot(entries); habit != "" {
		return habit, nil
	}
	project := strings.TrimSuffix(filepath.Base(main.Path), ".git")
	return filepath.Join(filepath.Dir(main.Path), project+".worktrees"), nil
}

// sharedRoot is the folder every linked worktree lives in, when they all share one: the parent of
// each worktree's folder, or, for a nested <root>/feature/x, the folder above its branch path.
// Claude Code's own worktrees (.claude/worktrees/) are left out, being that tool's habit, not the
// user's. Empty when there are none, or they disagree.
func sharedRoot(entries []Entry) string {
	shared := ""
	for i, e := range entries {
		if i == 0 || e.Bare || e.Prunable || strings.Contains(filepath.ToSlash(e.Path), "/.claude/worktrees/") {
			continue
		}
		root := filepath.Dir(e.Path)
		if e.Branch != "" {
			if trimmed, ok := strings.CutSuffix(filepath.ToSlash(e.Path), "/"+e.Branch); ok {
				root = filepath.FromSlash(trimmed)
			}
		}
		if shared != "" && shared != root {
			return ""
		}
		shared = root
	}
	return shared
}

// outermostMissing is the outermost folder of path that does not exist yet.
func outermostMissing(path string) string {
	top := path
	for {
		parent := filepath.Dir(top)
		if parent == top {
			return top
		}
		if _, err := os.Lstat(parent); err == nil {
			return top
		}
		top = parent
	}
}

// Create makes the worktree plan describes, from dir.
func Create(dir string, plan Plan) error {
	args := []string{"worktree", "add", "--quiet", plan.Path, plan.Branch}
	if plan.NewBranch {
		args = []string{"worktree", "add", "--quiet", "-b", plan.Branch, plan.Path, plan.Base}
	}
	if _, err := git(dir, args...); err != nil {
		return err
	}
	if plan.ExcludeFile != "" {
		if err := ensureLine(plan.ExcludeFile, plan.ExcludeLine); err != nil {
			return fmt.Errorf("worktree created, but %s could not be updated: %w", plan.ExcludeFile, err)
		}
	}
	return nil
}

// ensureLine appends line to file unless a line already equals it.
func ensureLine(file, line string) error {
	data, err := os.ReadFile(file)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	for _, existing := range strings.Split(string(data), "\n") {
		if strings.TrimSpace(existing) == line {
			return nil
		}
	}
	if err := os.MkdirAll(filepath.Dir(file), 0o755); err != nil {
		return err
	}
	text := line + "\n"
	if len(data) > 0 && !strings.HasSuffix(string(data), "\n") {
		text = "\n" + text
	}
	f, err := os.OpenFile(file, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.WriteString(text)
	return err
}
