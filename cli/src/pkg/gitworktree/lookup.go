// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

// Package gitworktree is booth's side of `--worktree <name>`: find a repository's worktree by
// name, create one, and remove it again when the booth is done. It drives the host's git; nothing
// here runs in a booth. See docs/BOOTH_WORKTREE.md.
package gitworktree

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
)

// The worktree is found in git's own list (`git worktree list`), so a worktree made by any tool,
// in any folder layout, is found with no configuration. The name matches a worktree's branch
// first, then its folder name.

// Entry is one record of `git worktree list --porcelain`.
type Entry struct {
	Path     string
	Branch   string // short name ("feature/x"), empty when detached
	Bare     bool
	Prunable bool // the folder is gone; git keeps the record until a prune
}

// NotFoundError is Find's error when no worktree has the name, the one case --worktree can create.
type NotFoundError struct{ Name string }

func (e *NotFoundError) Error() string {
	return fmt.Sprintf("no worktree has the branch or folder name %q (see `git worktree list`)", e.Name)
}

// IsNotFound reports whether err is Find's no-match error.
func IsNotFound(err error) bool {
	var notFound *NotFoundError
	return errors.As(err, &notFound)
}

// git runs git with dir as its working directory and returns stdout, trimmed. The error carries
// git's own message.
func git(dir string, args ...string) (string, error) {
	gitPath, err := exec.LookPath("git")
	if err != nil {
		return "", fmt.Errorf("--worktree needs git, and git is not installed")
	}
	cmd := exec.Command(gitPath, append([]string{"-C", dir}, args...)...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		if msg := strings.TrimSpace(stderr.String()); msg != "" {
			return "", fmt.Errorf("git %s: %s", strings.Join(args, " "), msg)
		}
		return "", fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return strings.TrimSpace(string(out)), nil
}

// List returns the worktrees of the repository holding dir, the main worktree first.
func List(dir string) ([]Entry, error) {
	if _, err := exec.LookPath("git"); err != nil {
		return nil, fmt.Errorf("--worktree needs git, and git is not installed")
	}
	out, err := exec.Command("git", "-C", dir, "worktree", "list", "--porcelain", "-z").Output()
	if err != nil {
		return nil, fmt.Errorf("--worktree needs a git repository, and %s is not in one", dir)
	}
	return parseList(string(out)), nil
}

// Resolve returns the worktree that name picks in the repository holding dir.
func Resolve(dir, name string) (Entry, error) {
	if strings.TrimSpace(name) == "" {
		return Entry{}, fmt.Errorf("--worktree needs a name: a branch or a worktree folder name")
	}
	entries, err := List(dir)
	if err != nil {
		return Entry{}, err
	}
	return Find(entries, name)
}

// parseList reads `git worktree list --porcelain -z`: NUL-terminated lines, with an empty one
// closing each record. git lists the main worktree first.
func parseList(data string) []Entry {
	var entries []Entry
	var current *Entry
	for _, line := range strings.Split(data, "\x00") {
		if line == "" {
			current = nil
			continue
		}
		key, value, _ := strings.Cut(line, " ")
		if key == "worktree" {
			entries = append(entries, Entry{Path: value})
			current = &entries[len(entries)-1]
			continue
		}
		if current == nil {
			continue
		}
		switch key {
		case "branch":
			current.Branch = strings.TrimPrefix(value, "refs/heads/")
		case "bare":
			current.Bare = true
		case "prunable":
			current.Prunable = true
		}
	}
	return entries
}

// Find picks the worktree name names: by branch, else by folder name. The main worktree is never
// picked, since booth already runs there without --worktree.
func Find(entries []Entry, name string) (Entry, error) {
	matches := matching(entries, func(e Entry) bool { return e.Branch == name })
	if len(matches) == 0 {
		matches = matching(entries, func(e Entry) bool { return filepath.Base(e.Path) == name })
	}
	switch {
	case len(matches) == 0:
		return Entry{}, &NotFoundError{Name: name}
	case len(matches) > 1:
		paths := make([]string, len(matches))
		for i, m := range matches {
			paths[i] = "  " + m.Path
		}
		return Entry{}, fmt.Errorf("--worktree %q matches more than one worktree; use --code with one of:\n%s",
			name, strings.Join(paths, "\n"))
	}
	match := matches[0]
	if len(entries) > 0 && entries[0].Path == match.Path {
		return Entry{}, fmt.Errorf("--worktree %q is the main checkout (%s); run booth there without --worktree",
			name, match.Path)
	}
	if match.Prunable {
		return Entry{}, fmt.Errorf("worktree %q is registered at %s, but that folder is gone; "+
			"`git worktree prune` drops the record", name, match.Path)
	}
	return match, nil
}

func matching(entries []Entry, matches func(Entry) bool) []Entry {
	var found []Entry
	for _, e := range entries {
		if !e.Bare && matches(e) {
			found = append(found, e)
		}
	}
	return found
}

// notInBoothName is every character a container name cannot hold.
var notInBoothName = regexp.MustCompile(`[^a-zA-Z0-9_.-]+`)

// BoothName is the booth name for a worktree: its branch with "/" (and anything else a container
// name cannot hold) turned into "-", so `--worktree feature/x` and `--worktree x` open the same
// booth, feature-x. A detached worktree is named after its folder.
func BoothName(e Entry) string {
	name := e.Branch
	if name == "" {
		name = filepath.Base(e.Path)
	}
	return strings.Trim(notInBoothName.ReplaceAllString(name, "-"), "-.")
}
