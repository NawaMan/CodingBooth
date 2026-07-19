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
  --variant <name>        Prebuilt variant: base | notebook | codeserver | xfce | kde | lxqt | wayland
  --port <n|RANDOM|NEXT>  Host port → container 10000 (NEXT/RANDOM accept :base)
  --daemon                Run the booth in the background
  --dind                  Enable a Docker-in-Docker sidecar
  --public                Bind to all interfaces with password authentication
  --egress                Enable egress defaults (proxy + enforcement)
  --sudo <true|false>     Enable/disable sudo access (default: true)
  --no-sudo               Shorthand for --sudo false

EXAMPLES:
  %s --variant codeserver       Run the booth to use codeserver on localhost:<port>.
  %s --daemon --port RANDOM     Run the booth in daemon mode on a random port.
  %s -- 'mvn install'           Run 'mvn install' inside the booth.

OTHER COMMANDS:
  BUILD     | Build and publish booth images   | build                                                                   | docs/BOOTH_BUILD.md
  LIFECYCLE | Manage kept-alive booths         | list, start, stop, restart, remove, prune                               | docs/BOOTH_LIFECYCLE.md
  HOME VOL  | Manage persisted home volumes    | home-volume-list, home-volume-export, home-volume-import [Experimental] | docs/BOOTH_HOME.md
  CONNECT   | Connect to a running booth       | shell, exec                                                             | docs/BOOTH_CONNECT.md
  MESSAGE   | Send messages into a booth       | message                                                                 | docs/BOOTH_MESSAGE.md
  EXPOSE    | Inspect a booth's ports          | expose list                                                             | docs/BOOTH_EXPOSE.md
  PROJECT   | Set up and scaffold new projects | example, config, template                                               | docs/BOOTH_EXAMPLE.md

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
  %s shell [--name <n>] [--shell <s>]          (open interactive shell in booth)
  %s exec [--name <n>] -- <command>            (run a command in a running booth)
  %s expose list [--name <n>]                  (list a booth's published ports)
  %s example <subcommand>                      (manage examples)
  %s template <subcommand>                     (browse and manage templates)
  %s config [path] [options]                    (configure a new or existing .booth/ project)
  %s build [options]                            (build and optionally push image)
  %s emit-dockerfile [options]                 (compile Boothfile to Dockerfile)
  %s home-volume-list                          (list persisted home volumes)
  %s home-volume-export <name> <file>          (export home volume to tar.gz)
  %s home-volume-import <name> <file>          (import tar.gz into home volume)
  %s print-default-allowlist.txt               (print built-in egress allowlist)

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
                           base | notebook | codeserver | xfce | kde | lxqt | wayland
                         Aliases:
                           default | ide | desktop | desktop-xfce | desktop-kde | desktop-lxqt | desktop-wayland
  --version <tag>        Prebuilt version tag (default: latest)
  --strict               Treat Boothfile warnings as errors

BUILD OPTIONS (only when using --dockerfile):
  --build-arg <KEY=VAL>  Add a Docker build-arg (repeatable)
  --silence-build        Hide build progress; show output only on failure
  NOTE: Build args are ignored when using prebuilt images or --image.

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from code directory)
                         Placeholders expand after port selection:
                         {port} {project} {variant}
                         e.g. --port NEXT --name '{project}-{port}'
  --port <n|RANDOM|NEXT> Host port → container 10000
                         n           : any valid TCP port (1–65535)
                         RANDOM       : pick a random free port ≥ 10000
                         NEXT         : pick the next free port ≥ 10000
                         NEXT:<base>  : next free port ≥ base (e.g. NEXT:20000)
                         RANDOM:<base>: random free port ≥ base
  --env-file <file>      Provide an --env-file to docker run
                         Use 'none' to disable env-file loading
                         .booth/.env is always included when present (must be gitignored)
  --startup <command>    Custom startup command to run inside the container

CONTAINER MODE:
  --daemon               Run the booth container in the background
  --public               Bind to all interfaces with password authentication.
                         Password read from .booth/.booth.password (chmod 600, gitignored),
                         or prompted interactively if not found.
  --tls-cert <path>      TLS certificate file for HTTPS (used with --public)
  --tls-key <path>       TLS private key file for HTTPS (used with --public)
  --dind                 Enable a Docker-in-Docker sidecar and set DOCKER_HOST
  --egress               Enable egress defaults (proxy + enforcement setup)
  --sudo <true|false>    Enable/disable sudo for the coder user (default: true).
                         When false, passwordless sudo is revoked after container setup.
                         Can also be set in config.toml: sudo = false
  --no-sudo              Shorthand for --sudo false
  --keep-alive           Do not remove the container when stopped
  --persist-home         [Experimental] Persist /home/coder across sessions using a Docker named volume
  --writable-booth       Allow writing to .booth/ inside the container (read-only by default)
  --no-writable-booth    Force .booth/ to be read-only (overrides config.toml)
  --log-time             Prefix progress messages with timestamps

IDLE TIMEOUT:
  --idle-time <s>[,t]    Prompt after s seconds of idle; auto-shutdown after t seconds
                         (default t=60) if user does not respond
  --idle-exit-code <n>   Exit code when booth shuts down due to idle (default: 0)

