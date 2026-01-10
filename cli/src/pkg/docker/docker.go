// Package docker provides Docker CLI execution with verbose and dryrun support.
package docker

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"

	"github.com/nawaman/workspace/cli/src/pkg/ilist"
)

type DockerFlags struct {
	Dryrun  bool
	Verbose bool
	Silent  bool
}

// Docker executes a docker command with the given subcommand and arguments.
// If silent is true, suppresses all stdout/stderr from the docker process.
func Docker(flags DockerFlags, subcommand string, args ilist.List[ilist.List[string]]) error {
	// Preserve current behavior: print the command for dry-run or verbose,
	// even if silent is true (matches "contract" of showing what would run).
	if flags.Dryrun || flags.Verbose {
		var printingArgs [][]string
		printingArgs = append(printingArgs, []string{subcommand})

		// For build commands, check for --progress
		if subcommand == "build" {
			hasProgress := false
			args.Range(func(_ int, group ilist.List[string]) bool {
				group.Range(func(_ int, arg string) bool {
					if strings.HasPrefix(arg, "--progress") {
						hasProgress = true
						return false
					}
					return true
				})
				return !hasProgress
			})
			if !hasProgress {
				printingArgs = append(printingArgs, []string{"--progress=auto"})
			}
		}

		// - Always add -i (interactive, keeps stdin open)
		// - Add -t only when we have a TTY (allocates a pseudo-TTY)
		if subcommand == "run" {
			runFlags := []string{"-i"}
			if HasInteractiveTTY() {
				runFlags = append(runFlags, "-t")
			}
			printingArgs = append(printingArgs, runFlags)
		}

		args.Range(func(_ int, group ilist.List[string]) bool {
			// We filter TTY flags for printing just like we do for execution
			filtered := filterTTYFlags(group.Slice())
			if len(filtered) > 0 {
				printingArgs = append(printingArgs, filtered)
			}
			return true
		})

		printCmd("docker", printingArgs...)
	}

	if flags.Dryrun {
		return nil
	}

	cmdArgs := make([]string, 0, 64) // Pre-allocate some space
	cmdArgs = append(cmdArgs, subcommand)

	// - Always add -i (interactive, keeps stdin open)
	// - Add -t only when we have a TTY (allocates a pseudo-TTY)
	if subcommand == "run" {
		cmdArgs = append(cmdArgs, "-i")
		if HasInteractiveTTY() {
			cmdArgs = append(cmdArgs, "-t")
		}
	}

	// For build commands, add --progress=auto if not present
	if subcommand == "build" {
		hasProgress := false
		args.Range(func(_ int, group ilist.List[string]) bool {
			group.Range(func(_ int, arg string) bool {
				if strings.HasPrefix(arg, "--progress") {
					hasProgress = true
					return false
				}
				return true
			})
			return !hasProgress
		})
		if !hasProgress {
			cmdArgs = append(cmdArgs, "--progress=auto")
		}
	}

	args.Range(func(_ int, group ilist.List[string]) bool {
		cmdArgs = append(cmdArgs, filterTTYFlags(group.Slice())...)
		return true
	})

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
		// Only set TERM if we are running interactively or if explicitly requested?
		// For now, keeping existing logic
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

// DockerOutput executes a docker command and returns its stdout output.
// This is useful for commands like "docker ps" where we need to check the output.
// The function respects Dryrun and Verbose flags for printing, but always captures output when not in dryrun mode.
func DockerOutput(flags DockerFlags, subcommand string, args ilist.List[ilist.List[string]]) (string, error) {
	// Print command if dryrun or verbose (same as Docker function)
	if flags.Dryrun || flags.Verbose {
		var printingArgs [][]string
		printingArgs = append(printingArgs, []string{subcommand})

		// For build commands, check for --progress
		if subcommand == "build" {
			hasProgress := false
			args.Range(func(_ int, group ilist.List[string]) bool {
				group.Range(func(_ int, arg string) bool {
					if strings.HasPrefix(arg, "--progress") {
						hasProgress = true
						return false
					}
					return true
				})
				return !hasProgress
			})
			if !hasProgress {
				printingArgs = append(printingArgs, []string{"--progress=auto"})
			}
		}

		// - Always add -i (interactive, keeps stdin open)
		// - Add -t only when we have a TTY (allocates a pseudo-TTY)
		if subcommand == "run" {
			runFlags := []string{"-i"}
			if HasInteractiveTTY() {
				runFlags = append(runFlags, "-t")
			}
			printingArgs = append(printingArgs, runFlags)
		}

		args.Range(func(_ int, group ilist.List[string]) bool {
			filtered := filterTTYFlags(group.Slice())
			if len(filtered) > 0 {
				printingArgs = append(printingArgs, filtered)
			}
			return true
		})

		printCmd("docker", printingArgs...)
	}

	if flags.Dryrun {
		return "", nil
	}

	cmdArgs := make([]string, 0, 64)
	cmdArgs = append(cmdArgs, subcommand)

	// - Always add -i (interactive, keeps stdin open)
	// - Add -t only when we have a TTY (allocates a pseudo-TTY)
	if subcommand == "run" {
		cmdArgs = append(cmdArgs, "-i")
		if HasInteractiveTTY() {
			cmdArgs = append(cmdArgs, "-t")
		}
	}

	// For build commands, add --progress=auto if not present
	if subcommand == "build" {
		hasProgress := false
		args.Range(func(_ int, group ilist.List[string]) bool {
			group.Range(func(_ int, arg string) bool {
				if strings.HasPrefix(arg, "--progress") {
					hasProgress = true
					return false
				}
				return true
			})
			return !hasProgress
		})
		if !hasProgress {
			cmdArgs = append(cmdArgs, "--progress=auto")
		}
	}

	args.Range(func(_ int, group ilist.List[string]) bool {
		cmdArgs = append(cmdArgs, filterTTYFlags(group.Slice())...)
		return true
	})

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
	cmd.Stdin = os.Stdin

	// Capture stdout to buffer
	var stdout bytes.Buffer
	cmd.Stdout = &stdout

	// Handle stderr based on Silent flag
	if flags.Silent {
		cmd.Stderr = io.Discard
	} else {
		cmd.Stderr = os.Stderr
	}

	// Run and propagate exit status
	if err := cmd.Run(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			return stdout.String(), fmt.Errorf("docker %s failed with exit code %d", subcommand, exitErr.ExitCode())
		}
		return stdout.String(), fmt.Errorf("docker %s failed: %w", subcommand, err)
	}

	return stdout.String(), nil
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
