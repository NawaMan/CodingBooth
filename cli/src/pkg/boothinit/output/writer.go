// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// OutputPaths returns the list of file paths that WriteOutput would create
// for the given BoothOutput and target path. This mirrors the exact logic of
// WriteOutput to determine which files would be written.
func OutputPaths(out *BoothOutput, targetPath string) []string {
	boothDir := filepath.Join(targetPath, ".booth")
	var paths []string

	// .gitignore is always written
	paths = append(paths, filepath.Join(boothDir, ".gitignore"))

	if out.Config != nil {
		content := SerializeConfigToml(out.Config, out.Command, out.AdjustCommand)
		if content != "" {
			paths = append(paths, filepath.Join(boothDir, "config.toml"))
		}
	}

	if out.Boothfile != nil {
		content := SerializeBoothfile(out.Boothfile, out.Command, out.AdjustCommand)
		if content != "" {
			paths = append(paths, filepath.Join(boothDir, "Boothfile"))
		}
	}

	for _, f := range out.Startups {
		paths = append(paths, filepath.Join(boothDir, "startups", f.RelPath))
	}

	for _, f := range out.Setups {
		paths = append(paths, filepath.Join(boothDir, "setups", f.RelPath))
	}

	for _, f := range out.Home {
		paths = append(paths, filepath.Join(boothDir, "home", f.RelPath))
	}

	for _, f := range out.HomeSeed {
		paths = append(paths, filepath.Join(boothDir, "home-seed", f.RelPath))
	}

	for _, f := range out.Cache {
		paths = append(paths, filepath.Join(boothDir, "cache", f.RelPath))
	}

	for _, d := range out.CacheDirs {
		paths = append(paths, filepath.Join(boothDir, "cache", d.RelPath, ".mount-this"))
	}

	return paths
}

// FindConflicts returns the subset of output file paths that already exist
// at the target path. Returns nil if no conflicts are found.
func FindConflicts(out *BoothOutput, targetPath string) []string {
	var conflicts []string
	for _, p := range OutputPaths(out, targetPath) {
		if _, err := os.Stat(p); err == nil {
			conflicts = append(conflicts, p)
		}
	}
	return conflicts
}

// WriteOutput writes the complete BoothOutput to the .booth/ directory
// under the given target path. If .booth/ already exists, files are overwritten.
func WriteOutput(out *BoothOutput, targetPath string) error {
	return writeOutput(out, targetPath, nil)
}

// WriteOutputBeside is WriteOutput, except that for each guarded file named in
// beside the generated content is written to "<name>.new" and the file itself is
// left exactly as the user wrote it. Nothing is destroyed and nothing is backed
// up — the user merges the two halves themselves.
//
// This is the useful answer for a hand-written booth, where "overwrite or give
// up" is a false choice: the generated content is what they wanted, they just
// need it *next to* their own work rather than on top of it. Same idea as
// pacnew/rpmnew/dpkg-dist.
//
// The rest of the output (setups/, startups/, home/, cache/) lands normally, so
// merging the .new file is all that remains to complete the reconfigure.
func WriteOutputBeside(out *BoothOutput, targetPath string, beside []string) error {
	return writeOutput(out, targetPath, beside)
}

