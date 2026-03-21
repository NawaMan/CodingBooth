// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package lifecycle

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"os/exec"
	"strings"

	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/ilist"
)

// stringSliceFlag collects repeatable -e flags into a slice.
type stringSliceFlag []string

func (f *stringSliceFlag) String() string {
	return strings.Join(*f, ", ")
}

func (f *stringSliceFlag) Set(value string) error {
	*f = append(*f, value)
	return nil
}

// Shell opens a new interactive shell inside a running booth container.
func Shell(args []string, stderr io.Writer) error {
	flagSet := flag.NewFlagSet("shell", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	shell := flagSet.String("shell", "", "Shell to launch (default: container default)")
	dir := flagSet.String("dir", "", "Starting directory inside the container")
	envfile := flagSet.String("envfile", "", "Load environment variables from a file")
	var envVars stringSliceFlag
	flagSet.Var(&envVars, "e", "Set environment variable (repeatable)")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(args); err != nil {
		return commandExit(2, "")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, "", flagSet.Args(), stateRunning)
	if err != nil {
		return commandExit(1, err.Error())
	}

	// Build docker exec args
	execArgs := buildExecFlags(true, *dir, envVars, *envfile)

	// Container name
	execArgs = append(execArgs, ilist.NewList(target.Name))

	// Shell command
	shellCmd := "bash"
	if *shell != "" {
		shellCmd = *shell
	}
	execArgs = append(execArgs, ilist.NewList(shellCmd, "-l"))

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "exec", ilist.NewList(execArgs...)); err != nil {
		return forwardExitCode("shell", target.Name, err)
	}
	return nil
}

// Exec runs a command inside a running booth container.
func Exec(args []string, stderr io.Writer) error {
	// Split args at "--" to separate flags from the command to execute.
	flagArgs, cmdArgs := splitAtSeparator(args)

	flagSet := flag.NewFlagSet("exec", flag.ContinueOnError)
	name := flagSet.String("name", "", "Container name")
	dir := flagSet.String("dir", "", "Working directory inside the container")
	interactive := flagSet.Bool("it", false, "Force interactive mode with TTY")
	envfile := flagSet.String("envfile", "", "Load environment variables from a file")
	var envVars stringSliceFlag
	flagSet.Var(&envVars, "e", "Set environment variable (repeatable)")
	flagSet.SetOutput(stderr)

	if err := flagSet.Parse(flagArgs); err != nil {
		return commandExit(2, "")
	}

	if len(cmdArgs) == 0 {
		return commandExit(1, "Error: no command specified. Usage: codingbooth exec <name> -- <command>")
	}

	containers, err := managedContainers(false)
	if err != nil {
		return commandExit(1, fmt.Sprintf("Error: failed to query booths: %v", err))
	}

	target, err := resolveSingleContainer(containers, *name, "", flagSet.Args(), stateRunning)
	if err != nil {
		return commandExit(1, err.Error())
	}

	// Build docker exec args
	execArgs := buildExecFlags(*interactive, *dir, envVars, *envfile)

	// Container name
	execArgs = append(execArgs, ilist.NewList(target.Name))

	// Command to execute
	execArgs = append(execArgs, ilist.NewList(cmdArgs...))

	if err := docker.Docker(docker.DockerFlags{Silent: false}, "exec", ilist.NewList(execArgs...)); err != nil {
		return forwardExitCode("exec", target.Name, err)
	}
	return nil
}

// buildExecFlags constructs the common docker exec flags for both shell and exec.
func buildExecFlags(interactive bool, dir string, envVars stringSliceFlag, envfile string) []ilist.List[string] {
	var execArgs []ilist.List[string]

	// TTY flags
	if interactive && docker.HasInteractiveTTY() {
		execArgs = append(execArgs, ilist.NewList("-it"))
	} else if interactive {
		execArgs = append(execArgs, ilist.NewList("-i"))
	}

	// User and working directory
	userDir := []string{"-u", "coder"}
	if dir != "" {
		userDir = append(userDir, "-w", dir)
	} else {
		userDir = append(userDir, "-w", "/home/coder/code")
	}
	execArgs = append(execArgs, ilist.NewList(userDir...))

	// Environment variables
	for _, env := range envVars {
		execArgs = append(execArgs, ilist.NewList("-e", env))
	}

	// Environment file
	if envfile != "" {
		execArgs = append(execArgs, ilist.NewList("--env-file", envfile))
	}

	return execArgs
}

// splitAtSeparator splits args into two slices at the first "--" separator.
// Returns (before, after). If no "--" is found, returns (args, nil).
func splitAtSeparator(args []string) ([]string, []string) {
	for i, arg := range args {
		if arg == "--" {
			return args[:i], args[i+1:]
		}
	}
	return args, nil
}

// forwardExitCode extracts the exit code from a DockerExitError and returns
// a commandError with that code so the caller can propagate it.
func forwardExitCode(command string, containerName string, err error) error {
	var dockerErr *docker.DockerExitError
	if errors.As(err, &dockerErr) {
		return commandExit(dockerErr.ExitCode, "")
	}
	return commandExit(1, fmt.Sprintf("Error: failed to %s in %q: %v", command, containerName, err))
}

// ExecExitCode extracts the exit code from a docker exec error.
// Returns -1 if the error is not an exec.ExitError.
func ExecExitCode(err error) int {
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode()
	}
	return -1
}
