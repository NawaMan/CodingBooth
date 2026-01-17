// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import (
	"fmt"
	"os"
)

var version = "dev"

func main() {
	// Check for commands
	if len(os.Args) > 1 {
		command := os.Args[1]

		switch command {
		case "version":
			showVersion(version)
			return
		case "--help", "-h", "help":
			showHelp(version)
			return
		case "run":
			runBooth(version)
			return
		default:
			// If it starts with --, treat as run with options
			if len(command) > 0 && command[0] == '-' {
				runBooth(version)
				return
			}
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
			fmt.Fprintln(os.Stderr, "Use 'coding-booth help' for usage information")
			os.Exit(1)
			return
		}
	}

	// No arguments: run booth
	runBooth(version)
}
