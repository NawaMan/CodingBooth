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
// When .booth/.env-local exists, it is always included first (must be gitignored).
// The user's env-file (explicit or auto-detected .env) is included second, so its
// values take priority over .env-local on conflicts.
func ApplyEnvFile(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()

	// Step 1: Apply .booth/.env-local if it exists (always included, independent of env-file setting)
	codeDir := ctx.Code()
	if codeDir != "" {
		envLocalFile := filepath.Join(codeDir, ".booth", ".env-local")
		if fileExists(envLocalFile) {
			if err := checkEnvLocalGitignored(envLocalFile, codeDir); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			builder.CommonArgs.Append(ilist.NewList[string]("--env-file", envLocalFile))
			if ctx.Verbose() {
				fmt.Printf("Using env-local: %s\n", envLocalFile)
			}
		}
	}

	// Step 2: Apply user's env-file (explicit or auto-detected)
	containerEnvFile := ctx.EnvFile()

	// If not set, default to <workspace>/.env when it exists
	if containerEnvFile == "" {
		candidate := filepath.Join(codeDir, ".env")
		if fileExists(candidate) {
			containerEnvFile = candidate
			builder.Config.EnvFile = candidate
		}
	}

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

// checkEnvLocalGitignored verifies that .booth/.env-local is gitignored.
// Skips the check if git is not available or the project is not a git repo.
func checkEnvLocalGitignored(envLocalFile, codeDir string) error {
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
	cmd = exec.Command(gitPath, "-C", codeDir, "check-ignore", "-q", ".booth/.env-local")
	cmd.Stdout = nil
	cmd.Stderr = nil
	if err := cmd.Run(); err != nil {
		return fmt.Errorf(
			"env-local file %q is NOT gitignored. "+
				"Add '.env-local' to .booth/.gitignore before using this feature. "+
				"Refusing to run to prevent accidental credential exposure",
			envLocalFile,
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
