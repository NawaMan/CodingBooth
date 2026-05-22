// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package booth

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/appctx"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
	"github.com/nawaman/codingbooth/src/pkg/shellexpand"
)

// ApplyEnvFile applies environment file configuration and returns updated AppContext.
//
// Layering order (each layer becomes a separate --env-file arg; on a key
// collision Docker honors the rightmost --env-file, so later layers win):
//  1. .booth/.env                — base, always included if present (must be gitignored)
//  2. .booth/.env--<profile>     — one per resolved profile, in apply order
//  3. user-supplied --env-file   — explicit override, applied last
//
// Profiles and --env-file are mutually exclusive (enforced at init), so in
// practice layers 2 and 3 do not coexist.
//
// All sources are parsed and expanded by booth (see docs/BOOTH_VARS.md) and
// written to temp files under .booth/.tmp/ before being handed to Docker.
//
// Note: .env in the project root is NOT auto-detected — it belongs to the application.
func ApplyEnvFile(ctx appctx.AppContext) appctx.AppContext {
	builder := ctx.ToBuilder()
	codeDir := ctx.Code()

	// Step 1: Apply .booth/.env if it exists (always included, independent of env-file setting)
	if codeDir != "" {
		boothEnvFile := filepath.Join(codeDir, ".booth", ".env")
		if fileExists(boothEnvFile) {
			if err := checkBoothEnvGitignored(boothEnvFile, codeDir); err != nil {
				fmt.Fprintf(os.Stderr, "Error: %v\n", err)
				os.Exit(1)
			}
			finalPath := mustPrepareExpandedEnvFile(ctx, boothEnvFile, codeDir, "booth")
			builder.CommonArgs.Append(ilist.NewList[string]("--env-file", finalPath))
			if ctx.Verbose() {
				if finalPath == boothEnvFile {
					fmt.Printf("Using booth env: %s\n", boothEnvFile)
				} else {
					fmt.Printf("Using booth env: %s (expanded → %s)\n", boothEnvFile, finalPath)
				}
			}
		}
	}

	// Step 2: Apply per-profile .env--<name> files in apply order.
	for _, p := range ctx.Profiles() {
		if p.EnvPath == "" {
			continue
		}
		if !fileExists(p.EnvPath) {
			// Discover already verified existence, but guard against
			// concurrent removal between init and ApplyEnvFile.
			fmt.Fprintf(os.Stderr, "Error: profile env file disappeared: %s\n", p.EnvPath)
			os.Exit(1)
		}
		label := "profile-" + p.Name
		finalPath := mustPrepareExpandedEnvFile(ctx, p.EnvPath, codeDir, label)
		builder.CommonArgs.Append(ilist.NewList[string]("--env-file", finalPath))
		if ctx.Verbose() {
			if finalPath == p.EnvPath {
				fmt.Printf("Using profile env (%s): %s\n", p.Name, p.EnvPath)
			} else {
				fmt.Printf("Using profile env (%s): %s (expanded → %s)\n", p.Name, p.EnvPath, finalPath)
			}
		}
	}

	// Step 3: Apply user's explicit env-file (if configured)
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

		finalPath := mustPrepareExpandedEnvFile(ctx, containerEnvFile, codeDir, "user")
		builder.CommonArgs.Append(ilist.NewList[string]("--env-file", finalPath))
		if ctx.Verbose() {
			if finalPath == containerEnvFile {
				fmt.Printf("Using env-file: %s\n", containerEnvFile)
			} else {
				fmt.Printf("Using env-file: %s (expanded → %s)\n", containerEnvFile, finalPath)
			}
		}
	}

	return builder.Build()
}

// mustPrepareExpandedEnvFile parses src, expands values with booth's
// bash-like rules, and writes the expanded result to a temp file under
// codeDir/.booth/.tmp/. Returns the path to the temp file. On parse or
// expansion error, prints a source-located message and exits non-zero
// before any docker invocation.
//
// In dryrun mode the original src path is returned unchanged (booth still
// parses and validates so that errors surface), and no temp file is
// written.
func mustPrepareExpandedEnvFile(ctx appctx.AppContext, src, codeDir, label string) string {
	entries, err := shellexpand.ParseEnvFile(src)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	expanded, err := shellexpand.ExpandEntries(entries, shellexpand.DefaultLookup, src)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Dryrun: keep the original path so the printed docker command is
	// stable and inspectable. We still validated the file above.
	if ctx.Dryrun() {
		return src
	}

	// Without a codeDir we have no .booth/.tmp/ to write into.
	if codeDir == "" {
		return src
	}

	tmpDir := filepath.Join(codeDir, ".booth", ".tmp")
	if err := os.MkdirAll(tmpDir, 0755); err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to create %s: %v\n", tmpDir, err)
		os.Exit(1)
	}

	name := fmt.Sprintf("env-%s-%d.expanded", label, time.Now().UnixNano())
	dst := filepath.Join(tmpDir, name)
	if err := os.WriteFile(dst, []byte(shellexpand.FormatEnvFile(expanded)), 0600); err != nil {
		fmt.Fprintf(os.Stderr, "Error: failed to write %s: %v\n", dst, err)
		os.Exit(1)
	}
	return dst
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
