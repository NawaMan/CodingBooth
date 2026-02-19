// Copyright 2025-2026 : Nawa Manusitthipol
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
package main

import (
	"fmt"
	"os"
	"path/filepath"
)

func scriptName() string {
	name := "codingbooth"
	if len(os.Args) > 0 && os.Args[0] != "" {
		name = filepath.Base(os.Args[0])
	}
	return name
}

// ---------------------------------------------------------------------------
// Top-level help (default) — run-focused
// ---------------------------------------------------------------------------

func showHelp(version string) {
	s := scriptName()
	fmt.Printf(`%s %s — launch a Docker-based development booth.

USAGE:
  %s [options]                    Run the current booth.
  %s [options] [-- command ...]   Run the command inside the current booth.

OPTIONS
  --build-arg <KEY=VAL>   Add a Docker build-arg which customize the booth image.
  --variant <name>        Prebuilt variant: base | notebook | codeserver | xfce | kde
  --port <n|RANDOM|NEXT>  Host port → container 10000
  --daemon                Run the booth in the background
  --dind                  Enable a Docker-in-Docker sidecar
  --public                Bind to all interfaces with password authentication
  --sandboxed             Enable sandbox defaults (proxy + enforcement)

EXAMPLES:
  %s --variant codeserver       Run the booth to use codeserver on localhost:<port>.
  %s --daemon --port RANDOM     Run the booth in daemon mode on a random port.
  %s -- 'mvn install'           Run 'mvn install' inside the booth.

OTHER COMMANDS:
  LIFECYCLE | Manage kept-alive booths         | list, start, stop, restart, remove, prune
  PROJECT   | Set up and scaffold new projects | example, init, template

Run '%s --help <command>'   for command-specific help.
Run '%s --help --detail'    for the full reference.
`, s, version, s, s, s, s, s, s, s)
}

// ---------------------------------------------------------------------------
// Full reference (help --detail)
// ---------------------------------------------------------------------------

