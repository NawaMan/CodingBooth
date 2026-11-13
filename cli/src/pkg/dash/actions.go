// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package dash

import (
	"fmt"

	"github.com/nawaman/codingbooth/src/pkg/lifecycle"
)

// plan is what a key does to the selected booth: the booth subcommand to run
// (always naming the booth and its engine, so a name used on two engines is
// never ambiguous), whether to ask first, and whether it takes the terminal.
type plan struct {
	Verb string   // "start", "stop", … — shown in the status line
	Args []string // arguments to the booth binary
	// Confirm is the y/N question to ask first; "" runs at once.
	Confirm string
	// Interactive commands take over the terminal (tea.ExecProcess) and return
	// to the dashboard when they exit; the others run in the background with
	// their output captured.
	Interactive bool
	// Busy is the status a background command shows on its row while it runs.
	Busy string
	// Done is the status line once it succeeded.
	Done string
	// URL, when set, is opened in the browser instead of running a command.
	URL string
	// Hold: when an interactive command fails, wait for Enter before the
	// dashboard comes back, so its last words can be read.
	Hold bool
	// Dir is where the command runs ("" = where the dashboard runs): worktree
	// commands name the worktree within the repository they run in.
	Dir string
	// Danger shows the question in the error colour: answering y loses work.
	Danger bool
	// Forget, when set, drops this remembered booth instead of running a command.
	Forget *lifecycle.Booth
}

// planFor decides what key does to booth. A key that does not apply to the
// booth's state returns a reason instead, shown in the status line.
func planFor(key string, booth lifecycle.Booth) (plan, string) {
	target := []string{"--name", booth.Name, "--engine", booth.Engine}
	with := func(subcommand string, extra ...string) []string {
		args := append([]string{subcommand}, target...)
		return append(args, extra...)
	}
	if booth.Gone() {
		return gonePlan(key, booth)
	}

	switch key {
	case keyStart:
		if booth.Running() {
			return plan{}, fmt.Sprintf("%s is already running.", booth.Name)
		}
		// A start takes the terminal: booth may build an image, and may ask
		// before starting a booth that can reach the host (a question it asks
		// on the terminal, which a background command must not have).
		if booth.Daemon {
			return plan{Verb: "start", Args: with("start", "--daemon"), Interactive: true, Hold: true,
				Done: "Started " + booth.Name + "."}, ""
		}
		// An interactive booth starts the way `booth start` does: attached, and
		// back to the dashboard when its session ends.
		return plan{Verb: "start", Args: with("start"), Interactive: true}, ""

	case keyStop:
		if !booth.Running() {
			return plan{}, fmt.Sprintf("%s is not running.", booth.Name)
		}
		question := fmt.Sprintf("Stop %s?", booth.Name)
		if !booth.KeepAlive {
			question = fmt.Sprintf("Stop %s? It is not keep-alive, so its container is removed too.", booth.Name)
		}
		return plan{Verb: "stop", Args: with("stop"), Confirm: question, Busy: "stopping…", Done: "Stopped " + booth.Name + "."}, ""

	case keyRestart:
		if !booth.Running() {
			return plan{}, fmt.Sprintf("%s is not running; use s to start it.", booth.Name)
		}
		return plan{Verb: "restart", Args: with("restart"), Confirm: fmt.Sprintf("Restart %s?", booth.Name),
			Busy: "restarting…", Done: "Restarted " + booth.Name + "."}, ""

	case keyRemove:
		if booth.Running() {
			return plan{Verb: "delete", Args: with("remove", "--force"),
				Confirm: fmt.Sprintf("%s is running. Force-delete it and its home volume?", booth.Name),
				Busy:    "deleting…", Done: "Deleted " + booth.Name + "."}, ""
		}
		return plan{Verb: "delete", Args: with("remove"),
			Confirm: fmt.Sprintf("Delete %s and its home volume?", booth.Name),
			Busy:    "deleting…", Done: "Deleted " + booth.Name + "."}, ""

	case keyOpen:
		if !booth.Running() {
			return plan{}, fmt.Sprintf("%s is not running; use s to start it.", booth.Name)
		}
		url := booth.URL()
		if url == "" {
			return plan{}, fmt.Sprintf("%s publishes no port to open.", booth.Name)
		}
		return plan{Verb: "open", URL: url, Done: "Opened " + url + " in your browser."}, ""

	case keyShell:
		if !booth.Running() {
			// `shell --run` starts the container as it is (its own variant) and
			// stops it again when the shell ends, so the row is left as found.
			// Held on failure, so a start that fails can be read; a shell that
			// ends on a failed command is held too, which is the lesser cost.
			return plan{Verb: "open a shell in", Args: with("shell", "--run"), Interactive: true, Hold: true,
				Confirm: fmt.Sprintf("%s is not running. Start it for a shell? It stops again when the shell ends.", booth.Name)}, ""
		}
		return plan{Verb: "shell", Args: with("shell"), Interactive: true}, ""
	}
	return plan{}, ""
}

// gonePlan is what key does to a remembered booth whose container is gone:
// Enter makes one for a shell, d forgets it, the rest need a container.
func gonePlan(key string, booth lifecycle.Booth) (plan, string) {
	switch key {
	case keyShell:
		// The same --run as a bare worktree's: a booth for the shell, under
		// its old name, removed again when the shell ends.
		return plan{Verb: "open a shell in", Interactive: true, Hold: true, Dir: booth.CodePath,
			Args:    []string{"shell", "--run", "--name", booth.Name, "--engine", booth.Engine, "--code", booth.CodePath},
			Confirm: fmt.Sprintf("%s has no container. Start a terminal booth for a shell? It is removed when the shell ends.", booth.Name)}, ""
	case keyRemove:
		forget := booth
		return plan{Verb: "forget", Forget: &forget,
			Confirm: fmt.Sprintf("Forget %s? Its folder is not touched.", booth.Name),
			Done:    "Forgot " + booth.Name + "."}, ""
	case keyStart, keyStop, keyRestart, keyOpen:
		return plan{}, booth.Name + " has no container; Enter opens a shell in its folder."
	}
	return plan{}, ""
}

// messageArgs is `booth message send` for a message to booth.
func messageArgs(booth lifecycle.Booth, kind messageKind, title, body string) []string {
	return []string{"message", "send", "--name", booth.Name, "--engine", booth.Engine,
		"--type", kind.Type, "--title", title, "--body", body}
}
