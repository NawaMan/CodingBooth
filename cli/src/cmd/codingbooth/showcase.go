// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"text/tabwriter"

	"github.com/nawaman/codingbooth/src/pkg/showcase"
)

func runShowcase(version string) {
	if len(os.Args) < 3 {
		showShowcaseHelp(version)
		os.Exit(1)
		return
	}

	subcommand := os.Args[2]
	switch subcommand {
	case "list":
		listShowcases()
	case "show":
		showShowcaseDetail()
	case "import":
		importShowcase()
	case "help", "--help", "-h":
		showShowcaseHelp(version)
	default:
		fmt.Fprintf(os.Stderr, "Unknown showcase subcommand: %s\n", subcommand)
		showShowcaseHelp(version)
		os.Exit(1)
	}
}

func showShowcaseHelp(version string) {
	s := scriptName()
	fmt.Printf(`%s showcase — browse and import CodingBooths.online showcases (version %s)

USAGE:
  %s showcase list [<handle>] [--limit <n>] [--cursor <token>] [--json]
      List published showcases: the cross-tenant gallery, or one tenant's
      showcases when <handle> is given.

  %s showcase show <handle>/<slug> [--version <n>] [--json]
      Show one showcase's detail: title, variant, source repo, and README.

  %s showcase import <handle>/<slug> <path> [--version <n>]
      Create a new booth project at <path> from a showcase: clones its
      source repo pinned to the exact published commit and writes the
      showcase's Boothfile/config.toml into <path>/.booth/.

  %s showcase help                Show this help

OPTIONS:
  --limit <n>       Page size for 'list' (passed through to the API)
  --cursor <token>  Continuation cursor for 'list' (from a previous --json listing)
  --version <n>     Fetch a specific published history entry instead of the latest
  --json            Print the raw API response instead of a formatted view

EXAMPLES:
  %s showcase list
  %s showcase list NawaMan-GMail
  %s showcase show NawaMan-GMail/defaultj
  %s showcase import NawaMan-GMail/defaultj ./defaultj
`,
		s, version, s, s, s, s, s, s, s, s,
	)
}

// splitHandleSlug parses the "<handle>/<slug>" argument shared by
// 'show' and 'import'.
func splitHandleSlug(arg string) (handle, slug string, err error) {
	parts := strings.Split(arg, "/")
	if len(parts) != 2 || parts[0] == "" || parts[1] == "" {
		return "", "", fmt.Errorf("expected <handle>/<slug>, got %q", arg)
	}
	return parts[0], parts[1], nil
}

// parseShowcaseFlags scans args (already past the fixed positional args) for
// the flags shared across showcase subcommands.
func parseShowcaseFlags(args []string) (limit, cursor, ver string, asJSON bool) {
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--limit":
			if i+1 < len(args) {
				limit = args[i+1]
				i++
			}
		case "--cursor":
			if i+1 < len(args) {
				cursor = args[i+1]
				i++
			}
		case "--version":
			if i+1 < len(args) {
				ver = args[i+1]
				i++
			}
		case "--json":
			asJSON = true
		}
	}
	return
}

func listShowcases() {
	args := os.Args[3:]

	var handle string
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		handle = args[0]
		args = args[1:]
	}

	limit, cursor, _, asJSON := parseShowcaseFlags(args)

	if handle == "" {
		resp, err := showcase.FetchGallery(limit, cursor)
		if err != nil {
			reportShowcaseError(err)
			return
		}
		if asJSON {
			printJSON(resp)
			return
		}
		printCatalog(resp.Showcases, true)
		if resp.NextCursor != nil && *resp.NextCursor != "" {
			fmt.Printf("\nMore results: %s showcase list --cursor %s\n", scriptName(), *resp.NextCursor)
		}
		return
	}

	resp, err := showcase.FetchTenant(handle, limit, cursor)
	if err != nil {
		reportShowcaseError(err)
		return
	}
	if asJSON {
		printJSON(resp)
		return
	}
	printCatalog(resp.Showcases, false)
}

func printCatalog(entries []showcase.CatalogEntry, showHandle bool) {
	if len(entries) == 0 {
		fmt.Println("No showcases found.")
		return
	}

	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	if showHandle {
		fmt.Fprintln(w, "HANDLE\tSLUG\tTITLE\tVARIANT\tVERSION\tPUBLISHED\t")
	} else {
		fmt.Fprintln(w, "SLUG\tTITLE\tVARIANT\tVERSION\tPUBLISHED\t")
	}
	for _, e := range entries {
		featured := ""
		if e.Featured {
			featured = "*"
		}
		if showHandle {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", e.Handle, e.Slug, e.Title, e.Variant, e.Version, e.PublishedAt, featured)
		} else {
			fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n", e.Slug, e.Title, e.Variant, e.Version, e.PublishedAt, featured)
		}
	}
	w.Flush()
}

