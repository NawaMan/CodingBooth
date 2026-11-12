// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"

	"github.com/nawaman/codingbooth/src/pkg/booth"
	"github.com/nawaman/codingbooth/src/pkg/dash"
	"github.com/nawaman/codingbooth/src/pkg/docker"
	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// runDash is `booth dash`.
func runDash(_ string) {
	flagSet := flag.NewFlagSet("dash", flag.ContinueOnError)
	var engine string
	flagSet.Func("engine", "Container engine: docker, podman, apple", func(value string) error {
		value = strings.ToLower(strings.TrimSpace(value))
		switch value {
		case "docker", "podman", "apple":
			engine = value
			return nil
		}
		return fmt.Errorf("invalid engine %q (supported: docker, podman, apple)", value)
	})
	interval := flagSet.Duration("interval", 2*time.Second, "Time between refreshes")
	flagSet.Usage = showHelpDash
	if err := flagSet.Parse(os.Args[2:]); err != nil {
		if err == flag.ErrHelp {
			return
		}
		os.Exit(2)
	}
	if flagSet.NArg() != 0 {
		fmt.Fprintln(os.Stderr, "Error: booth dash takes no positional arguments.")
		os.Exit(2)
	}
	if *interval < 500*time.Millisecond {
		fmt.Fprintln(os.Stderr, "Error: --interval must be at least 500ms.")
		os.Exit(2)
	}
	if !docker.IsStdinTTY() || !docker.IsStdoutTTY() {
		fmt.Fprintln(os.Stderr, "Error: booth dash needs a terminal. For scripts, use: booth list --json")
		os.Exit(1)
	}

	// Actions run this same binary (`booth stop --name … --engine …`), so each
	// behaves exactly as it does when typed — lifecycle log, sidecars and all.
	self, err := os.Executable()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: cannot find the booth binary: %v\n", err)
		os.Exit(1)
	}
	home, _ := os.UserHomeDir()
	cwd, _ := os.Getwd()

	deps := dash.Deps{
		Snapshot: func() ([]lifecycle.Booth, []string, error) { return lifecycle.Snapshot(engine) },
		Run: func(dir string, args []string) (string, error) {
			// No stdin: a command that would prompt fails instead of hanging
			// behind the dashboard.
			cmd := detach(exec.Command(self, args...))
			cmd.Dir = dir
			out, err := cmd.CombinedOutput()
			return string(out), err
		},
		Repos: func(booths []lifecycle.Booth) []lifecycle.Repo {
			return lifecycle.Repos(booths, cwd)
		},
		Editor: editorCommand,
		Command: func(dir string, args []string) *exec.Cmd {
			cmd := exec.Command(self, args...)
			cmd.Dir = dir
			return cmd
		},
		Message: func(ctx context.Context, args []string) (string, error) {
			out, err := detach(exec.CommandContext(ctx, self, args...)).CombinedOutput()
			return string(out), err
		},
		Open: booth.OpenURLInBrowser,
		Ports: func(b lifecycle.Booth) ([]lifecycle.ExposedPort, error) {
			return lifecycle.ExposedPorts(b.Name, b.Engine)
		},
		Stats:   lifecycle.Stats,
		State:   lifecycle.State,
		Pending: lifecycle.PendingMessages,
		Logs: func(b lifecycle.Booth, lines int) (string, error) {
			out, err := detach(exec.Command(self, "logs", "--name", b.Name, "--engine", b.Engine,
				"-n", strconv.Itoa(lines))).CombinedOutput()
			if err != nil {
				return "", fmt.Errorf("%s", lastLine(string(out), err))
			}
			return string(out), nil
		},
		Interval: *interval,
		Home:     home,
	}
	// K and its hint only for those who have GitKraken.
	if _, err := exec.LookPath("gitkraken"); err == nil {
		deps.GitKraken = openGitKraken
	}
	if err := dash.Run(deps); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// lastLine is a failed command's last line of output, or err when it printed none.
func lastLine(out string, err error) string {
	lines := strings.Split(strings.TrimSpace(out), "\n")
	if last := strings.TrimSpace(lines[len(lines)-1]); last != "" {
		return last
	}
	return err.Error()
}

// editorCommand opens path in $VISUAL, else $EDITOR, else VS Code (code). The
// dashboard hands it the terminal, so a terminal editor works as well as a
// window that returns at once.
func editorCommand(path string) (*exec.Cmd, error) {
	editor := strings.TrimSpace(os.Getenv("VISUAL"))
	if editor == "" {
		editor = strings.TrimSpace(os.Getenv("EDITOR"))
	}
	if editor == "" {
		editor = "code"
	}
	fields := strings.Fields(editor)
	bin, err := exec.LookPath(fields[0])
	if err != nil {
		if os.Getenv("VISUAL") == "" && os.Getenv("EDITOR") == "" {
			return nil, fmt.Errorf("no editor: set $VISUAL (code is not installed)")
		}
		return nil, fmt.Errorf("editor %q is not installed", fields[0])
	}
	return exec.Command(bin, append(fields[1:], path)...), nil
}

// openGitKraken starts GitKraken on path and leaves it running.
func openGitKraken(path string) error {
	bin, err := exec.LookPath("gitkraken")
	if err != nil {
		return fmt.Errorf("GitKraken is not installed (no gitkraken on PATH)")
	}
	cmd := exec.Command(bin, "-p", path)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("cannot start GitKraken: %v", err)
	}
	go cmd.Wait() //nolint:errcheck // reaped, not waited for
	return nil
}
