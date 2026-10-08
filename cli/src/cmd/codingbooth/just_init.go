// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/term"

	"github.com/nawaman/codingbooth/src/pkg/justinit"
)

// runJustInit is `booth just-init [path] [--yes]`: write the starter Justfile.
// A Justfile already there is backed up first, with the user's say-so — asked
// on a terminal, or given up front with --yes.
func runJustInit() {
	os.Exit(justInit(os.Args[2:], os.Stdin, os.Stdout, os.Stderr, term.IsTerminal(int(os.Stdin.Fd()))))
}

func justInit(args []string, stdin io.Reader, stdout, stderr io.Writer, interactive bool) int {
	dir := "."
	yes := false
	for i := 0; i < len(args); i++ {
		switch a := args[i]; {
		case a == "-h" || a == "--help" || a == "help":
			showHelpJustInit()
			return 0
		case a == "-y" || a == "--yes":
			yes = true
		case a == "--code":
			// The shell-config function appends --code <project root> when booth
			// is run from a subfolder, so the Justfile lands at the root.
			if i+1 >= len(args) {
				fmt.Fprintln(stderr, "Error: --code needs a path")
				return 2
			}
			i++
			dir = args[i]
		case strings.HasPrefix(a, "--code="):
			dir = strings.TrimPrefix(a, "--code=")
		case strings.HasPrefix(a, "-"):
			fmt.Fprintf(stderr, "Error: unknown option %s\nRun '%s just-init --help' for usage.\n", a, scriptName())
			return 2
		default:
			dir = a
		}
	}

	if info, err := os.Stat(dir); err != nil || !info.IsDir() {
		fmt.Fprintf(stderr, "Error: %s is not a folder\n", dir)
		return 1
	}

	if existing := justinit.FindJustfile(dir); existing != "" {
		backup := justinit.BackupPath(existing)
		if !yes {
			if !interactive {
				fmt.Fprintf(stderr, "%s already exists. Run again with --yes to back it up to %s and write a new one.\n",
					existing, filepath.Base(backup))
				return 1
			}
			fmt.Fprintf(stderr, "%s already exists. Back it up to %s and write a new one? [y/N] ",
				existing, filepath.Base(backup))
			answer, _ := bufio.NewReader(stdin).ReadString('\n')
			answer = strings.TrimSpace(answer)
			if answer != "y" && answer != "Y" {
				fmt.Fprintln(stderr, "Left as it is.")
				return 1
			}
		}
		moved, err := justinit.Backup(existing)
		if err != nil {
			fmt.Fprintf(stderr, "Error: backing up %s: %v\n", existing, err)
			return 1
		}
		fmt.Fprintf(stdout, "Backed up %s to %s\n", existing, moved)
	}

	path, err := justinit.Write(dir)
	if err != nil {
		fmt.Fprintf(stderr, "Error: %v\n", err)
		return 1
	}
	fmt.Fprintf(stdout, "Created %s — run `just` to list its recipes (no just on the host? `./booth exec --run -- just`).\n", path)
	return 0
}