func showHelpDetail(version string) {
	s := scriptName()
	fmt.Printf(`%s — launch a Docker-based development booth (version %s)

USAGE:
  %s version                                   (print the CodingBooth version)
  %s help                                      (show this help and exit)
  %s run [options] [--] [command ...]          (run the booth)
  %s [options] [--] [command ...]              (default action: run)
  %s list [--running|--stopped] [--name-only]  (list booth-managed containers)
  %s start [--name <n>|--code <path>] [-d]     (start a stopped keep-alive booth)
  %s stop [--name <n>] [-f] [--time <n>]       (stop a running booth)
  %s restart [--name <n>] [--time <n>]         (restart a running booth)
  %s remove [--name <n>] [--force]             (remove booth container(s))
  %s prune [--yes]                             (remove stopped booth containers)
  %s example <subcommand>                      (manage examples)
  %s template <subcommand>                     (browse and manage templates)
  %s init <subcommand> [options]               (initialize a new .booth/ project)
  %s emit-dockerfile [options]                 (compile Boothfile to Dockerfile)
  %s print-default-allowlist.txt               (print built-in sandbox allowlist)

BOOTSTRAP OPTIONS (CLI or defaults; evaluated before env and config file):
  --code <path>          Host code path to mount at /home/coder/code
                         (default: current directory)
  --config <file>        Path to the config file to load
                         (default: <code>/.booth/config.toml)

CONFIG PRECEDENCE:
  options (CLI) > config file (TOML) > environment (ENV) > defaults
  NOTE: --code and --config are bootstrap options and are taken only from
        CLI (first pass) or defaults.

GENERAL RUN OPTIONS:
  --dryrun               Print docker commands without executing them
  --verbose              Print extra debugging information

IMAGE SELECTION (precedence: --image > --dockerfile > --boothfile > prebuilt):
  --boothfile <path>     Build from a Boothfile (compiled to Dockerfile)
                         Auto-detected at .booth/Boothfile if present.
  --dockerfile <path>    Build locally from a Dockerfile (file or directory)
                         If a directory is provided, it looks for .booth/Dockerfile.
  --image <n>         Use an existing local or remote image (e.g. repo/name:tag)
                         The script checks if the image exists locally and pulls it
                         only if it is missing (unless --pull is used).
  --pull                 Always pull the image, even if it exists locally
                         (default: pull only if the image is missing)
  --variant <n>       Prebuilt variant (examples):
                           base | notebook | codeserver | xfce | kde
                         Aliases:
                           default | ide | desktop | desktop-xfce | desktop-kde
  --version <tag>        Prebuilt version tag (default: latest)
  --strict               Treat Boothfile warnings as errors

BUILD OPTIONS (only when using --dockerfile):
  --build-arg <KEY=VAL>  Add a Docker build-arg (repeatable)
  --silence-build        Hide build progress; show output only on failure
  NOTE: Build args are ignored when using prebuilt images or --image.

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from code directory)
  --port <n|RANDOM|NEXT> Host port → container 10000
                         n      : any valid TCP port (1–65535)
                         RANDOM : pick a random free port ≥ 10000
                         NEXT   : pick the next available free port ≥ 10000
  --env-file <file>      Provide an --env-file to docker run
                         Use 'none' to disable auto-detection of <code>/.env
                         .booth/.env-local is always included when present (must be gitignored)
  --startup <command>    Custom startup command to run inside the container

CONTAINER MODE:
  --daemon               Run the booth container in the background
  --public               Bind to all interfaces with password authentication.
                         Password read from .booth/.booth.password (chmod 600, gitignored),
                         or prompted interactively if not found.
  --tls-cert <path>      TLS certificate file for HTTPS (used with --public)
  --tls-key <path>       TLS private key file for HTTPS (used with --public)
  --dind                 Enable a Docker-in-Docker sidecar and set DOCKER_HOST
  --sandboxed            Enable sandbox defaults (proxy + enforcement setup)
  --keep-alive           Do not remove the container when stopped
  --writable-booth       Allow writing to .booth/ inside the container (read-only by default)
  --web-split            Base variant: force-enable browser split-terminal UI at port 10000 (default)

COMMANDS:
  All arguments after '--' are executed *inside* the container instead of starting
  the default booth service. Example:
      %s -- bash -lc "echo hi"

NOTES:
  - The script checks if the image exists locally; if missing, it pulls automatically.
    Use --pull to always pull even if the image exists.
  - If --env-file is not provided, <code>/.env is used when present.
    Use '--env-file none' to disable. .booth/.env-local is always loaded when present.
  - In daemon mode, do not pass commands after '--'.
  - With --dind, a docker:dind sidecar runs on a private network and the main
    container uses DOCKER_HOST=tcp://<sidecar>:2375.
  - With --sandboxed, booth enables sandbox policy defaults. If --dind is also set,
    the existing DinD sidecar network namespace is reused.

EXAMPLES:
  %s --variant base --version latest --code /path/to/code
  %s --dockerfile ./Dockerfile --code . --build-arg FOO=bar
  %s --daemon --variant codeserver --port RANDOM
  %s --image my/image:tag -- env | sort
  %s --env-file none --variant notebook
`,
		s, version,
		s, s, s, s, s, s, s, s, s, s, s, s, s, s, s,
		s,
		s, s, s, s, s,
	)
}

// ---------------------------------------------------------------------------
// Per-subcommand help
// ---------------------------------------------------------------------------

func showHelpRun(version string) {
	s := scriptName()
	fmt.Printf(`%s run — launch a booth container (version %s)

USAGE:
  %s run [options] [--] [command ...]
  %s [options] [--] [command ...]       (run is the default action)

BOOTSTRAP OPTIONS:
  --code <path>          Host code path (default: current directory)
  --config <file>        Config file (default: <code>/.booth/config.toml)

  Config precedence: CLI > config file (TOML) > environment (ENV) > defaults

GENERAL:
  --dryrun               Print docker commands without executing them
  --verbose              Print extra debugging information

IMAGE SELECTION (precedence: --image > --dockerfile > --boothfile > prebuilt):
  --boothfile <path>     Build from a Boothfile (auto-detected at .booth/Boothfile)
  --dockerfile <path>    Build from a Dockerfile (file or directory)
  --image <n>         Use an existing image (e.g. repo/name:tag)
  --pull                 Always pull the image even if it exists locally
  --variant <n>       Prebuilt variant: base | notebook | codeserver | xfce | kde
  --version <tag>        Prebuilt version tag (default: latest)
  --strict               Treat Boothfile warnings as errors

BUILD OPTIONS (only with --dockerfile):
  --build-arg <KEY=VAL>  Add a Docker build-arg (repeatable)
  --silence-build        Hide build progress; show output only on failure

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from code directory)
  --port <n|RANDOM|NEXT> Host port → container 10000
  --env-file <file>      Env-file for docker run (use 'none' to disable auto-detection)
  --startup <command>    Custom startup command inside the container

CONTAINER MODE:
  --daemon               Run in background
  --public               Bind to all interfaces with password authentication
  --tls-cert <path>      TLS certificate file (used with --public)
  --tls-key <path>       TLS private key file (used with --public)
  --dind                 Enable Docker-in-Docker sidecar
  --sandboxed            Enable sandbox defaults
  --keep-alive           Do not remove container when stopped
  --writable-booth       Allow writing to .booth/ inside the container
  --web-split            Force-enable browser split-terminal UI (base variant)

COMMANDS:
  Arguments after '--' run inside the container instead of the default service.

EXAMPLES:
  %s --code .
  %s --variant codeserver --code /my/project
  %s --daemon --port RANDOM
  %s -- bash -lc "echo hi"

Run '%s help --detail' for the full reference.
`, s, version, s, s, s, s, s, s, s)
}

