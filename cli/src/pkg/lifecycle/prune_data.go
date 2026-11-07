// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/pathmount"
)

// pruneDataKind maps `booth prune <word>` to the tree it prunes: "cache" or "shared" ("share"
// too, the word people say). Any other word is not a data prune.
func pruneDataKind(word string) (string, bool) {
	switch word {
	case "cache":
		return "cache", true
	case "shared", "share":
		return "shared", true
	}
	return "", false
}

// pruneData is `booth prune cache|shared`: delete what the project's .booth/<kind>/ holds that
// config.toml does not declare -- the leftovers of a deselected template, which booth no longer
// mounts. It lists them first and asks, unless yes. It refuses while a booth runs on this
// .booth/, so nothing is deleted from under a running container. .booth/cache/ is not in git, so
// a delete there is final; .booth/shared/ is, so one there shows in git status.
func pruneData(kind, codeDir string, yes bool, containers []managedContainer, queryErr error,
	stdin io.Reader, stdout, stderr io.Writer) error {
	code := normalizeCodePath(codeDir)
	boothDir := filepath.Join(code, ".booth")
	if info, err := os.Stat(boothDir); err != nil || !info.IsDir() {
		return commandExit(1, fmt.Sprintf("Error: %s has no .booth folder; run it in a project, or give --code <path>", code))
	}

	if queryErr != nil {
		_, _ = fmt.Fprintf(stderr, "Warning: could not check for a running booth on this project (%v).\n", queryErr)
	}
	if running := runningOn(boothDir, code, containers); len(running) > 0 {
		return commandExit(1, fmt.Sprintf("Error: booth %s is running on this project; stop it first (booth stop --name %s)",
			strings.Join(running, ", "), running[0]))
	}

	treeDir := filepath.Join(boothDir, kind)
	left := pathmount.Leftovers(boothDir, kind)
	if len(left) == 0 {
		_, _ = fmt.Fprintf(stdout, "Nothing to prune: everything in .booth/%s/ is declared in config.toml.\n", kind)
		return nil
	}

	_, _ = fmt.Fprintf(stdout, "Not declared in config.toml (not mounted), in %s:\n", code)
	for _, e := range left {
		_, _ = fmt.Fprintf(stdout, "  %-60s %s\n", pathmount.Display(kind, e), humanSize(treeSize(filepath.Join(treeDir, filepath.FromSlash(e.Rel)))))
	}
	if kind == "cache" {
		_, _ = fmt.Fprintln(stdout, ".booth/cache/ is not in git: what is deleted is gone (keys, stores and databases too).")
	} else {
		_, _ = fmt.Fprintln(stdout, ".booth/shared/ is in git: the deletion shows in git status, to commit or restore.")
	}
	if !yes {
		_, _ = fmt.Fprintf(stdout, "Delete these %d item(s)? [y/N]: ", len(left))
		confirmed, err := readConfirmation(stdin)
		if err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to read confirmation: %v", err))
		}
		if !confirmed {
			_, _ = fmt.Fprintln(stdout, "Prune cancelled.")
			return nil
		}
	}

	removed := 0
	for _, e := range left {
		target := filepath.Join(treeDir, filepath.FromSlash(e.Rel))
		if err := os.RemoveAll(target); err != nil {
			return commandExit(1, fmt.Sprintf("Error: failed to delete %s: %v", pathmount.Display(kind, e), err))
		}
		removeEmptyParents(filepath.Dir(target), treeDir)
		removed++
	}
	_, _ = fmt.Fprintf(stdout, "Deleted %d item(s) from .booth/%s/.\n", removed, kind)
	return nil
}

// runningOn names the running booths whose .booth folder is boothDir.
func runningOn(boothDir, code string, containers []managedContainer) []string {
	var names []string
	for _, c := range containers {
		if c.State != "running" {
			continue
		}
		dir := c.BoothDir
		if dir == "" && c.CodePath != "" {
			dir = filepath.Join(c.CodePath, ".booth")
		}
		if dir != "" && samePathKey(dir) == samePathKey(boothDir) {
			names = append(names, c.Name)
		}
	}
	return names
}

// removeEmptyParents removes dir and the folders above it while they are empty, stopping at
// stop (the tree root, which stays).
func removeEmptyParents(dir, stop string) {
	stop = filepath.Clean(stop)
	for dir = filepath.Clean(dir); dir != stop && strings.HasPrefix(dir, stop+string(filepath.Separator)); dir = filepath.Dir(dir) {
		if os.Remove(dir) != nil { // fails on a folder that is not empty
			return
		}
	}
}

// treeSize is the total size of the files at or under p.
func treeSize(p string) int64 {
	var total int64
	_ = filepath.WalkDir(p, func(_ string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if info, infoErr := d.Info(); infoErr == nil {
				total += info.Size()
			}
		}
		return nil
	})
	return total
}