// writeOutput writes the output, diverting any guarded file named in beside to a
// "<name>.new" sibling instead of overwriting it.
func writeOutput(out *BoothOutput, targetPath string, beside []string) error {
	boothDir := filepath.Join(targetPath, ".booth")

	if err := os.MkdirAll(boothDir, 0755); err != nil {
		return fmt.Errorf("creating .booth/: %w", err)
	}

	divert := make(map[string]bool, len(beside))
	for _, name := range beside {
		divert[name] = true
	}

	// Ensure secrets and local cache are always gitignored
	gitignoreContent := "# Secrets - never commit\n.booth.password\n.env\n\n# Local persistent state (not committed)\ncache/\n\n# Runtime temp files\n.tmp/\n\n# Transient artifacts of booth config overwriting hand-written files:\n# .bak = what was replaced, .new = generated content awaiting a manual merge\n*.bak\n*.new\n\n# Lock file and .generated are version-controlled\n# Binaries are in ~/.cache/codingbooth/ (not here)\n"
	if err := writeFile(filepath.Join(boothDir, ".gitignore"), gitignoreContent, 0644); err != nil {
		return fmt.Errorf("writing .gitignore: %w", err)
	}

	// Fingerprint what we write, so a later run can tell our own output from
	// content a human has since edited. See guard.go. A diverted file is NOT
	// recorded: what sits at the canonical path is still the user's own content,
	// and must keep reading back as hand-written until they merge.
	written := make(map[string]string, len(GuardedFiles))

	writeGuarded := func(name, content string) error {
		if content == "" {
			return nil
		}
		if divert[name] {
			return writeFile(filepath.Join(boothDir, name+".new"), content, 0644)
		}
		if err := writeFile(filepath.Join(boothDir, name), content, 0644); err != nil {
			return err
		}
		written[name] = hashContent(content)
		return nil
	}

	if out.Config != nil {
		content := SerializeConfigToml(out.Config, out.Command, out.AdjustCommand)
		if err := writeGuarded("config.toml", content); err != nil {
			return fmt.Errorf("writing config.toml: %w", err)
		}
	}

	if out.Boothfile != nil {
		content := SerializeBoothfile(out.Boothfile, out.Command, out.AdjustCommand)
		if err := writeGuarded("Boothfile", content); err != nil {
			return fmt.Errorf("writing Boothfile: %w", err)
		}
	}

	if err := writeManifest(boothDir, written); err != nil {
		return fmt.Errorf("writing %s: %w", ManifestName, err)
	}

	// Always clean up stale generated startup files (from previous selections)
	startupsDir := filepath.Join(boothDir, "startups")
	if err := cleanupGeneratedFiles(startupsDir); err != nil {
		return fmt.Errorf("cleaning startups/: %w", err)
	}
	if len(out.Startups) > 0 {
		if err := writeStartupFiles(out.Startups, startupsDir, out.Command, out.AdjustCommand); err != nil {
			return fmt.Errorf("writing startups/: %w", err)
		}
	}

	if len(out.Setups) > 0 {
		setupsDir := filepath.Join(boothDir, "setups")
		if err := CopyFilesExecutable(out.Setups, setupsDir); err != nil {
			return fmt.Errorf("writing setups/: %w", err)
		}
	}

	if len(out.Home) > 0 {
		homeDir := filepath.Join(boothDir, "home")
		if err := CopyFiles(out.Home, homeDir); err != nil {
			return fmt.Errorf("writing home/: %w", err)
		}
	}

	if len(out.HomeSeed) > 0 {
		homeSeedDir := filepath.Join(boothDir, "home-seed")
		if err := CopyFiles(out.HomeSeed, homeSeedDir); err != nil {
			return fmt.Errorf("writing home-seed/: %w", err)
		}
	}

	// Touch cache files (no-clobber: skip if file already exists)
	if len(out.Cache) > 0 {
		cacheDir := filepath.Join(boothDir, "cache")
		if err := touchCacheFiles(out.Cache, cacheDir); err != nil {
			return fmt.Errorf("writing cache/: %w", err)
		}
	}

	// Create cache directories with .mount-this markers (no-clobber)
	if len(out.CacheDirs) > 0 {
		cacheDir := filepath.Join(boothDir, "cache")
		if err := touchCacheDirs(out.CacheDirs, cacheDir); err != nil {
			return fmt.Errorf("writing cache dirs/: %w", err)
		}
	}

	return nil
}

// writeFile writes content to a file with the given permissions.
func writeFile(path string, content string, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(content), perm)
}

// writeStartupFiles writes individual startup scripts to the startups/ directory.
// Each file is serialized with a shebang header and marked as generated.
func writeStartupFiles(files []FileContent, dir, command, adjustCommand string) error {
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	for _, f := range files {
		content := SerializeStartupFile(f.Content, command, adjustCommand)
		path := filepath.Join(dir, f.RelPath)
		if err := os.WriteFile(path, []byte(content), 0755); err != nil {
			return err
		}
	}
	return nil
}

// cleanupGeneratedFiles removes files in dir that have a "# Generated by" header.
// User-added files (without the header) are preserved.
func cleanupGeneratedFiles(dir string) error {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		path := filepath.Join(dir, entry.Name())
		if isGeneratedFile(path) {
			if err := os.Remove(path); err != nil {
				return err
			}
		}
	}
	return nil
}

// touchCacheFiles creates empty files in the cache directory (no-clobber).
// If a file already exists, it is left untouched to preserve user data.
func touchCacheFiles(files []FileContent, cacheDir string) error {
	for _, f := range files {
		path := filepath.Join(cacheDir, f.RelPath)
		if _, err := os.Stat(path); err == nil {
			continue // already exists — no-clobber
		}
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			return err
		}
		if err := os.WriteFile(path, []byte{}, 0644); err != nil {
			return err
		}
	}
	return nil
}

// touchCacheDirs creates directories with .mount-this markers in the cache directory (no-clobber).
// If the .mount-this marker already exists, the directory is left untouched.
func touchCacheDirs(dirs []FileContent, cacheDir string) error {
	for _, d := range dirs {
		dirPath := filepath.Join(cacheDir, d.RelPath)
		if err := os.MkdirAll(dirPath, 0755); err != nil {
			return err
		}
		markerPath := filepath.Join(dirPath, ".mount-this")
		if _, err := os.Stat(markerPath); err == nil {
			continue // already exists — no-clobber
		}
		if err := os.WriteFile(markerPath, []byte{}, 0644); err != nil {
			return err
		}
	}
	return nil
}

// isGeneratedFile checks if a file contains a "# Generated by" or "# Configured by" line
// within the first few lines (header area).
func isGeneratedFile(path string) bool {
	f, err := os.Open(path)
	if err != nil {
		return false
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for i := 0; i < 5 && scanner.Scan(); i++ {
		line := scanner.Text()
		if strings.HasPrefix(line, "# Generated by:") || strings.HasPrefix(line, "# Configured by:") {
			return true
		}
	}
	return false
}
