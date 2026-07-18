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
			dispatchHelp(os.Args[2:], version)
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
		case "prune":
			pruneBooths(version)
			return
		case "home-volume-list":
			listHomeVolumes(version)
			return
		case "home-volume-export":
			exportHomeVolume(version)
			return
		case "home-volume-import":
			importHomeVolume(version)
			return
		case "shell":
			shellBooth(version)
			return
		case "exec":
			execBooth(version)
			return
		case "message":
			messageBooth(version)
			return
		case "expose":
			exposeBooth(version)
			return
		case "example":
			runExample(version)
			return
		case "template":
			runTemplate(version)
			return
		case "config":
			runConfig(version)
			return
		case "tools-cache":
			runToolsCache()
			return
		case "build":
			buildBooth(version)
			return
		case "emit-dockerfile":
			emitDockerfile()
			return
		case "print-default-allowlist.txt":
			printDefaultAllowlist()
			return
		default:
			// If it starts with --, treat as run with options
			if len(command) > 0 && command[0] == '-' {
				runBooth(version, os.Args)
				return
			}
			fmt.Fprintf(os.Stderr, "Unknown command: %s\n", command)
			fmt.Fprintf(os.Stderr, "Use '%s help' for usage information\n", os.Args[0])
			os.Exit(1)
			return
		}
	}

	// No arguments: run booth
	runBooth(version, os.Args)
}
