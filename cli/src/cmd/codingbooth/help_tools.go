// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.

package main

import "fmt"

func showHelpTools(command string) {
	script := scriptName()
	if command == "cp" {
		fmt.Printf(`%s cp — copy files and directories between host and booth.

USAGE:
  %s cp [options] SOURCE DESTINATION

Exactly one endpoint must be :PATH (selected booth) or NAME:PATH.
Container paths are relative to /; host paths are relative to the current directory.
The project is already shared at /home/coder/code; cp is useful outside that mount.

OPTIONS:
  --name NAME                    Select the booth for :PATH
  --code PATH                    Find the booth by its project directory
  --engine docker|podman|apple    Select the owning engine explicitly
  --                             Treat subsequent paths literally, even with '-'

EXAMPLES:
  %s cp ./settings.json :/tmp/settings.json
  %s cp worker:/tmp/results ./results
  %s cp --code ~/projects/app ./data/. :/tmp/data/

Files overwrite existing files; directories copy recursively using the engine's
native rules. Parent directories must exist. Ownership and symlink behavior follow
the engine: Docker copy-in defaults to root ownership. There is no automatic chown.
Prefix a local filename containing ':' with './'. Use --name for a one-letter
booth name because C:/path denotes a Windows host drive.

Docker and Podman also copy stopped booths and accept '-' for a tar stream.
Apple requires a running booth and a version providing 'container cp'; tar streams
are not supported there. Copying never creates or starts a booth.

See docs/BOOTH_TOOLS.md for persistence, ownership, and engine differences.
`, script, script, script, script, script)
		return
	}
	descriptions := map[string]string{
		"inspect": "show the booth's complete engine-native JSON inspection",
		"stats":   "stream the booth's resource usage",
		"top":     "show the booth's running processes",
		"diff":    "list added, changed, and deleted container filesystem paths",
		"wait":    "wait for the booth to stop and print its exit code",
	}
	fmt.Printf("%s %s — %s.\n\nUSAGE:\n  %s %s [name] [options]\n\n", script, command, descriptions[command], script, command)
	fmt.Println(`OPTIONS:
  --name NAME                    Select the booth by name instead of position
  --code PATH                    Find by project directory; with a name, verify it
  --engine docker|podman|apple    Select the owning engine explicitly

With no selector, use the booth named after the current directory.
Output and command failures are forwarded from the owning engine.`)
	switch command {
	case "inspect":
		fmt.Println("\n  --json             Native JSON (the default); schema depends on the engine\n  --format, -f TEXT  Engine-native formatting (Docker/Podman only)")
	case "stats":
		fmt.Println("\n  --no-stream        Print one sample and exit\n  --format TEXT      Engine-native formatting\n\nRequires a running booth. Ctrl+C ends the display without stopping the booth.")
	case "top":
		fmt.Println("\nArguments after '--' are native process-list options, e.g. '-- -eo pid,args'.\nRequires a running booth. Supported on Docker and Podman; unavailable on Apple.")
	case "diff":
		fmt.Println("\nReports A (added), C (changed), D (deleted) paths, not content diffs.\nSupported on Docker and Podman; unavailable on Apple.")
	case "wait":
		fmt.Println("\nPrints the container's exit code; the command itself succeeds if waiting succeeds.\nSupported on Docker and Podman; unavailable on Apple. Does not start the booth.")
	}
	fmt.Println("\nSee docs/BOOTH_TOOLS.md.")
}
