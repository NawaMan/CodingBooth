package docker

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// DockerBuild executes a docker build command with optional silent mode.
// When SilenceBuild is enabled, it captures stderr and only displays it on failure.
func DockerBuild(flags DockerFlags, args ...string) error {
	// If not in silent mode, just call Docker build normally
	if !flags.Silent {
		return Docker(flags, "build", args...)
	}

	// Silent mode: capture stderr and only show on failure
	cmdArgs := make([]string, 0, len(args)+1)
	cmdArgs = append(cmdArgs, "build")
	cmdArgs = append(cmdArgs, args...)

	if flags.Dryrun || flags.Verbose {
		PrintCmd("docker", cmdArgs...)
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