COMMANDS:
  All arguments after '--' are executed *inside* the container instead of starting
  the default booth service. Example:
      %s -- bash -lc "echo hi"

NOTES:
  - The script checks if the image exists locally; if missing, it pulls automatically.
    Use --pull to always pull even if the image exists.
  - .booth/.env is always loaded when present (must be gitignored).
    Use '--env-file <file>' to pass additional env vars, or 'none' to disable.
  - In daemon mode, do not pass commands after '--'.
  - With --dind, a docker:dind sidecar runs on a private network and the main
    container uses DOCKER_HOST=tcp://<sidecar>:2375.
  - With --egress, booth enables egress policy defaults. If --dind is also set,
    the existing DinD sidecar network namespace is reused.

EXAMPLES:
  %s --variant base --version latest --code /path/to/code
  %s --dockerfile ./Dockerfile --code . --build-arg FOO=bar
  %s --daemon --variant codeserver --port RANDOM
  %s --image my/image:tag -- env | sort
  %s --env-file none --variant notebook
`,
		s, version,
		s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s,
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
  --variant <n>       Prebuilt variant: base | notebook | codeserver | xfce | kde | lxqt | wayland
  --version <tag>        Prebuilt version tag (default: latest)
  --strict               Treat Boothfile warnings as errors

BUILD OPTIONS (only with --dockerfile):
  --build-arg <KEY=VAL>  Add a Docker build-arg (repeatable)
  --silence-build        Hide build progress; show output only on failure

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from code directory)
                         Supports {port} {project} {variant} placeholders
  --port <n|RANDOM|NEXT> Host port → container 10000 (NEXT/RANDOM accept :base)
  --env-file <file>      Env-file for docker run (use 'none' to disable)
  --startup <command>    Custom startup command inside the container

CONTAINER MODE:
  --daemon               Run in background
  --public               Bind to all interfaces with password authentication
  --tls-cert <path>      TLS certificate file (used with --public)
  --tls-key <path>       TLS private key file (used with --public)
  --dind                 Enable Docker-in-Docker sidecar
  --egress               Enable egress defaults
  --sudo <true|false>    Enable/disable sudo (default: true)
  --no-sudo              Shorthand for --sudo false
  --keep-alive           Do not remove container when stopped
  --writable-booth       Allow writing to .booth/ inside the container
  --no-writable-booth    Force .booth/ to be read-only (overrides config.toml)
  --log-time             Prefix progress messages with timestamps

IDLE TIMEOUT:
  --idle-time <s>[,t]    Prompt after s seconds of idle; auto-shutdown after t seconds
                         (default t=60) if user does not respond
  --idle-exit-code <n>   Exit code when booth shuts down due to idle (default: 0)

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

func showHelpConfig() {
	s := scriptName()
	fmt.Printf(`%s config — configure a new or existing .booth/ project

USAGE:  %s config [path] [options]

Run '%s config help' for available options.
`, s, s, s)
}

func showHelpBuild() {
	s := scriptName()
	fmt.Printf(`%s build — build a booth image and optionally push to a registry

USAGE:  %s build [options]

OPTIONS:
  --push <registry>       Build and push to the given registry (e.g. ghcr.io/myteam)
  --name <name>           Image name (default: project name)
  --tag <tag>             Image tag (default: content hash, 24 hex chars)
  --build-arg <KEY=VAL>   Additional Docker build argument (repeatable)
  --code <path>           Project directory (default: current directory)
  --variant <variant>     Override variant from config
  --version <version>     Override CodingBooth version from config
  --silence-build         Hide build progress; show output only on failure
  --verbose               Show detailed output
  --dryrun                Print docker commands without executing

IMAGE NAMING:
  Local:   <name>:<tag>
  Push:    <registry>/<name>:<tag>

  When --tag is omitted, a 24-character SHA-256 hash is computed from the
  Boothfile content, build args, variant, and version. Same inputs always
  produce the same tag.

EXAMPLES:
  %s build                                        Build locally
  %s build --push ghcr.io/myteam                  Build and push
  %s build --push ghcr.io/myteam --name my-env --tag v1.0
  %s build --build-arg PYTHON_VERSION=3.13

AUTHENTICATION:
  Pushing requires prior 'docker login <registry>'. CodingBooth does not
  manage registry credentials.
`, s, s, s, s, s, s)
}

func showHelpShell() {
	s := scriptName()
	fmt.Printf(`%s shell — open an interactive shell in a running booth

USAGE:  %s shell [options] [name]

OPTIONS:
  --name <n>           Container name
  --shell <shell>      Shell to launch (default: bash)
  --dir <path>         Starting directory (default: /home/coder/code)
  --run                Run the booth first if it is not already running
  --keep-alive         With --run, leave the booth running afterwards
  --port <n|NEXT|RANDOM>
                       With --run, host port when creating a missing booth
  --accept-existing    Connect even if create flags (e.g. --port) do not match
  -e <VAR=value>       Set environment variable (repeatable)
  --envfile <path>     Load environment variables from a file