func showShowcaseDetail() {
	if len(os.Args) < 4 {
		fmt.Fprintln(os.Stderr, "Usage: booth showcase show <handle>/<slug> [--version <n>] [--json]")
		os.Exit(1)
		return
	}

	handle, slug, err := splitHandleSlug(os.Args[3])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
		return
	}

	_, _, ver, asJSON := parseShowcaseFlags(os.Args[4:])

	detail, err := showcase.FetchDetail(handle, slug, ver)
	if err != nil {
		reportShowcaseError(err)
		return
	}

	if asJSON {
		printJSON(detail)
		return
	}

	fmt.Printf("%s/%s — %s\n", handle, slug, detail.Title)
	fmt.Printf("  Booth ID:    %s\n", detail.BoothID)
	fmt.Printf("  Variant:     %s\n", detail.Variant)
	fmt.Printf("  Source:      %s (%s @ %s)\n", detail.RepoURL, detail.Branch, detail.Commit)
	fmt.Printf("  Published:   %s\n", detail.PublishedAt)
	if detail.Note != "" {
		fmt.Printf("  Note:        %s\n", detail.Note)
	}
	if detail.MdContent != "" {
		fmt.Printf("\n---\n\n%s\n", detail.MdContent)
	}
}

func importShowcase() {
	if len(os.Args) < 5 {
		fmt.Fprintln(os.Stderr, "Usage: booth showcase import <handle>/<slug> <path> [--version <n>]")
		os.Exit(1)
		return
	}

	handle, slug, err := splitHandleSlug(os.Args[3])
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
		return
	}

	targetPath := os.Args[4]
	_, _, ver, _ := parseShowcaseFlags(os.Args[5:])

	targetPath, err = filepath.Abs(targetPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving target path: %v\n", err)
		os.Exit(1)
		return
	}

	if _, err := os.Stat(targetPath); err == nil {
		fmt.Fprintf(os.Stderr, "Error: Target path already exists: %s\n", targetPath)
		os.Exit(1)
		return
	}

	fmt.Printf("Fetching showcase %s/%s...\n", handle, slug)
	detail, err := showcase.FetchDetail(handle, slug, ver)
	if err != nil {
		reportShowcaseError(err)
		return
	}

	if detail.SourceType != "git" {
		fmt.Fprintf(os.Stderr, "Error: unsupported source type %q; this version of booth only supports git-sourced showcases\n", detail.SourceType)
		os.Exit(1)
		return
	}

	fmt.Printf("Cloning %s (branch %s) pinned to %s...\n", detail.RepoURL, detail.Branch, detail.Commit)
	if err := showcase.CloneAtCommit(detail.RepoURL, detail.Branch, detail.Commit, targetPath); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
		return
	}

	if err := writeShowcaseBoothFiles(targetPath, detail); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
		return
	}

	shortCommit := detail.Commit
	if len(shortCommit) > 12 {
		shortCommit = shortCommit[:12]
	}
	fmt.Printf("\nShowcase '%s/%s' ready at: %s (pinned to %s)\n", handle, slug, targetPath, shortCommit)
	fmt.Println("\nTo get started:")
	fmt.Printf("  cd %s\n", targetPath)
	fmt.Println("  ./booth")
}

// writeShowcaseBoothFiles writes the showcase's pre-rendered Boothfile and
// config.toml into <targetPath>/.booth/, but only where the freshly cloned
// repo doesn't already have its own — a project that commits its own
// .booth/ keeps it untouched, matching how the rest of the CLI protects
// existing hand-written files.
func writeShowcaseBoothFiles(targetPath string, detail *showcase.Detail) error {
	boothDir := filepath.Join(targetPath, ".booth")
	if err := os.MkdirAll(boothDir, 0755); err != nil {
		return fmt.Errorf("failed to create %s: %w", boothDir, err)
	}

	files := []struct {
		name    string
		content string
	}{
		{"Boothfile", detail.BoothfileContent},
		{"config.toml", detail.ConfigTomlContent},
	}
	for _, f := range files {
		if f.content == "" {
			continue
		}
		path := filepath.Join(boothDir, f.name)
		if _, err := os.Stat(path); err == nil {
			fmt.Printf("Keeping existing %s from the cloned repo\n", path)
			continue
		}
		if err := os.WriteFile(path, []byte(f.content), 0644); err != nil {
			return fmt.Errorf("failed to write %s: %w", path, err)
		}
	}
	return nil
}

func reportShowcaseError(err error) {
	if apiErr, ok := err.(*showcase.APIError); ok {
		switch apiErr.Code {
		case "showcase_not_found":
			fmt.Fprintln(os.Stderr, "Error: showcase not found")
		case "version_not_found":
			fmt.Fprintln(os.Stderr, "Error: that showcase has no such version")
		default:
			fmt.Fprintf(os.Stderr, "Error: %s (HTTP %d)\n", apiErr.Error(), apiErr.StatusCode)
		}
		os.Exit(1)
		return
	}
	fmt.Fprintf(os.Stderr, "Error: %v\n", err)
	os.Exit(1)
}

func printJSON(v interface{}) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}
