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
  --no-browser            Do not open the booth UI in a browser when it comes up
  --hide-welcome          Do not print the welcome banner in booth shells
  --dind                  Enable a Docker-in-Docker sidecar (privileged: asks first)
  --dind-allowed          Start a --dind booth without asking
  --privileged-allowed    Start a booth with --privileged-like run-args without asking
  --public                Bind to all interfaces with password authentication
  --ok-public             Required with --public if another port is already published
  --egress                Enable egress defaults (proxy + enforcement)
  --sudo <true|false>     Enable/disable sudo access (default: true)
  --no-sudo               Shorthand for --sudo false
  --rootless              Skip the Linux rootless/userns-remap refusal (unsupported)
  --engine <docker|podman|apple>
                          Container engine to use (default: apple, i.e. Apple
                          container, when installed and running; else docker;
                          else podman. podman and apple are experimental — see
                          docs/PODMAN_SUPPORT.md and docs/CONTAINER_SUPPORT.md)

EXAMPLES:
  %s --variant codeserver       Run the booth to use codeserver on localhost:<port>.
  %s --daemon --port RANDOM     Run the booth in daemon mode on a random port.
  %s -- 'mvn install'           Run 'mvn install' inside the booth.

OTHER COMMANDS:
  BUILD     | Build and publish booth images   | build                                                                   | docs/BOOTH_BUILD.md
  LIFECYCLE | Manage kept-alive booths         | list, start, stop, restart, remove, prune, logs                         | docs/BOOTH_LIFECYCLE.md
  HOME VOL  | Manage persisted home volumes    | home-volume-list, home-volume-export, home-volume-import [Experimental] | docs/BOOTH_HOME.md
  CONNECT   | Connect to a running booth       | shell, exec                                                             | docs/BOOTH_CONNECT.md
  MESSAGE   | Send messages into a booth       | message                                                                 | docs/BOOTH_MESSAGE.md
  EXPOSE    | Inspect a booth's ports          | expose list                                                             | docs/BOOTH_EXPOSE.md
  PROJECT   | Set up and scaffold new projects | example, config, template, showcase                                     | docs/BOOTH_EXAMPLE.md
  EXPRESS   | Run from arguments, ignoring the project's .booth | express                                                      | docs/BOOTH_RUN.md

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
  %s express [options] [-- command ...]        (run from arguments; ignore the project's .booth)
  %s [options] [--] [command ...]              (default action: run)
  %s list [--running|--stopped] [--name-only]  (list booth-managed containers)
  %s start [--name <n>|--code <path>] [-d]     (start a stopped keep-alive booth)
  %s stop [--name <n>] [-f] [--time <n>]       (stop a running booth)
  %s restart [--name <n>] [--time <n>]         (restart a running booth)
  %s remove [--name <n>] [--force]             (remove booth container(s))
  %s prune [--yes]                             (remove stopped booth containers)
  %s shell [--name <n>] [--shell <s>]          (open interactive shell in booth)
  %s exec [--name <n>] -- <command>            (run a command in a running booth)
  %s logs [--name <n>] [-f] [service ...]      (show a booth's output or service logs)
  %s expose list [--name <n>]                  (list a booth's published ports)
  %s example <subcommand>                      (manage examples)
  %s template <subcommand>                     (browse and manage templates)
  %s showcase <subcommand>                     (browse and import CodingBooths.online showcases)
  %s config [path] [options]                    (configure a new or existing .booth/ project)
  %s build [options]                            (build and optionally push image)
  %s emit-dockerfile [options]                 (compile Boothfile to Dockerfile)
  %s home-volume-list                          (list persisted home volumes)
  %s home-volume-export <name> <file>          (export home volume to tar.gz)
  %s home-volume-import <name> <file>          (import tar.gz into home volume)
  %s print-default-allowlist.txt               (print built-in egress allowlist)
  %s print-security-warning [options]          (print the run's security warning; exit 1 if any)

BOOTSTRAP OPTIONS (CLI or defaults; evaluated before env and config file):
  --code <path>          Host code path to mount at /home/coder/code
                         (default: current directory)
  --config <file>        Path to the config file to load
                         (default: <code>/.booth/config.toml)
  --profile <a[,b]>      Overlay .booth/<name>--config.toml and .booth/.<name>--env
                         on the base config; later wins. Repeatable. Also
                         BOOTH_PROFILES. Not combinable with --config/--env-file.
                         Lists add to the base; a conflicting -e/-v/-p/-l between
                         layers is an error, not an override.
                         (Value is the next argument; --profile=<a> is not read.)

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
  --silence-build        Hide build output; show a status line, log on failure
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
  --offset-base <n>      What a +OFFSET host port counts from (default: the booth
                         port, so published ports follow it). Use 0 to make every
                         +OFFSET an absolute port.
  --env-file <file>      Provide an --env-file to docker run
                         Use 'none' to disable env-file loading
                         .booth/.env is always included when present (must be gitignored)
  --startup <command>    Custom startup command to run inside the container

CONTAINER MODE:
  --daemon               Run the booth container in the background
  --public               Bind to all interfaces with password authentication.
                         Password read from .booth/.booth.password (chmod 600, gitignored),
                         or prompted interactively if not found.
  --ok-public            Required with --public when another port is already published
                         (e.g. a template's own +expose, or --expose at config time) --
                         that port has no password or TLS of its own, only the booth's does.
  --tls-cert <path>      TLS certificate file for HTTPS (used with --public)
  --tls-key <path>       TLS private key file for HTTPS (used with --public)
  --dind                 Enable a Docker-in-Docker sidecar and set DOCKER_HOST.
                         The sidecar is privileged, so booth asks before starting it.
  --dind-allowed         Start a --dind booth without asking. Command line only:
                         there is no config.toml key or environment variable for it.
  --privileged-allowed   Start without asking when run-args give the booth a way onto
                         the host (--privileged, --pid=host, a docker.sock mount, ...).
                         Command line only, like --dind-allowed.
  --rootless             Skip the Linux rootless/userns-remap refusal (unsupported).
                         macOS/Windows Docker Desktop and Linux rootful Docker are fine.
  --egress               Enable egress defaults (proxy + enforcement setup)
  --sudo <true|false>    Enable/disable sudo for the coder user (default: true).
                         When false, passwordless sudo is revoked after container setup.
                         Can also be set in config.toml: sudo = false
  --no-sudo              Shorthand for --sudo false
  --engine <docker|podman|apple>
                         Container engine to shell out to (default: apple,
                         i.e. Apple container on macOS, when installed and
                         running — except with --dind/--egress; else docker;
                         else podman). podman and apple are experimental and
                         may not have full Docker feature parity yet — see
                         docs/PODMAN_SUPPORT.md and docs/CONTAINER_SUPPORT.md.
                         Can also be set in config.toml (engine = "podman") or
                         CB_ENGINE.
  --keep-alive           Do not remove the container when stopped
  --hide-welcome         Do not print the welcome banner when a shell starts.
                         Can also be set in config.toml (hide-welcome = true)
                         or with CB_HIDE_WELCOME=true
  --vm-memory <size>     macOS / engine apple only: memory for the booth's VM
                         (Apple container's default is 1 GB; a desktop needs
                         more, e.g. 4g). Also vm-memory in config.toml or
                         CB_VM_MEMORY. Ignored on Docker and Podman.
  --vm-cpus <n>          macOS / engine apple only: CPUs for the booth's VM
                         (default 4). Also vm-cpus / CB_VM_CPUS.
  --vm-shm-size <size>   macOS / engine apple only: size of /dev/shm, out of
                         the VM's memory (desktops get 1g). Also vm-shm-size /
                         CB_VM_SHM_SIZE.
  --apple-low-ports      On engine apple, let coder open ports below 1024 (as
                         Docker allows by default; --public needs it there).
                         Grants only NET_BIND_SERVICE. Ignored on other
                         engines. Also: apple-low-ports = true in config.toml,
                         or CB_APPLE_LOW_PORTS=true
  --browser              Open the booth UI in your default browser once its port
                         answers. On by default; a booth given a command
                         (-- bash, or --variant terminal) serves no page and
                         never opens one.
                         Can also be set in config.toml (browser = false) or
                         with CB_BROWSER=false
  --no-browser           Shorthand for browser = false, for this run only
  --browser-port <spec>  Which port --browser opens, instead of the booth's own port:
                         n       : that absolute port
                         +OFFSET : offset-base + OFFSET (same arithmetic as a
                                   +OFFSET run-arg, e.g. -p +80:8080)
                         Default: the booth's own port. Can also be set in
                         config.toml (browser-port = "+80") or CB_BROWSER_PORT
  --quiet, -q            Hide lifecycle messages (implies --silence-build --no-browser)
  --persist-home         [Experimental] Persist /home/coder across sessions using a Docker named volume
  --writable-booth       Allow writing to .booth/ inside the container (read-only by default)
  --no-writable-booth    Force .booth/ to be read-only (overrides config.toml)
  --log-time             Prefix progress messages with timestamps
  --console-spec <mode>  Save the Console UI's layout/tabs to disk as they change:
                         "shared" to .booth/console.json (needs --writable-booth to
                         persist), "cache" to .booth/.tmp/console.json (always writable)

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
  - WARNING: the DinD sidecar runs privileged, so code in the booth can reach
    its daemon and use it to step outside the booth's isolation and touch the
    host. Only enable --dind for booths whose code you trust.
  - Before starting a booth that can reach the host as root (--dind, or run-args
    such as --privileged, --cap-add SYS_ADMIN, --pid=host, --device, a docker.sock
    mount, a writable mount of /etc or ~), booth lists what it found and asks.
    With no terminal it refuses unless --dind-allowed / --privileged-allowed is
    given. Rootless Podman does not ask (its root is your own account). See
    docs/BOOTH_SECURITY.md.
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
		s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s, s,
		s,
		s, s, s, s, s,
	)
}

func showHelpExpress() {
	s := scriptName()
	fmt.Printf(`%s express — run a booth from arguments, without the project's .booth.

USAGE:
  %s express [options] [-- command ...]

%s express mounts --code (default: the current directory) at /home/coder/code
and does not read or write that tree's .booth. Profiles, BOOTH_PROFILES, and
.booth/.env are ignored. --select is compiled the same way '%s config --no-tui'
compiles it, into a directory express owns, and that directory is mounted at
/home/coder/code/.booth. A foreground run uses a temporary directory, removed
when the process exits. --daemon and --keep-alive (and CB_DAEMON / CB_KEEP_ALIVE)
keep it under the user cache, because a later start re-reads the mounted spec.

With no --select, express starts the prebuilt variant from the arguments and
from CB_* variables. It does not write an empty Boothfile. --image, then
--dockerfile, then --boothfile, then --select, then the prebuilt variant.
--select cannot be combined with --image, --dockerfile, or --boothfile.

Launch flags override the generated file. CB_* variables still apply and lose
to flags. --version is the image tag. --apt-snapshot requires --select;
--templates-path without it is unused. Arguments after -- replace --cmd.

Refused: --config, --profile, --booth-dir, the --add-* / --remove-* config
edits, --overwrite, --beside, the config-only flags (--no-tui, --web, --start,
--full, --detail, --debug), and --writable-booth, --console-spec,
--leave-tmp-on-exit, --keep-tmp-on-start. --set of cache-files, cache-dirs,
shared-files, shared-dirs, and of keys run never reads from a file (public,
tls-cert, and the same family) is refused. Unknown tokens are forwarded to
docker run, as with %s run.

SPEC (compiled, not forwarded):
  --select <dsl>         Repeatable. Templates, :params, +extensions. '/' separates.
  --cmd <words>          Command argv. Repeatable. Shell-split. '--' replaces it.
  --expose <port>        Publish a port. Repeatable.
  --env <KEY=VALUE>      Environment entry. Repeatable.
  --mount <host:path>    Extra mount. Repeatable.
  --set <key[=value]>    A config.toml key run already reads from a file.
  --templates-path <dir> Local template catalog. Requires --select.
  --apt-snapshot <id>    id, today, or none. Requires --select.
                         Omitted with --select freezes apt to today.

IMAGE (first match wins; --select is refused alongside the first three):
  --image <ref>          Use this image. Skip the build.
  --dockerfile <path>    Build this Dockerfile.
  --boothfile <path>     Compile this Boothfile and build it.
  --variant <name>       Prebuilt variant when nothing above is set.
  --version <tag>        Image tag (default: this CLI's version). Not a catalog pin.
  --strict               Strict Boothfile parse.
  --build-arg <K=V>      Docker build-arg. Repeatable.
  --pull                 Pull the prebuilt image even when it exists.
  --silence-build        Do not print build output.

WHERE:
  --code <path>          Host directory mounted at /home/coder/code. Not read as a spec.
  --name <name>          Container name. {port}, {project}, and {variant} expand.
  --port <n|NEXT|RANDOM> Host port. NEXT and RANDOM accept :base.
  --offset-base <n>      Base for +OFFSET port mappings.
  --browser-port <n>     Port opened in the browser, when it is not the booth port.
  --engine <name>        docker, podman, or apple.
  --sudo <true|false>    sudo in the booth (default: true). --no-sudo is --sudo false.
  --hide-welcome         Do not print the welcome banner.
  --persist-home         Experimental home volume cb-home-<name>.

THIS LAUNCH:
  --daemon               Background. Refuses a command. Keeps the spec in the cache.
  --keep-alive           Leave the container after exit. Keeps the spec in the cache.
  --browser / --no-browser
  --quiet, -q            Quiet. Implies --silence-build and --no-browser.
  --dryrun               Print the docker command and exit.
  --verbose              Debug output.
  --log-time             Timestamp log lines.
  --idle-time <s>[,t]    Idle prompt, then shutdown.
  --idle-exit-code <n>   Exit code after an idle shutdown.
  --show-run-time [epoch]
  --show-count-down <epoch>
  --count-down-exit-code <n>
  --startup <path>       Run this startup file. Only the one given.
  --env-file <path|none> Extra env file, or none to skip it.
  --                     Command words. Joined and run with bash -lc.

HOST REACH:
  --dind / --dind-allowed / --privileged-allowed / --rootless / --egress
  --public / --ok-public / --tls-cert <file> / --tls-key <file>
  --vm-memory / --vm-cpus / --vm-shm-size / --apple-low-ports
                         Apple container only.

EXAMPLES:
  %s express --select 'go+vscode-ext' --variant codeserver --port 12000 --expose 8080 --env FOO=1
  %s express --variant base -- make test
  %s express --dryrun

See docs/BOOTH_RUN.md.
`, s, s, s, s, s, s, s, s)
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
  --profile <a[,b]>      Overlay <name>--config.toml / .<name>--env (or BOOTH_PROFILES)

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
  --silence-build        Hide build output; show a status line, log on failure

RUNTIME OPTIONS:
  --name <container>     Container name (default: inferred from code directory)
                         Supports {port} {project} {variant} placeholders
  --port <n|RANDOM|NEXT> Host port → container 10000 (NEXT/RANDOM accept :base)
  --offset-base <n>      Base for +OFFSET host ports (default: the booth port)
  --env-file <file>      Env-file for docker run (use 'none' to disable)
  --startup <command>    Custom startup command inside the container

CONTAINER MODE:
  --daemon               Run in background
  --public               Bind to all interfaces with password authentication
  --ok-public            Required with --public if another port is already published
  --tls-cert <path>      TLS certificate file (used with --public)
  --tls-key <path>       TLS private key file (used with --public)
  --dind                 Enable Docker-in-Docker sidecar (privileged: asks first)
  --dind-allowed         Start a --dind booth without asking (command line only)
  --privileged-allowed   Allow --privileged-like run-args without asking (command line only)
  --rootless             Skip the Linux rootless/userns-remap refusal (unsupported)
  --egress               Enable egress defaults
  --sudo <true|false>    Enable/disable sudo (default: true)
  --no-sudo              Shorthand for --sudo false
  --engine <docker|podman|apple>
                         Container engine to use (default: apple, i.e. Apple
                         container, when installed and running; else docker;
                         else podman. podman and apple are experimental — see
                         docs/PODMAN_SUPPORT.md and docs/CONTAINER_SUPPORT.md)
  --keep-alive           Do not remove container when stopped
  --hide-welcome         No welcome banner in shells (also: hide-welcome = true, CB_HIDE_WELCOME=true)
  --apple-low-ports      Engine apple only: let coder open ports below 1024 (also: apple-low-ports = true, CB_APPLE_LOW_PORTS=true)
  --vm-memory <size>     Engine apple only: memory for the booth's VM, default 1 GB (also: vm-memory, CB_VM_MEMORY)
  --vm-cpus <n>          Engine apple only: CPUs for the booth's VM, default 4 (also: vm-cpus, CB_VM_CPUS)
  --vm-shm-size <size>   Engine apple only: /dev/shm size, out of VM memory (also: vm-shm-size, CB_VM_SHM_SIZE)
  --browser              Open the booth UI in a browser once its port answers (default)
  --no-browser           Never open a browser (also: browser = false, CB_BROWSER=false)
  --browser-port <spec>  Which port --browser opens: n (absolute) or +OFFSET (from
                         offset-base), instead of the booth's own port
  --quiet, -q            Hide lifecycle messages (implies --silence-build --no-browser)
  --writable-booth       Allow writing to .booth/ inside the container
  --no-writable-booth    Force .booth/ to be read-only (overrides config.toml)
  --log-time             Prefix progress messages with timestamps
  --console-spec <mode>  Save the Console UI's layout/tabs to disk as they change:
                         "shared" to .booth/console.json (needs --writable-booth to
                         persist), "cache" to .booth/.tmp/console.json (always writable)

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
  --silence-build         Hide build output; show a status line, log on failure
  --verbose               Show detailed output
  --dryrun                Print docker commands without executing
  --engine <docker|podman|apple>
                          Container engine to use (default: apple, i.e. Apple
                          container, when installed and running; else docker;
                          else podman. podman and apple are experimental)

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
  --dind-allowed       With --run, start a --dind booth without asking
  --privileged-allowed
                       With --run, allow --privileged-like run-args without asking
  --silence-build, --quiet, -q
                       Hide --run bring-up and teardown
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
  %s shell --silence-build --run
`, s, s, s, s, s, s, s, s, s, s, s)
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
  --dind-allowed       With --run, start a --dind booth without asking
  --privileged-allowed
                       With --run, allow --privileged-like run-args without asking
  --silence-build, --quiet, -q
                       Hide --run bring-up and teardown; command output only
  -e <VAR=value>       Set environment variable (repeatable)
  --envfile <path>     Load environment variables from a file

The exit code of the executed command is forwarded to the caller. A booth
brought up by --run is stopped again when the command finishes, unless
--keep-alive is given. A booth that was already running is never stopped.
Create-intent flags like --port apply only when a booth is created; against an
existing booth a mismatch fails unless --accept-existing is set.

--silence-build (also --quiet / -q) hides the --run start/stop chatter and the
image build, leaving the command's output. A long first build still shows one
in-place progress line; a failed build still prints the log.

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
  %s exec --silence-build --run -- make test
  %s exec myproject --run --keep-alive -- make test
  %s exec myproject --run --port 9000 -- make test
  %s exec myproject --port 9000 --accept-existing -- make test
`, s, s, s, s, s, s, s, s, s, s, s)
}

func showHelpLogs() {
	s := scriptName()
	fmt.Printf(`%s logs — show a booth's output, or the logs of its services

USAGE:  %s logs [options]                 (the booth's container output)
        %s logs [options] <service> ...   (service log files in the booth's /tmp)
        %s logs --startup [options]       (the startup-hook log)
        %s logs --list                    (list the service log files)
        %s logs lifecycle [options]       (what happened to the booth, from the host)

OPTIONS:
  --name <n>           Booth name (default: the current folder's booth)
  --code <path>        Code path used to find the booth
  --follow, -f         Keep streaming new output
  --tail, -n <n|all>   Show only the last n lines (default: all)
  --startup            Show /tmp/startups.log (same as the service "startups")
  --list               List the *.log files in the booth's /tmp
  --since <time>       Container output only: since a timestamp or duration (10m)
  --until <time>       Container output only: before a timestamp or duration
  --timestamps, -t     Container output only: prefix each line with its time

With no service, this is '<engine> logs' for the booth: what its main process,
booth-entry and your .booth/startups/ scripts printed.

Most services log to files instead. A service name selects /tmp/<service>.log,
or, when there is none, every /tmp/<service>-*.log; several files are shown
with a '==> file <==' header each, as tail does. Positional arguments are
service names, so the booth is chosen with --name or --code.

A stopped (kept) booth works too: its output and its log files are read from
the stopped container (not on engine apple for log files). --follow then
prints what is there and returns.

The service "lifecycle" is what happened to the booth: started, told to stop
or restart (and by whom), idle prompts and timeouts, the session timer running
out, a console pane's terminal gone, and how the container exited. It is
.booth/.tmp/lifecycle.log in the code folder, on the host, kept across runs, so
it is there after the booth is gone: with no --name it reads the current
folder's, and --code <path> reads a removed booth's.

EXAMPLES:
  %s logs -f
  %s logs --name myproject --tail 100
  %s logs --startup
  %s logs --list
  %s logs excalidraw -f
  %s logs penpot
  %s logs lifecycle -n 20
`, s, s, s, s, s, s, s, s, s, s, s, s, s)
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

func showHelpPrintSecurityWarning() {
	s := scriptName()
	fmt.Printf(`%s print-security-warning — print the security warning a run would show

USAGE:  %s print-security-warning [options]

Takes the same options as '%s run' (including run-args such as -v or --network)
and reads the same .booth/config.toml, profiles, and templates, then prints the
settings that would let code in the booth reach the host — what each could lead
to, with a link to docs/BOOTH_SECURITY.md. Nothing is built or started and nothing
is asked.

--dind-allowed / --privileged-allowed do not change the result: it reports what the
booth would get, not whether you agreed to it.

EXIT STATUS:
  0  Prints "No security warning."
  1  Prints the warning (stdout)
  An options or config error is reported on stderr, as for a run.
`, s, s, s)
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
		case "express":
			showHelpExpress()
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
		case "logs":
			showHelpLogs()
		case "expose":
			showHelpExpose()
		case "emit-dockerfile":
			showHelpEmitDockerfile()
		case "print-security-warning":
			showHelpPrintSecurityWarning()
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
