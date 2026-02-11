// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package output

import (
	"fmt"
	"os"
	"path/filepath"
)

// WriteOutput writes the complete BoothOutput to the .booth/ directory
// under the given target path. The target must not already contain a .booth/ directory.
func WriteOutput(out *BoothOutput, targetPath string) error {
	boothDir := filepath.Join(targetPath, ".booth")

	if _, err := os.Stat(boothDir); err == nil {
		return fmt.Errorf(".booth/ already exists at %s", targetPath)
	}

	if err := os.MkdirAll(boothDir, 0755); err != nil {
		return fmt.Errorf("creating .booth/: %w", err)
	}

	// Ensure .booth.password is always gitignored
	gitignoreContent := "# Secrets - never commit\n.booth.password\n\n# Lock file is version-controlled\n# Binaries are in ~/.cache/codingbooth/ (not here)\n"
	if err := writeFile(filepath.Join(boothDir, ".gitignore"), gitignoreContent, 0644); err != nil {
		return fmt.Errorf("writing .gitignore: %w", err)
	}

	if out.Config != nil {
		content := SerializeConfigToml(out.Config)
		if content != "" {
			if err := writeFile(filepath.Join(boothDir, "config.toml"), content, 0644); err != nil {
				return fmt.Errorf("writing config.toml: %w", err)
			}
		}
	}

	if out.Boothfile != nil {
		content := SerializeBoothfile(out.Boothfile)
		if content != "" {
			if err := writeFile(filepath.Join(boothDir, "Boothfile"), content, 0644); err != nil {
				return fmt.Errorf("writing Boothfile: %w", err)
			}
		}
	}

	if out.Startup != nil {
		content := SerializeStartup(out.Startup)
		if content != "" {
			if err := writeFile(filepath.Join(boothDir, "startup.sh"), content, 0755); err != nil {
				return fmt.Errorf("writing startup.sh: %w", err)
			}
		}
	}

	if len(out.Setups) > 0 {
		setupsDir := filepath.Join(boothDir, "setups")
		if err := CopyFiles(out.Setups, setupsDir); err != nil {
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
