// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package docker

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"

	"github.com/nawaman/coding-booth/src/pkg/ilist"
)

// DockerBuild executes a docker build command with optional silent mode.
// When SilenceBuild is enabled, it captures stderr and only displays it on failure.
func DockerBuild(flags DockerFlags, args ilist.List[ilist.List[string]]) error {
	// If not in silent mode, just call Docker build normally
	if !flags.Silent {
		return Docker(flags, "build", args)
	}

	// Silent mode: capture stderr and only show on failure
	cmdArgs := make([]string, 0, 64)
	cmdArgs = append(cmdArgs, "build")

	args.Range(func(_ int, group ilist.List[string]) bool {
		cmdArgs = append(cmdArgs, group.Slice()...)
		return true
	})

	if flags.Dryrun || flags.Verbose {
		var printingArgs [][]string
		printingArgs = append(printingArgs, []string{"build"})
		args.Range(func(_ int, group ilist.List[string]) bool {
			printingArgs = append(printingArgs, group.Slice())
			return true
		})
		printCmd("docker", printingArgs...)
	}

	if flags.Dryrun {
		return nil
	}

	cmd := exec.Command("docker", cmdArgs...)

	// Set environment (same as Docker function)
	env := append(os.Environ(), "MSYS_NO_PATHCONV=1")
	env = append(env, "FORCE_COLOR=1")
	env = append(env, "BUILDKIT_COLORS=run=green:warning=yellow:error=red:cancel=cyan")

	hasTermSet := false
	for _, e := range env {
		if strings.HasPrefix(e, "TERM=") {
			hasTermSet = true
			break
		}
	}
	if !hasTermSet {
		env = append(env, "TERM=xterm-256color")
	}

	cmd.Env = env

	// Forward stdout normally, but capture stderr
	cmd.Stdout = os.Stdout
	cmd.Stdin = os.Stdin

	var stderrBuf bytes.Buffer
	cmd.Stderr = &stderrBuf

	// Run the build
	if err := cmd.Run(); err != nil {
		// Build failed - display captured stderr
		fmt.Fprintln(os.Stderr)
		fmt.Fprintln(os.Stderr, "❌ Docker build failed!")
		fmt.Fprintln(os.Stderr, "---- Build output ----")
		fmt.Fprint(os.Stderr, stderrBuf.String())
		fmt.Fprintln(os.Stderr, "----------------------")

		if exitErr, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("docker build failed with exit code %d", exitErr.ExitCode())
		}
		return fmt.Errorf("docker build failed: %w", err)
	}

	// Build succeeded - stderr is discarded
	return nil
}
