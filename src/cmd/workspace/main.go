package main

import (
	"fmt"
	"os"
)

func main() {
	// Check for commands
	if len(os.Args) > 1 {
		command := os.Args[1]

		switch command {
		case "version":
			showVersion()
			return
		case "--help", "-h", "help":
			showHelp()
			return
		case "run":
			runWorkspace()
			return
		default:
			// If it starts with --, treat as run with options
			if len(command) > 0 && command[0] == '-' {
				runWorkspace()
				return
			}
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
			fmt.Fprintln(os.Stderr, "Use 'workspace help' for usage information")
			os.Exit(1)
		}
	}

	// No arguments: run workspace
	runWorkspace()
}
