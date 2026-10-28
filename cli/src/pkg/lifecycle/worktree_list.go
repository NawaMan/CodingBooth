// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"text/tabwriter"

	"github.com/nawaman/codingbooth/src/pkg/gitworktree"
)

// worktreeRow is one worktree of the repository and the booths whose code path it is.
type worktreeRow struct {
	Path     string             `json:"path"`
	Branch   string             `json:"branch"` // empty when detached
	Main     bool               `json:"main"`   // the main checkout
	Prunable bool               `json:"prunable"`
	Booths   []worktreeRowBooth `json:"booths"`
}

type worktreeRowBooth struct {
	Name  string `json:"name"`
	State string `json:"state"`
	Port  string `json:"port"`
}

// WorktreeList prints the git worktrees of the repository around the current directory, each
// with the booths that run on it: `git worktree list` joined with `booth list` by code path.
func WorktreeList(args []string, stdout io.Writer, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("worktree list", flag.ContinueOnError)
	engineChoice := engineFlag(flagSet)
	jsonOutput := flagSet.Bool("json", false, "Print a JSON array of worktrees")
	flagSet.SetOutput(stderr)
	if err := parseLifecycleFlags(flagSet, args); err != nil {
		return commandExit(2, "")
	}
	if flagSet.NArg() != 0 {
		return commandExit(2, "Error: booth worktree list takes no positional arguments.")
	}

	dir, err := os.Getwd()
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}
	entries, err := gitworktree.List(dir)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: %v", err))
	}
	containers, err := managedContainersAcross(resolveLifecycleEngines("", *engineChoice), false, stderr)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to list booths: %v", err))
	}
	rows := joinWorktreeBooths(entries, containers)

	if *jsonOutput {
		return json.NewEncoder(stdout).Encode(rows)
	}
	writer := tabwriter.NewWriter(stdout, 0, 4, 2, ' ', 0)
	_, _ = fmt.Fprintln(writer, "BRANCH\tBOOTH\tSTATUS\tPORT\tPATH")
	for _, row := range rows {
		branch := nonEmpty(row.Branch, "(detached)")
		path := row.Path
		if row.Main {
			path += "  (main checkout)"
		}
		if row.Prunable {
			path += "  (folder gone: git worktree prune)"
		}
		if len(row.Booths) == 0 {
			_, _ = fmt.Fprintf(writer, "%s\t-\t-\t-\t%s\n", branch, path)
		}
		for _, b := range row.Booths {
			status := "Stopped"
			if b.State == "running" {
				status = "Running"
			}
			_, _ = fmt.Fprintf(writer, "%s\t%s\t%s\t%s\t%s\n", branch, b.Name, status, nonEmpty(b.Port, "-"), path)
		}
	}
	return writer.Flush()
}

// joinWorktreeBooths pairs each worktree (bare entries left out) with the booths whose code path
// is that worktree's folder.
func joinWorktreeBooths(entries []gitworktree.Entry, containers []managedContainer) []worktreeRow {
	byPath := map[string][]worktreeRowBooth{}
	for _, c := range containers {
		if c.CodePath == "" {
			continue
		}
		key := samePathKey(c.CodePath)
		byPath[key] = append(byPath[key], worktreeRowBooth{Name: c.Name, State: c.State, Port: c.Port})
	}
	rows := []worktreeRow{}
	for i, e := range entries {
		if e.Bare {
			continue
		}
		rows = append(rows, worktreeRow{
			Path: e.Path, Branch: e.Branch, Main: i == 0, Prunable: e.Prunable,
			Booths: byPath[samePathKey(e.Path)],
		})
	}
	return rows
}

// samePathKey makes two spellings of one folder compare equal: cleaned, symlinks resolved when
// the folder exists.
func samePathKey(path string) string {
	if resolved, err := filepath.EvalSymlinks(path); err == nil {
		return resolved
	}
	return filepath.Clean(path)
}
