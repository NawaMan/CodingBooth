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
}

// planFor decides what key does to booth. A key that does not apply to the
// booth's state returns a reason instead, shown in the status line.
func planFor(key string, booth lifecycle.Booth) (plan, string) {
	target := []string{"--name", booth.Name, "--engine", booth.Engine}
	with := func(subcommand string, extra ...string) []string {
		args := append([]string{subcommand}, target...)
		return append(args, extra...)
	}

	switch key {
	case keyStart:
		if booth.Running() {
			return plan{}, fmt.Sprintf("%s is already running.", booth.Name)
		}
		if booth.Daemon {
			return plan{Verb: "start", Args: with("start", "--daemon"), Busy: "starting…", Done: "Started " + booth.Name + "."}, ""
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
			return plan{Verb: "remove", Args: with("remove", "--force"),
				Confirm: fmt.Sprintf("%s is running. Force-remove it and its home volume?", booth.Name),
				Busy:    "removing…", Done: "Removed " + booth.Name + "."}, ""
		}
		return plan{Verb: "remove", Args: with("remove"),
			Confirm: fmt.Sprintf("Remove %s and its home volume?", booth.Name),
			Busy:    "removing…", Done: "Removed " + booth.Name + "."}, ""

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
			return plan{}, fmt.Sprintf("%s is not running; use s to start it.", booth.Name)
		}
		return plan{Verb: "shell", Args: with("shell"), Interactive: true}, ""
	}
	return plan{}, ""
}