A booth brought up by --run is stopped again when you disconnect, unless
--keep-alive is given. A booth that was already running is never stopped.
Create-intent flags like --port apply only when a booth is created; against an
existing booth a mismatch fails unless --accept-existing is set.

EXAMPLES:
  %s shell myproject
  %s shell myproject --shell zsh
  %s shell myproject --dir /tmp
  %s shell myproject -e DEBUG=1
  %s shell myproject --run
  %s shell myproject --run --keep-alive
  %s shell myproject --run --port 9000
  %s shell myproject --port 9000 --accept-existing
`, s, s, s, s, s, s, s, s, s, s)
}

func showHelpExec() {
	s := scriptName()
	fmt.Printf(`%s exec — run a command in a running booth

USAGE:  %s exec [options] [name] -- <command>

OPTIONS:
  --name <n>           Container name
  --dir <path>         Working directory (default: /home/coder/code)
  -it                  Force interactive mode with TTY
  --daemon, -d         Run the command detached and return immediately
  --run                Run the booth first if it is not already running
  --keep-alive         With --run, leave the booth running afterwards
  --port <n|NEXT|RANDOM>
                       With --run, host port when creating a missing booth
  --accept-existing    Connect even if create flags (e.g. --port) do not match
  -e <VAR=value>       Set environment variable (repeatable)
  --envfile <path>     Load environment variables from a file

The exit code of the executed command is forwarded to the caller. A booth
brought up by --run is stopped again when the command finishes, unless
--keep-alive is given. A booth that was already running is never stopped.
Create-intent flags like --port apply only when a booth is created; against an
existing booth a mismatch fails unless --accept-existing is set.

--daemon starts the command in the background and returns at once: nothing is
streamed back and the command's exit code is not forwarded (exec exits 0 if the
command was started). Redirect output inside the container to keep it. It cannot
be combined with -it, and with --run it requires --keep-alive — otherwise the
booth would be stopped on return, killing the detached command.

EXAMPLES:
  %s exec myproject -- make test
  %s exec myproject -e FOO=bar -- env
  %s exec myproject --dir /tmp -- ls
  %s exec myproject --daemon -- bash -c './server >/tmp/server.log 2>&1'
  %s exec myproject --run -- make test
  %s exec myproject --run --keep-alive -- make test
  %s exec myproject --run --port 9000 -- make test
  %s exec myproject --port 9000 --accept-existing -- make test
`, s, s, s, s, s, s, s, s, s, s)
}

func showHelpExpose() {
	s := scriptName()
	fmt.Printf(`%s expose — inspect the ports a booth publishes

USAGE:  %s expose list [name] [--name <n>]

Lists, for a running booth, the ports reachable from the host: the booth front
door, any published (-p) ports, and any runtime tunnels opened with
booth--expose. Each row shows the container port, the host binding, its kind,
and whether it is actually bound (confirmed against 'docker port'). With no
name, the booth for the current directory is used.

The source of truth is the run-time manifest .booth/.tmp/ports.json; when it is
absent (e.g. an older booth), the live 'docker port' view is used instead.

Inside a booth, 'booth--expose list' shows the same ports plus which process is
listening on each — including internal-only services that are not published.

EXAMPLES:
  %s expose list
  %s expose list demo
  %s expose list --name demo
`, s, s, s, s, s)
}

func showHelpEmitDockerfile() {
	s := scriptName()
	fmt.Printf(`%s emit-dockerfile — compile Boothfile to Dockerfile

USAGE:  %s emit-dockerfile [options]

Reads a Boothfile and outputs the compiled Dockerfile to stdout.
Use --strict to treat warnings as errors.
`, s, s)
}

func showHelpListHomeVolume() {
	s := scriptName()
	fmt.Printf(`%s home-volume-list — list persisted home volumes

USAGE:  %s home-volume-list

Lists all Docker volumes created by --persist-home.
`, s, s)
}

func showHelpExportHomeVolume() {
	s := scriptName()
	fmt.Printf(`%s home-volume-export — export a home volume to a tar.gz file

USAGE:  %s home-volume-export <container-name> <output-file>

Exports the persisted home volume for a booth to a compressed tar file.
The volume must exist (booth must have been run with --persist-home).

Note: home volumes can be large (1-3GB+ depending on usage).
`, s, s)
}

func showHelpImportHomeVolume() {
	s := scriptName()
	fmt.Printf(`%s home-volume-import — import a tar.gz file into a home volume

USAGE:  %s home-volume-import <container-name> <input-file>

Imports a compressed tar file into the home volume for a booth.
Creates the volume if it does not exist.
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
		case "config":
			showHelpConfig()
		case "build":
			showHelpBuild()
		case "shell":
			showHelpShell()
		case "exec":
			showHelpExec()
		case "expose":
			showHelpExpose()
		case "emit-dockerfile":
			showHelpEmitDockerfile()
		case "home-volume-list":
			showHelpListHomeVolume()
		case "home-volume-export":
			showHelpExportHomeVolume()
		case "home-volume-import":
			showHelpImportHomeVolume()
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
