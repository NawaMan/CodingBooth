// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"archive/zip"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

const (
	githubRepo = "NawaMan/CodingBooth"
)

func runExample(version string) {
	if len(os.Args) < 3 {
		showExampleHelp(version)
		os.Exit(1)
		return
	}

	subcommand := os.Args[2]
	switch subcommand {
	case "list":
		listExamples(version)
	case "try":
		tryExample(version)
	case "help", "--help", "-h":
		showExampleHelp(version)
	default:
		fmt.Fprintf(os.Stderr, "Unknown example subcommand: %s\n", subcommand)
		showExampleHelp(version)
		os.Exit(1)
	}
}

func showExampleHelp(version string) {
	scriptName := "codingbooth"
	if len(os.Args) > 0 && os.Args[0] != "" {
		scriptName = filepath.Base(os.Args[0])
	}

	fmt.Printf(`%s example — manage CodingBooth examples (version %s)

USAGE:
  %s example list [--version <tag>]              List available examples
  %s example try <name> <path> [--version <tag>] Download and extract an example
  %s example help                                Show this help

OPTIONS:
  --version <tag>    Release tag (default: current binary version)

EXAMPLES:
  # List all available examples
  %s example list

  # Try the python example in a new folder
  %s example try python ./my-python-project

  # Try a specific version's example
  %s example try go ./my-go-project --version 0.16.0
`,
		scriptName,
		version,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
		scriptName,
	)
}

func listExamples(version string) {
	// Default to the binary's version
	tag := version

	// Parse --version flag
	for i := 3; i < len(os.Args); i++ {
		if os.Args[i] == "--version" && i+1 < len(os.Args) {
			tag = os.Args[i+1]
			break
		}
	}

	// Check cache first
	cacheDir, err := getCacheDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Warning: Cannot determine cache directory: %v\n", err)
	}

	cachePath := ""
	if cacheDir != "" {
		cachePath = filepath.Join(cacheDir, tag, "example-list.txt")
	}

	var content string

	// Try to read from cache
	if cachePath != "" {
		if cached, err := os.ReadFile(cachePath); err == nil {
			content = string(cached)
		}
	}

	// Fetch from GitHub if not cached
	if content == "" {
		url := fmt.Sprintf("https://github.com/%s/releases/download/%s/example-list.txt", githubRepo, tag)
		fetched, err := fetchURL(url)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error fetching example list: %v\n", err)
			fmt.Fprintf(os.Stderr, "URL: %s\n", url)
			os.Exit(1)
			return
		}
		content = fetched

		// Save to cache
		if cachePath != "" {
			cacheFileDir := filepath.Dir(cachePath)
			if err := os.MkdirAll(cacheFileDir, 0755); err == nil {
				_ = os.WriteFile(cachePath, []byte(content), 0644)
			}
		}
	}

	// Parse and display formatted output
	displayExampleList(content)
}

func displayExampleList(content string) {
	var examples []string

	lines := strings.Split(content, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if strings.HasPrefix(line, "- ") {
			name := strings.TrimPrefix(line, "- ")
			// Strip -example suffix
			name = strings.TrimSuffix(name, "-example")
			examples = append(examples, name)
		}
	}

	if len(examples) == 0 {
		fmt.Println("No examples found.")
		return
	}

	// Sort alphabetically
	sort.Strings(examples)

	// Find max width for column alignment
	maxWidth := 0
	for _, name := range examples {
		if len(name) > maxWidth {
			maxWidth = len(name)
		}
	}
	colWidth := maxWidth + 2 // Add padding

	// Print header
	fmt.Printf("Available examples (%d):\n\n", len(examples))

	// Print in 4 columns
	cols := 4
	for i, name := range examples {
		fmt.Printf("  %-*s", colWidth, name)
		if (i+1)%cols == 0 {
			fmt.Println()
		}
	}
	// Final newline if last row wasn't complete
	if len(examples)%cols != 0 {
		fmt.Println()
	}
}