func showHelpList() {
	s := scriptName()
	fmt.Printf(`%s list — list booth-managed containers

USAGE:  %s list [options]

OPTIONS:
  --running       Show only running containers
  --stopped       Show only stopped containers
  --name-only     Print container names only (useful for scripting)
`, s, s)
}

func showHelpStart() {
	s := scriptName()
	fmt.Printf(`%s start — start a stopped keep-alive booth

USAGE:  %s start [options]

OPTIONS:
  --name <n>      Container name to start
  --code <path>   Identify the container by its code path
  -d              Start in detached/daemon mode
`, s, s)
}

func showHelpStop() {
	s := scriptName()
	fmt.Printf(`%s stop — stop a running booth

USAGE:  %s stop [options]

OPTIONS:
  --name <n>      Container name to stop
  -f              Force stop (SIGKILL)
  --time <n>      Seconds to wait before force-killing (default: 10)
`, s, s)
}

func showHelpRestart() {
	s := scriptName()
	fmt.Printf(`%s restart — restart a running booth

USAGE:  %s restart [options]

OPTIONS:
  --name <n>      Container name to restart
  --time <n>      Seconds to wait before force-killing (default: 10)
`, s, s)
}

func showHelpRemove() {
	s := scriptName()
	fmt.Printf(`%s remove — remove booth container(s)

USAGE:  %s remove [options]

OPTIONS:
  --name <n>      Container name to remove
  --force         Force-remove even if running
`, s, s)
}

func showHelpPrune() {
	s := scriptName()
	fmt.Printf(`%s prune — remove stopped booth containers

USAGE:  %s prune [options]

OPTIONS:
  --yes           Skip confirmation prompt
`, s, s)
}

func showHelpExample() {
	s := scriptName()
	fmt.Printf(`%s example — manage examples

USAGE:  %s example <subcommand>

Run '%s example help' for available subcommands.
`, s, s, s)
}

func showHelpTemplate() {
	s := scriptName()
	fmt.Printf(`%s template — browse and manage templates

USAGE:  %s template <subcommand>

Run '%s template help' for available subcommands.
`, s, s, s)
}

func showHelpInit() {
	s := scriptName()
	fmt.Printf(`%s init — initialize a new .booth/ project

USAGE:  %s init <subcommand> [options]

Run '%s init help' for available subcommands.
`, s, s, s)
}

func showHelpEmitDockerfile() {
	s := scriptName()
	fmt.Printf(`%s emit-dockerfile — compile Boothfile to Dockerfile

USAGE:  %s emit-dockerfile [options]

Reads a Boothfile and outputs the compiled Dockerfile to stdout.
Use --strict to treat warnings as errors.
`, s, s)
}

// ---------------------------------------------------------------------------
// Help dispatcher
// ---------------------------------------------------------------------------

// dispatchHelp routes "help", "help <command>", or "help --detail".
func dispatchHelp(args []string, version string) {
	// help --detail  →  full reference
	for _, a := range args {
		if a == "--detail" {
			showHelpDetail(version)
			return
		}
	}

	// help <subcommand>
	for _, a := range args {
		if a == "" || a[0] == '-' {
			continue
		}
		switch a {
		case "run":
			showHelpRun(version)
		case "list":
			showHelpList()
		case "start":
			showHelpStart()
		case "stop":
			showHelpStop()
		case "restart":
			showHelpRestart()
		case "remove":
			showHelpRemove()
		case "prune":
			showHelpPrune()
		case "example":
			showHelpExample()
		case "template":
			showHelpTemplate()
		case "init":
			showHelpInit()
		case "emit-dockerfile":
			showHelpEmitDockerfile()
		default:
			fmt.Fprintf(os.Stderr, "Unknown command: %s\nRun '%s help' for usage.\n",
				a, scriptName())
			os.Exit(1)
		}
		return
	}

	// bare "help"
	showHelp(version)
}
