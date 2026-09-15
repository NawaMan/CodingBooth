// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package showcase

import (
	"fmt"
	"os"
	"os/exec"
)

// CloneAtCommit clones repoURL's branch into destPath and pins it to commit
// via a detached-HEAD checkout, so the working tree matches the exact state
// the showcase was published from rather than the branch's current tip.
func CloneAtCommit(repoURL, branch, commit, destPath string) error {
	if _, err := exec.LookPath("git"); err != nil {
		return fmt.Errorf("git is required to import a showcase but was not found in PATH")
	}

	if err := runGit("", "clone", "--single-branch", "--branch", branch, repoURL, destPath); err != nil {
		return fmt.Errorf("failed to clone %s (branch %s): %w", repoURL, branch, err)
	}

	if err := runGit(destPath, "checkout", commit); err != nil {
		// The pinned commit may not be on branch's fetched history (e.g. the
		// branch was rewritten since the showcase was published, or the
		// commit lives on another branch of the same remote). Ask the remote
		// for that exact commit directly and retry once before giving up.
		if fetchErr := runGit(destPath, "fetch", "origin", commit); fetchErr == nil {
			if retryErr := runGit(destPath, "checkout", commit); retryErr == nil {
				return nil
			}
		}
		return fmt.Errorf("failed to check out commit %s in %s (branch %s): %w", commit, repoURL, branch, err)
	}

	return nil
}

func runGit(dir string, args ...string) error {
	cmd := exec.Command("git", args...)
	cmd.Dir = dir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
