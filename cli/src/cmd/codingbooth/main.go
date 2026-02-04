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
			// Keep explicit "run" behavior identical to the implicit default action.
			trimmedArgs := append([]string{os.Args[0]}, os.Args[2:]...)
			runBooth(version, trimmedArgs)
			return
		case "list":
			listBooths(version)
			return
		case "start":
			startBooth(version)
			return
		case "stop":
			stopBooth(version)
			return
		case "restart":
			restartBooth(version)
			return
		case "remove":
			removeBooth(version)
			return
		case "example":
			runExample(version)
			return
		default:
			// If it starts with --, treat as run with options
			if len(command) > 0 && command[0] == '-' {
				runBooth(version, os.Args)
				return
			}
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
			fmt.Fprintln(os.Stderr, "Use 'codingbooth help' for usage information")
			os.Exit(1)
			return
		}
	}

	// No arguments: run booth
	runBooth(version, os.Args)
}
