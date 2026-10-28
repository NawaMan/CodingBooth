// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package init

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// --worktree <name> picks the code path from git's own list of worktrees (`git worktree list`),
// so a worktree made by any tool, in any folder layout, is found with no configuration. The name
// matches a worktree's branch first, then its folder name. See docs/BOOTH_WORKTREE.md.

// worktreeEntry is one record of `git worktree list --porcelain`.
type worktreeEntry struct {
	path     string
	branch   string // short name ("feature/x"), empty when detached
	bare     bool
	prunable bool // the folder is gone; git keeps the record until a prune
}

// resolveWorktreeCode returns the path of the worktree that name picks in the repository holding dir.
func resolveWorktreeCode(dir, name string) (string, error) {
	if strings.TrimSpace(name) == "" {
		return "", fmt.Errorf("--worktree needs a name: a branch or a worktree folder name")
	}
	gitPath, err := exec.LookPath("git")
	if err != nil {
		return "", fmt.Errorf("--worktree needs git, and git is not installed")
	}
	cmd := exec.Command(gitPath, "-C", dir, "worktree", "list", "--porcelain", "-z")
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("--worktree needs a git repository, and %s is not in one", dir)
	}
	return matchWorktree(parseWorktreeList(string(out)), name)
}

// parseWorktreeList reads `git worktree list --porcelain -z`: NUL-terminated lines, with an empty
// one closing each record. git lists the main worktree first.
func parseWorktreeList(data string) []worktreeEntry {
	var entries []worktreeEntry
	var current *worktreeEntry
	for _, line := range strings.Split(data, "\x00") {
		if line == "" {
			current = nil
			continue
		}
		key, value, _ := strings.Cut(line, " ")
		if key == "worktree" {
			entries = append(entries, worktreeEntry{path: value})
			current = &entries[len(entries)-1]
			continue
		}
		if current == nil {
			continue
		}
		switch key {
		case "branch":
			current.branch = strings.TrimPrefix(value, "refs/heads/")
		case "bare":
			current.bare = true
		case "prunable":
			current.prunable = true
		}
	}
	return entries
}

// matchWorktree picks the worktree name names: by branch, else by folder name. The main worktree
// is never picked, since booth already runs there without --worktree.
func matchWorktree(entries []worktreeEntry, name string) (string, error) {
	matches := matchingWorktrees(entries, func(e worktreeEntry) bool { return e.branch == name })
	if len(matches) == 0 {
		matches = matchingWorktrees(entries, func(e worktreeEntry) bool {
			return filepath.Base(e.path) == name
		})
	}
	switch {
	case len(matches) == 0:
		return "", fmt.Errorf("no worktree has the branch or folder name %q (see `git worktree list`)", name)
	case len(matches) > 1:
		paths := make([]string, len(matches))
		for i, m := range matches {
			paths[i] = "  " + m.path
		}
		return "", fmt.Errorf("--worktree %q matches more than one worktree; use --code with one of:\n%s",
			name, strings.Join(paths, "\n"))
	}
	match := matches[0]
	if len(entries) > 0 && entries[0].path == match.path {
		return "", fmt.Errorf("--worktree %q is the main checkout (%s); run booth there without --worktree",
			name, match.path)
	}
	if match.prunable {
		return "", fmt.Errorf("worktree %q is registered at %s, but that folder is gone; "+
			"`git worktree prune` drops the record", name, match.path)
	}
	return match.path, nil
}

func matchingWorktrees(entries []worktreeEntry, matches func(worktreeEntry) bool) []worktreeEntry {
	var found []worktreeEntry
	for _, e := range entries {
		if !e.bare && matches(e) {
			found = append(found, e)
		}
	}
	return found
}