func tryExample(version string) {
	// Parse arguments: booth example try <name> <path> [--version <tag>]
	if len(os.Args) < 5 {
		fmt.Fprintln(os.Stderr, "Usage: booth example try <name> <path> [--version <tag>]")
		os.Exit(1)
		return
	}

	exampleName := os.Args[3]
	targetPath := os.Args[4]
	tag := version

	// Parse --version flag
	for i := 5; i < len(os.Args); i++ {
		if os.Args[i] == "--version" && i+1 < len(os.Args) {
			tag = os.Args[i+1]
			break
		}
	}

	// Resolve paths
	targetPath, err := filepath.Abs(targetPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error resolving target path: %v\n", err)
		os.Exit(1)
		return
	}

	// Find current booth root (look for .booth folder)
	currentBoothRoot := findBoothRoot()
	if currentBoothRoot != "" {
		// Check if target is inside current booth
		if isPathInside(targetPath, currentBoothRoot) {
			fmt.Fprintf(os.Stderr, "Error: Target path must be outside the current booth folder\n")
			fmt.Fprintf(os.Stderr, "  Current booth: %s\n", currentBoothRoot)
			fmt.Fprintf(os.Stderr, "  Target path:   %s\n", targetPath)
			os.Exit(1)
			return
		}
	}

	// Check if target already exists
	if _, err := os.Stat(targetPath); err == nil {
		fmt.Fprintf(os.Stderr, "Error: Target path already exists: %s\n", targetPath)
		os.Exit(1)
		return
	}

	// Determine zip filename - "demo" is special, others have -example suffix
	zipName := exampleName + "-example"
	if exampleName == "demo" {
		zipName = "demo"
	}

	// Download the example zip
	url := fmt.Sprintf("https://github.com/%s/releases/download/%s/%s.zip", githubRepo, tag, zipName)
	fmt.Printf("Downloading %s example...\n", exampleName)

	zipPath, err := downloadToTemp(url)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error downloading example: %v\n", err)
		fmt.Fprintf(os.Stderr, "URL: %s\n", url)
		os.Exit(1)
		return
	}
	defer os.Remove(zipPath)

	// Extract the zip
	fmt.Printf("Extracting to %s...\n", targetPath)
	if err := extractZip(zipPath, targetPath, zipName); err != nil {
		fmt.Fprintf(os.Stderr, "Error extracting example: %v\n", err)
		os.Exit(1)
		return
	}

	fmt.Printf("\nExample '%s' ready at: %s\n", exampleName, targetPath)
	fmt.Println("\nTo get started:")
	fmt.Printf("  cd %s\n", targetPath)
	fmt.Println("  ./booth install")
	fmt.Println("  ./booth")
}

func findBoothRoot() string {
	cwd, err := os.Getwd()
	if err != nil {
		return ""
	}

	dir := cwd
	for {
		boothDir := filepath.Join(dir, ".booth")
		if info, err := os.Stat(boothDir); err == nil && info.IsDir() {
			return dir
		}

		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return ""
}

func isPathInside(child, parent string) bool {
	rel, err := filepath.Rel(parent, child)
	if err != nil {
		return false
	}
	return !strings.HasPrefix(rel, "..") && rel != ".."
}

func downloadToTemp(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to download: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	tmpFile, err := os.CreateTemp("", "booth-example-*.zip")
	if err != nil {
		return "", fmt.Errorf("failed to create temp file: %w", err)
	}
	defer tmpFile.Close()

	if _, err := io.Copy(tmpFile, resp.Body); err != nil {
		os.Remove(tmpFile.Name())
		return "", fmt.Errorf("failed to write temp file: %w", err)
	}

	return tmpFile.Name(), nil
}

func extractZip(zipPath, destPath, stripPrefix string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return fmt.Errorf("failed to open zip: %w", err)
	}
	defer r.Close()

	// Strip the top-level folder (e.g., "python-example/")
	prefix := stripPrefix + "/"

	for _, f := range r.File {
		// Strip the prefix directory
		name := f.Name
		if strings.HasPrefix(name, prefix) {
			name = strings.TrimPrefix(name, prefix)
		}
		if name == "" {
			continue
		}

		fpath := filepath.Join(destPath, name)

		// Security check: ensure path doesn't escape destination
		if !strings.HasPrefix(fpath, filepath.Clean(destPath)+string(os.PathSeparator)) {
			return fmt.Errorf("invalid file path: %s", f.Name)
		}

		if f.FileInfo().IsDir() {
			if err := os.MkdirAll(fpath, os.ModePerm); err != nil {
				return err
			}
			continue
		}

		// Create parent directories
		if err := os.MkdirAll(filepath.Dir(fpath), os.ModePerm); err != nil {
			return err
		}

		// Extract file
		outFile, err := os.OpenFile(fpath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			return err
		}

		rc, err := f.Open()
		if err != nil {
			outFile.Close()
			return err
		}

		_, err = io.Copy(outFile, rc)
		outFile.Close()
		rc.Close()

		if err != nil {
			return err
		}
	}

	return nil
}

func getCacheDir() (string, error) {
	// Use XDG_CACHE_HOME if set, otherwise ~/.cache
	cacheHome := os.Getenv("XDG_CACHE_HOME")
	if cacheHome == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		cacheHome = filepath.Join(home, ".cache")
	}
	return filepath.Join(cacheHome, "codingbooth", "versions"), nil
}

func fetchURL(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to fetch: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("HTTP %d: %s", resp.StatusCode, resp.Status)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response: %w", err)
	}

	return strings.TrimSuffix(string(body), "\n") + "\n", nil
}
