// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"fmt"
	"os"
	"path/filepath"
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

	if out.Startup != nil {
		content := SerializeStartup(out.Startup, out.Command, out.AdjustCommand)
		if content != "" {
			paths = append(paths, filepath.Join(boothDir, "startup.sh"))
		}
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
	boothDir := filepath.Join(targetPath, ".booth")

	if err := os.MkdirAll(boothDir, 0755); err != nil {
		return fmt.Errorf("creating .booth/: %w", err)
	}

	// Ensure secrets are always gitignored
	gitignoreContent := "# Secrets - never commit\n.booth.password\n.env-local\n\n# Lock file is version-controlled\n# Binaries are in ~/.cache/codingbooth/ (not here)\n"
	if err := writeFile(filepath.Join(boothDir, ".gitignore"), gitignoreContent, 0644); err != nil {
		return fmt.Errorf("writing .gitignore: %w", err)
	}

	if out.Config != nil {
		content := SerializeConfigToml(out.Config, out.Command, out.AdjustCommand)
		if content != "" {
			if err := writeFile(filepath.Join(boothDir, "config.toml"), content, 0644); err != nil {
				return fmt.Errorf("writing config.toml: %w", err)
			}
		}
	}

	if out.Boothfile != nil {
		content := SerializeBoothfile(out.Boothfile, out.Command, out.AdjustCommand)
		if content != "" {
			if err := writeFile(filepath.Join(boothDir, "Boothfile"), content, 0644); err != nil {
				return fmt.Errorf("writing Boothfile: %w", err)
			}
		}
	}

	if out.Startup != nil {
		content := SerializeStartup(out.Startup, out.Command, out.AdjustCommand)
		if content != "" {
			if err := writeFile(filepath.Join(boothDir, "startup.sh"), content, 0755); err != nil {
				return fmt.Errorf("writing startup.sh: %w", err)
			}
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

	return nil
}

// writeFile writes content to a file with the given permissions.
func writeFile(path string, content string, perm os.FileMode) error {
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(content), perm)
}
