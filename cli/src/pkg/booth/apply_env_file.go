// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// ApplyEnvFile applies environment file configuration and returns updated AppContext.
// When .booth/.env exists, it is always included first (must be gitignored).
// An explicit env-file (from config or CLI) is included second, so its values take
// priority over .env on conflicts.
// Note: .env in the project root is NOT auto-detected — it belongs to the application.
func ApplyEnvFile(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	// Step 1: Apply .booth/.env if it exists (always included, independent of env-file setting)
	codeDir := ctx.Code()
	if codeDir != "" {
		boothEnvFile := filepath.Join(codeDir, ".booth", ".env")
		if fileExists(boothEnvFile) {
			if err := checkBoothEnvGitignored(boothEnvFile, codeDir); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			builder.CommonArgs.Append(ilist.NewList[string]("--env-file", boothEnvFile))
			if ctx.Verbose() {
				fmt.Printf("Using booth env: %s\n", boothEnvFile)
			}
		}
	}

	// Step 2: Apply user's explicit env-file (if configured)
	containerEnvFile := ctx.EnvFile()

	// Respect the "not used" token
	if containerEnvFile != "" && containerEnvFile == "-" {
		if ctx.Verbose() {
			fmt.Println("Skipping --env-file (explicitly disabled).")
		}
		return builder.Build()
	}

	// If specified, it must exist; otherwise error out
	if containerEnvFile != "" {
		if !fileExists(containerEnvFile) {
			fmt.Fprintf(os.Stderr, "Error: env-file must be an existing file: %s\n", containerEnvFile)
			os.Exit(1)
		}

		builder.CommonArgs.Append(ilist.NewList[string]("--env-file", containerEnvFile))
		if ctx.Verbose() {
			fmt.Printf("Using env-file: %s\n", containerEnvFile)
		}
	}

	return builder.Build()
}

// checkBoothEnvGitignored verifies that .booth/.env is gitignored.
// Skips the check if git is not available or the project is not a git repo.
func checkBoothEnvGitignored(boothEnvFile, codeDir string) error {
	gitPath, err := exec.LookPath("git")
	if err != nil {
		// git not installed, skip check
		return nil
	}

	// Check if we are in a git repo
	cmd := exec.Command(gitPath, "-C", codeDir, "rev-parse", "--git-dir")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		// Not a git repo, skip check
		return nil
	}

	// git check-ignore returns exit 0 if ignored, exit 1 if NOT ignored
	cmd = exec.Command(gitPath, "-C", codeDir, "check-ignore", "-q", ".booth/.env")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		return fmt.Errorf(
			"booth env file %q is NOT gitignored. "+
				"Add '.env' to .booth/.gitignore before using this feature. "+
				"Refusing to run to prevent accidental credential exposure",
			boothEnvFile,
		)
	}

	return nil
}

// fileExists checks if a file exists.
func fileExists(path string) bool {
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	return !info.IsDir()
}
