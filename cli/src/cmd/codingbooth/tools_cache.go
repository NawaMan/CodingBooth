// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bufio"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// runToolsCache dispatches `codingbooth tools-cache <subcommand>`.
// Subcommands:
//
//	list                  show cached binary versions and sizes
//	clean                 interactive: list and prompt for one to remove
//	clean --all           remove every cached version
//	clean <version>       remove a specific version
func runToolsCache() {
	// os.Args[1] is "tools-cache"; subcommand follows.
	args := os.Args[2:]
	sub := "list"
	if len(args) > 0 {
		sub = args[0]
	}

	switch sub {
	case "list":
		toolsCacheList()
	case "clean":
		toolsCacheClean(args[1:])
	default:
		fmt.Fprintf(os.Stderr, "Unknown tools-cache subcommand: %s\n", sub)
		os.Exit(1)
	}
}

// toolsCacheRoot returns the base cache directory, respecting BOOTH_CACHE_DIR
// just like the wrapper's get_cache_dir() does.
func toolsCacheRoot() string {
	if env := os.Getenv("BOOTH_CACHE_DIR"); env != "" {
		return env
	}
	base, err := os.UserCacheDir()
	if err == nil && base != "" {
		return filepath.Join(base, "codingbooth")
	}
	home, _ := os.UserHomeDir()
	if home != "" {
		return filepath.Join(home, ".cache", "codingbooth")
	}
	return ".codingbooth-cache"
}

func toolsCacheVersionsDir() string {
	return filepath.Join(toolsCacheRoot(), "versions")
}

func toolsCacheList() {
	root := toolsCacheRoot()
	versionsDir := toolsCacheVersionsDir()

	fmt.Println()
	info, err := os.Stat(versionsDir)
	if err != nil || !info.IsDir() {
		fmt.Println("No cached versions found.")
		fmt.Println()
		fmt.Printf("Cache location: %s\n", root)
		return
	}

	entries, _ := os.ReadDir(versionsDir)
	var versions []string
	for _, e := range entries {
		if e.IsDir() {
			versions = append(versions, e.Name())
		}
	}
	sort.Strings(versions)

	if len(versions) == 0 {
		fmt.Println("No cached versions found.")
		fmt.Println()
		fmt.Printf("Cache location: %s\n", root)
		return
	}

	fmt.Println("Cached binary versions:")
	fmt.Println()

	var total int64
	for _, v := range versions {
		vdir := filepath.Join(versionsDir, v)
		size := dirBytes(vdir)
		fmt.Printf("  %-12s %10s   [%s]\n", v, formatHumanBytes(size), strings.Join(listCachePlatforms(vdir), " "))
		total += size
	}

	fmt.Println()
	fmt.Printf("Total: %s in %d version(s)\n", formatHumanBytes(total), len(versions))
	fmt.Println()
	fmt.Printf("Cache location: %s\n", root)
}

func toolsCacheClean(args []string) {
	versionsDir := toolsCacheVersionsDir()
	if info, err := os.Stat(versionsDir); err != nil || !info.IsDir() {
		fmt.Println("No cached versions to clean.")
		return
	}

	cleanAll := false
	var target string
	for _, a := range args {
		switch {
		case a == "--all":
			cleanAll = true
		case a == "--unused":
			fmt.Println("Warning: --unused not yet implemented")
		case strings.HasPrefix(a, "-"):
			fmt.Fprintf(os.Stderr, "Unknown option: %s\n", a)
			os.Exit(1)
		default:
			target = a
		}
	}

	if cleanAll {
		size := dirBytes(versionsDir)
		if err := os.RemoveAll(versionsDir); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("Removed all cached versions. Freed %s\n", formatHumanBytes(size))
		return
	}

	if target != "" {
		targetDir := filepath.Join(versionsDir, target)
		if info, err := os.Stat(targetDir); err != nil || !info.IsDir() {
			fmt.Printf("Version %s not found in cache.\n", target)
			os.Exit(1)
		}
		size := dirBytes(targetDir)
		if err := os.RemoveAll(targetDir); err != nil {
			fmt.Fprintf(os.Stderr, "Error: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("Removed version %s. Freed %s\n", target, formatHumanBytes(size))
		return
	}

	// Interactive: show the list then prompt.
	toolsCacheList()
	fmt.Println()
	fmt.Print("Enter version to remove (or 'all' or press Enter to cancel): ")

	reader := bufio.NewReader(os.Stdin)
	line, _ := reader.ReadString('\n')
	choice := strings.TrimSpace(line)

	switch choice {
	case "":
		fmt.Println("No version selected.")
	case "all":
		toolsCacheClean([]string{"--all"})
	default:
		toolsCacheClean([]string{choice})
	}
}

// listCachePlatforms returns the platform suffixes of every codingbooth-* file
// found in a version directory (e.g. ["linux-amd64", "darwin-arm64"]).
func listCachePlatforms(versionDir string) []string {
	entries, _ := os.ReadDir(versionDir)
	var platforms []string
	for _, e := range entries {
		name := e.Name()
		if !strings.HasPrefix(name, "codingbooth-") {
			continue
		}
		name = strings.TrimPrefix(name, "codingbooth-")
		name = strings.TrimSuffix(name, ".exe")
		platforms = append(platforms, name)
	}
	sort.Strings(platforms)
	return platforms
}

func dirBytes(root string) int64 {
	var total int64
	_ = filepath.WalkDir(root, func(_ string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() {
			return nil
		}
		info, ierr := d.Info()
		if ierr == nil {
			total += info.Size()
		}
		return nil
	})
	return total
}

func formatHumanBytes(n int64) string {
	const (
		kib = int64(1024)
		mib = kib * 1024
		gib = mib * 1024
	)
	switch {
	case n >= gib:
		return fmt.Sprintf("%dGiB", n/gib)
	case n >= mib:
		return fmt.Sprintf("%dMiB", n/mib)
	case n >= kib:
		return fmt.Sprintf("%dKiB", n/kib)
	default:
		return fmt.Sprintf("%dB", n)
	}
}
