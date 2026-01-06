// Package docker provides Docker CLI execution with verbose and dryrun support.
package docker

import (
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
)

type DockerFlags struct {
	Dryrun  bool
	Verbose bool
	Silent  bool
}

// Docker executes a docker command with the given subcommand and arguments.
// If silent is true, suppresses all stdout/stderr from the docker process.
func Docker(flags DockerFlags, subcommand string, args ...string) error {
	cmdArgs := make([]string, 0, len(args)+2) // +2 for potential -i and -t flags
	cmdArgs = append(cmdArgs, subcommand)

	// - Always add -i (interactive, keeps stdin open)
	// - Add -t only when we have a TTY (allocates a pseudo-TTY)
	// - Filter out any user-provided TTY flags from args (we manage them above)
	if subcommand == "run" {
		cmdArgs = append(cmdArgs, "-i")
		if HasInteractiveTTY() {
			cmdArgs = append(cmdArgs, "-t")
		}
	}

	// For build commands, add --progress=auto
	if subcommand == "build" {
		hasProgress := false
		for _, arg := range args {
			if strings.HasPrefix(arg, "--progress") {
				hasProgress = true
				break
			}
		}
		if !hasProgress {
			cmdArgs = append(cmdArgs, "--progress=auto")
		}
	}

	cmdArgs = append(cmdArgs, filterTTYFlags(args)...)

	// Preserve current behavior: print the command for dry-run or verbose,
	// even if silent is true (matches "contract" of showing what would run).
	if flags.Dryrun || flags.Verbose {
		PrintCmd("docker", cmdArgs...)
	}

	if flags.Dryrun {
		return nil
	}

	cmd := exec.Command("docker", cmdArgs...)

	// Set environment for Windows path compatibility and color output
	env := append(os.Environ(), "MSYS_NO_PATHCONV=1")
	env = append(env, "FORCE_COLOR=1")
	env = append(env, "BUILDKIT_COLORS=run=green:warning=yellow:error=red:cancel=cyan")

	// Ensure TERM is set for color support (if not already set)
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

	// stdin: keep existing behavior (so docker can read input when needed)
	cmd.Stdin = os.Stdin

	// stdout/stderr: silence if requested
	if flags.Silent {
		cmd.Stdout = io.Discard
		cmd.Stderr = io.Discard
	} else {
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
	}

	// Run and propagate exit status
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return fmt.Errorf("docker %s failed with exit code %d", subcommand, exitErr.ExitCode())
		}
		return fmt.Errorf("docker %s failed: %w", subcommand, err)
	}

	return nil
}

// filterTTYFlags removes user-provided TTY-related flags from args.
// We manage TTY flags explicitly in the Docker function, so we strip any that
// the user might have passed to avoid conflicts.
// It intelligently distinguishes between:
//   - Standalone -i, -it, -t (TTY flags) - always removed
//   - -t <value> (e.g., docker build -t imagename) - always kept
func filterTTYFlags(args []string) []string {
	result := make([]string, 0, len(args))

	for i := 0; i < len(args); i++ {
		arg := args[i]

		// Skip standalone -i, -it flags (always TTY-related)
		if arg == "-i" || arg == "-it" {
			continue
		}

		// For -t, check if it's followed by a value
		if arg == "-t" {
			// Check if there's a next argument and it doesn't look like a flag
			if i+1 < len(args) && !strings.HasPrefix(args[i+1], "-") {
				// This is -t <value> (e.g., docker build -t imagename), keep both
				result = append(result, arg)
				i++
				result = append(result, args[i])
				continue
			}
			// This is standalone -t (TTY flag), skip it
			continue
		}

		// Keep all other arguments
		result = append(result, arg)
	}

	return result
}
