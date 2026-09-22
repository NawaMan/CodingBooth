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

	"github.com/nawaman/codingbooth/src/pkg/ilist"
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
	if needsPodmanBuildFormat("build", flags.binary(), args) {
		cmdArgs = append(cmdArgs, "--format", "docker")
	}

	args.Range(func(_ int, group ilist.List[string]) bool {
		cmdArgs = append(cmdArgs, group.Slice()...)
		return true
	})

	if flags.Dryrun || flags.Verbose {
		var printingArgs [][]string
		printingArgs = append(printingArgs, []string{"build"})
		if needsPodmanBuildFormat("build", flags.binary(), args) {
			printingArgs = append(printingArgs, []string{"--format", "docker"})
		}
		args.Range(func(_ int, group ilist.List[string]) bool {
			printingArgs = append(printingArgs, group.Slice())
			return true
		})
		printCmd(flags.binary(), printingArgs...)
	}

	if flags.Dryrun {
		return nil
	}

	cmd := exec.Command(flags.binary(), cmdArgs...)

	// Set environment (same as Docker function)
	env := append(os.Environ(), "MSYS_NO_PATHCONV=1")
	env = append(env, "FORCE_COLOR=1")
	env = append(env, "BUILDKIT_COLORS=run=cyan:warning=yellow:error=red:cancel=green")

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

	cmd.Stdin = os.Stdin

	// The captured stream still lands in the buffer verbatim for the failure
	// path; progress reads it on the way past to draw one transient line on
	// the terminal. Deferred LIFO: the line is erased first, and only then is
	// a terminal that buildProgressOut had to open for it handed back.
	progressOut, releaseProgressOut := buildProgressOut()
	defer releaseProgressOut()

	var captureBuf bytes.Buffer
	progress := newBuildProgress(&captureBuf, progressOut, flags.binary())
	defer progress.Close()

	if flags.binary() == "podman" {
		// Buildah's STEP headers and every RUN step's own output land on
		// stdout, not stderr (confirmed against a real `podman build`) — only
		// registry-pull chatter and the final error go to stderr. Silencing
		// only stderr, as the Docker/BuildKit path below does, would leave
		// every STEP and RUN line printing live, exactly the clutter
		// --silence-build exists to hide. Cmd docs: giving Stdout and Stderr
		// the same comparable writer serializes both through it, so no extra
		// locking is needed here beyond buildProgress's own.
		cmd.Stdout = progress
		cmd.Stderr = progress
	} else {
		// BuildKit's progress lives on stderr; stdout is just the image ID
		// echoed back, harmless to forward live.
		cmd.Stdout = os.Stdout
		cmd.Stderr = progress
	}

	// Run the build
	if err := cmd.Run(); err != nil {
		// Build failed - wipe the status line, then display what was captured
		progress.Close()
		fmt.Fprintln(os.Stderr)
		fmt.Fprintf(os.Stderr, "❌ %s build failed!\n", flags.binary())
		fmt.Fprintln(os.Stderr, "---- Build output ----")
		fmt.Fprint(os.Stderr, captureBuf.String())
		fmt.Fprintln(os.Stderr, "----------------------")

		if exitErr, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("%s build failed with exit code %d", flags.binary(), exitErr.ExitCode())
		}
		return fmt.Errorf("%s build failed: %w", flags.binary(), err)
	}

	// Build succeeded - the status line is wiped and stderr is discarded
	progress.Close()

	return nil
}
