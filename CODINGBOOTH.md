# CodingBooth User Manual

**Current Version:** v0.50.0--rc1 — [View Changelog](docs/CHANGELOG.md)

This manual is the comprehensive feature reference for **CodingBooth** — a tool that delivers fully reproducible, isolated development environments. Everything `booth` can do is documented here, organized for the user's perspective: install, scaffold, run, customize, observe, and clean up.

For a marketing-oriented overview, see the [README](README.md).
For deep architecture details, see [docs/implementations/](docs/implementations/).

---

## What Is CodingBooth?

CodingBooth runs a browser-based VS Code workspace, a Jupyter notebook, a full Linux desktop, or a plain shell — all inside a Docker container with **your host UID and GID**. Files you create or edit inside the booth are owned by you on the host. The whole environment travels with the project as a `.booth/` folder, so anyone running `booth` against the same repo gets the same setup.

Everything you do with CodingBooth flows through one command — the `booth` script — which is a **wrapper** that fetches and pins a Go binary called `codingbooth`. The wrapper handles distribution; the binary handles orchestration; the variants (Docker images) provide the UI.

```
host                                                container
  booth (wrapper, shell)  ──fetches──▶  codingbooth (binary, Go)  ──launches──▶  variant image
```


## Support and Requirements

### Supported platforms
- Linux, macOS, Windows
- x86 64-bit, ARM 64-bit

### Requirements
- Docker
- Bash
- curl


# Table of Contents

- [Installation](#installation)
- [Quick Try](#quick-try)
- [Variants](#variants)
- [Running Booths](#running-booths)
- [Common Flags](#common-flags)
- [Command Passthrough](#command-passthrough)
- [Configuration Inputs](#configuration-inputs)
- [Environment Variables](#environment-variables)
- [Mounts and Ports](#mounts-and-ports)
- [Run Modes](#run-modes)
- [Persistent Home](#persistent-home)
- [Local Cache](#local-cache)
- [Container Lifecycle](#container-lifecycle)
- [Session Timers](#session-timers)
- [Idle Auto-Shutdown](#idle-auto-shutdown)
- [Connecting to Booths](#connecting-to-booths)
- [Messaging](#messaging)
- [Building Images](#building-images)
- [Scaffolding Projects](#scaffolding-projects)
- [The `.booth/` Folder](#the-booth-folder)
- [Built-in Tools](#built-in-tools)
- [Setup Layer](#setup-layer)
- [In-Container Helpers](#in-container-helpers)
- [In-Container Daemons](#in-container-daemons)
- [Web UI](#web-ui)
- [Wrapper Tooling](#wrapper-tooling)
- [How It Works](#how-it-works)
- [Troubleshooting](#troubleshooting)
- [Contributor Tooling](#contributor-tooling)
- [Guidance & Limitations](#guidance--limitations)
- [Community & Feedback](#community--feedback)


## Installation

### One-liner install

```bash
curl -fsSL https://raw.githubusercontent.com/NawaMan/CodingBooth/main/install.sh | bash
```

This drops the **wrapper script** (`booth`) in the current directory, downloads the matching `codingbooth` binary, and configures your shell so `booth` can be invoked from anywhere inside the project.

> The `booth` script operates relative to its own location, not the current working directory — so `/path/to/project/booth` works from anywhere.

### Wrapper subcommands

| Command                      | What it does                                                         |
|------------------------------|----------------------------------------------------------------------|
| `booth install [version]`    | Download the `codingbooth` binary (positional version argument)      |
| `booth update [version]`     | Re-download to latest, or to a specific version                      |
| `booth uninstall`            | Remove project lock file and locally-cached binaries                 |
| `booth tools-cache list`     | Inspect the shared binary cache                                      |
| `booth tools-cache clean [--all\|VERSION]` | Prune the shared binary cache                          |

### Cache layout

Binaries are cached either **shared** (per-user) or **local** (per-project), selected at install time via `--cache=shared|local`:

| Mode     | Location                                                                   |
|----------|----------------------------------------------------------------------------|
| `shared` | `~/.cache/codingbooth/` (Linux) · `~/Library/Caches/...` (macOS) · `%LOCALAPPDATA%\...` (Windows) |
| `local`  | `.booth/tools/` (in the project)                                           |

The chosen cache is recorded in `.booth/tools/codingbooth.lock` (`version=`, `downloaded_at=`, `cache=`). The lock file is **version-controlled** — it pins the binary so all collaborators run the same version.

### Pre-exec integrity gauntlet

Every time you run `booth <something>` that forwards to the binary, the wrapper:

1. Reads the lock file
2. Detects platform (Linux/macOS/Windows × amd64/arm64)
3. Locates the binary in the chosen cache
4. Auto-downloads if missing
5. Verifies SHA256 against the published `codingbooth.sha256`
6. Maintains a `booth` → `codingbooth-<platform>` symlink
7. `exec`s the binary with your original argv

Subcommands handled entirely by the wrapper (`help`, `version`, `install`, `update`, `uninstall`, `tools-cache`) skip the gauntlet — they work without network access.

For more, see **[Wrapper implementation](docs/implementations/WRAPPER.md)**.


## Quick Try

### Try with an example

```bash
booth example list                    # list ~45 workspaces
booth example try <name> <folder>     # copy into <folder>
cd <folder>
booth                                 # start it
```

Visit http://localhost:10000 in your browser to access the UI. See **[booth example](docs/BOOTH_EXAMPLE.md)**.

### Try with `booth config`

```bash
booth template list           # list 77+ templates
booth config                  # interactive TUI
# or:
booth config --no-tui --select java+maven+m2/scala --select claude-code+auto-accept
booth                         # start the booth
```

See **[booth config](docs/BOOTH_CONFIG.md)** and **[Scaffolding Projects](#scaffolding-projects)** below.


## Variants

CodingBooth supports multiple **variants** — different UIs that share the same underlying environment. The variant is selected with `--variant <name>`.

| Variant         | Description                                                              |
|-----------------|--------------------------------------------------------------------------|
| `base`          | Minimal terminal session in the browser                                  |
| `notebook`      | Jupyter Lab with multi-language kernels (Python, Bash, Java, ...)        |
| `codeserver`    | VS Code in your browser with full extension support                      |
| `desktop-xfce`  | Full XFCE Linux desktop accessible via the browser                       |
| `desktop-kde`   | KDE Plasma desktop in the browser                                        |
| `terminal`      | Direct bash session in your host terminal — alias for `booth -- bash`    |
| (passthrough)   | Skip the UI entirely. `booth -- <command>` runs the command and exits    |

Friendly init-phase error messages are surfaced when a variant fails to start.

For aliases, desktop configuration, and clipboard details, see **[Variants Guide](docs/BOOTH_VARIANTS.md)**.

### Example screenshots

| Base                                                                          | Terminal                                                                             |
|:-----------------------------------------------------------------------------:|:------------------------------------------------------------------------------------:|
| [![Base](docs/images/Booth-Base.png)](docs/images/Booth-Base.png)             | [![Terminal](docs/images/Booth-Bash.png)](docs/images/Booth-Bash.png)                |
| `booth --variant base`                                                        | `booth --variant terminal`                                                           |

| Notebook                                                                      | Code Server                                                                          |
|:-----------------------------------------------------------------------------:|:------------------------------------------------------------------------------------:|
| [![Notebook](docs/images/Booth-NoteBook.png)](docs/images/Booth-NoteBook.png) | [![Code Server](docs/images/Booth-CodeServer.png)](docs/images/Booth-CodeServer.png) |
| `booth --variant notebook`                                                    | `booth --variant codeserver`                                                         |

| XFCE Desktop                                                                  | KDE Desktop                                                                          |
|:-----------------------------------------------------------------------------:|:------------------------------------------------------------------------------------:|
| [![XFCE](docs/images/Booth-XFCE.png)](docs/images/Booth-XFCE.png)             | [![KDE](docs/images/Booth-KDE.png)](docs/images/Booth-KDE.png)                       |
| `booth --variant desktop-xfce`                                                | `booth --variant desktop-kde`                                                        |


## Running Booths

`booth run` (or just `booth`) is the default verb. It launches a container, mounts your project into `/home/coder/code`, and starts the chosen variant.

Three modes:

| Mode             | Invocation                | Behavior                                              |
|------------------|---------------------------|-------------------------------------------------------|
| **Foreground**   | `booth`                   | Run in the current terminal; logs stream live         |
| **Daemon**       | `booth --daemon`          | Run in the background                                 |
| **Command**      | `booth -- <cmd>`          | Run a single command, forward exit code, exit         |

`--keep-alive` preserves the container after exit so you can resume with `booth start <name>`.
Exit codes from the in-container command are **forwarded** — `booth -- false` exits 1.

For the full run reference (image selection, config files, run modes, ports, DinD, TLS), see **[booth run](docs/BOOTH_RUN.md)**.


## Common Flags

```shell
booth [flags] [-- command...]
```

| Flag                            | Description                                                                  |
|---------------------------------|------------------------------------------------------------------------------|
| `--variant <name>`              | Select container variant                                                     |
| `--port <port>`                 | Host port mapping (number, `NEXT`, or `RANDOM`)                              |
| `--name <name>`                 | Set container name                                                           |
| `--build-arg <arg>`             | Pass a build argument to Docker                                              |
| `-v <host:container>`           | Bind mount a file or folder into the container                               |
| `--`                            | Separator: everything after runs as a command inside the container           |
| `--dind`                        | Enable Docker-in-Docker mode                                                 |
| `--sandboxed`                   | Restrict outbound network to allowlisted domains                             |
| `--keep-alive`                  | Preserve container after exit (resume with `booth start <name>`)             |
| `--persist-home`                | Persist `/home/coder` across sessions using a Docker named volume            |
| `--writable-booth`              | Allow writing to `.booth/` inside the container (read-only by default)       |
| `--daemon`                      | Run container in background                                                  |
| `--silence-build`               | Suppress build/startup output                                                |
| `--show-run-time [epoch]`       | Display elapsed session time ([details](docs/BOOTH_RUNTIME.md))              |
| `--show-count-down <epoch>`     | Display countdown timer to a deadline ([details](docs/BOOTH_RUNTIME.md))     |
| `--count-down-exit-code <code>` | Exit code when countdown expires (default: 0)                                |
| `--idle-time <s>[,t]`           | Auto-shutdown after `s` seconds idle, with `t` seconds warning               |
| `--idle-exit-code <code>`       | Exit code when idle shutdown fires                                           |
| `--log-time`                    | Prefix progress messages with timestamps (HH:MM:SS) — also `CB_LOG_TIME`     |
| `--leave-tmp-on-exit`           | Preserve `.booth/.tmp/` contents on exit for debugging                       |
| `--keep-tmp-on-start`           | Preserve `.booth/.tmp/` from previous session on start                       |
| `--env-file <path>`             | Load env vars from file (use `-` to disable auto-loading of `.booth/.env`)   |
| `--dryrun`                      | Print docker commands without executing                                      |
| `--verbose`                     | Verbose debug output                                                         |

Additional Docker pass-through flags (`-e`, `-p`, etc.) can be set via `run-args` in `.booth/config.toml`.

### Wrapper vs Binary help

The `booth` script is a wrapper around the `codingbooth` binary; each has its own help:

| Command           | What it shows                               |
|-------------------|---------------------------------------------|
| `booth help`      | Wrapper help (install, update, cache, ...)  |
| `booth --help`    | Binary help (run flags, variants, ...)      |
| `booth version`   | Wrapper + binary version info               |
| `booth --version` | Binary version only                         |


## Command Passthrough

Use `--` to run commands inside the container and exit:

```shell
booth -- make test
booth -- echo "Hello from container"
booth -- python -c "print('hello')"
```

Exit codes are forwarded. Combine with `--silence-build` for clean scripted output:

```shell
> booth --silence-build -- echo "Hello"
Hello
```


## Configuration Inputs

`booth run` resolves configuration from four sources, in increasing precedence:

1. **Defaults**
2. **Environment variables** (`CB_*`)
3. **`.booth/config.toml`**
4. **CLI flags**

CLI always wins. The TUI (`booth config`) reads/writes `config.toml`. Templates (`--select ...`) emit values into `config.toml`, the Boothfile, startup scripts, and home seeding — see [Scaffolding Projects](#scaffolding-projects).

The binary tags every container it manages with these Docker labels:

| Label         | Meaning                              |
|---------------|--------------------------------------|
| `cb.managed`  | Marks the container as ours          |
| `cb.project`  | Project identity                     |
| `cb.variant`  | The variant in use                   |
| `cb.role`     | Main / sidecar / DinD                |
| `cb.parent`   | Parent booth (for booth-in-booth)    |


## Environment Variables

Variables that land inside the running booth as regular `$FOO` come from three sources, layered in this order (later overrides earlier):

1. **`.booth/.env`** — auto-loaded if present.
   **Gitignore-enforced:** booth runs `git check-ignore` and refuses to start unless `.booth/.env` is gitignored. This prevents accidental commits of secrets.
2. **`--env-file <path>`** — explicit env file from CLI or config. Use `--env-file -` to disable auto-loading of `.booth/.env`.
3. **`-e KEY=VALUE`** in `run-args` — Docker-style env at the lowest layer in TOML, but applied at the same point as the env file.

You can also seed env keys via `booth config --env KEY=VALUE` during scaffolding.

The host wrapper itself is mounted read-only into the container at `/home/coder/code/booth` so the in-container helpers can re-invoke it.

For details, see **[booth run](docs/BOOTH_RUN.md)**.


## Mounts and Ports

### Bind mounts

```bash
booth -v /host/path:/container/path
```

Add Docker pass-through flags through `run-args` in `.booth/config.toml`:

```toml
run-args = [
    "-v", "/host/data:/data:ro",
    "-e", "FOO=bar",
]
```

### Ports

`--port` accepts:

| Value     | Effect                                     |
|-----------|--------------------------------------------|
| `<num>`   | Bind to that exact host port               |
| `NEXT`    | Find the next available port               |
| `RANDOM`  | Pick a random available port               |

For runtime port tunneling without restarting the container, see **[booth expose](docs/BOOTH_EXPOSE.md)** and the [`booth--expose`](#in-container-helpers) helper below.


## Run Modes

### Docker-in-Docker (`--dind`)

Runs a sidecar Docker daemon so processes inside the booth can build and run containers themselves. Requires `--privileged` on the sidecar. See **[DinD](docs/implementations/DIND.md)**.

### Sandbox (`--sandboxed`)

Restricts outbound network to an allowlist of domains via an Envoy proxy plus iptables egress filter. Useful when running third-party code or letting AI agents loose. The default allowlist can be inspected with `booth print-default-allowlist.txt`. See **[Sandbox](docs/implementations/SANDBOX.md)**.

### Booth-in-Booth

If you run `booth` *inside* an existing booth container, the wrapper detects nested invocation and warns. Nested operation must be opted in. See **[Booth-in-Booth](docs/implementations/BOOTH_IN_BOOTH.md)**.


## Persistent Home

By default, everything outside `/home/coder/code` (your project) is **ephemeral** — it disappears when the booth exits. To persist `/home/coder` across sessions:

```bash
booth --persist-home
```

This attaches a Docker named volume to the home directory. The volume is automatically seeded the first time from template-provided home files (`files.home` and `files.home-seed` in templates) using `smart_copy` — existing files in the volume are not overwritten.

Manage volumes with:

```bash
booth home-volume list
booth home-volume export <name> <file.tar>
booth home-volume import <name> <file.tar>
```

For seeding rules, dotfiles, credentials, and home-directory precedence, see **[booth home](docs/BOOTH_HOME.md)** and **[booth persist-home](docs/BOOTH_PERSIST_HOME.md)**.


## Local Cache

`.booth/cache/` is a host-side mirror of select container paths that survives across sessions — shell history, tool configs, language caches, etc. Its structure mirrors the container filesystem and matching files are **automatically bind-mounted**.

- **`smart_copy`** seeds the cache from image-provided defaults without overwriting your edits.
- **`.mount-this`** marker files designate which directories to bind-mount.
- Templates declare `cache-files` and `cache-dirs` to wire specific paths into the cache.
- Claude Code's `~/.claude/` is persisted via this mechanism out of the box.

See **[booth cache](docs/BOOTH_LOCALCACHE.md)**.


## Container Lifecycle

Manage running booths from outside the container:

| Command          | What it does                                  |
|------------------|-----------------------------------------------|
| `booth list`     | List managed booths                           |
| `booth start`    | Start a stopped booth                         |
| `booth stop`     | Stop a running booth                          |
| `booth restart`  | Restart a booth                               |
| `booth remove`   | Remove a booth (and its volumes if requested) |
| `booth prune`    | Remove all stopped booths and dangling state  |

For full lifecycle behavior, see **[booth lifecycle](docs/BOOTH_LIFECYCLE.md)** and the **[implementation notes](docs/implementations/BOOTH_LIFECYCLE.md)**.

### `.booth/.tmp/` lifecycle

Per-session ephemeral state lives at `.booth/.tmp/`. It is **wiped on start** and **cleaned on exit**.

| Flag                    | Effect                                                |
|-------------------------|-------------------------------------------------------|
| `--leave-tmp-on-exit`   | Don't clean `.booth/.tmp/` on exit (debugging)        |
| `--keep-tmp-on-start`   | Don't wipe `.booth/.tmp/` from previous session       |

A per-session metadata file is written at `.booth/.tmp/booth-startup.txt`. See **[booth tmp](docs/BOOTH_TMP.md)**.


## Session Timers

Two timers can be displayed in the lifecycle panel of web variants:

| Flag                            | Description                                                                |
|---------------------------------|----------------------------------------------------------------------------|
| `--show-run-time [epoch]`       | Show elapsed time since session start (or since `epoch`)                   |
| `--show-count-down <epoch>`     | Show countdown to a deadline; expires the session at `epoch`               |
| `--count-down-exit-code <code>` | Exit code when countdown expires (default: 0)                              |

Inside the container, `booth-timer-notifier` (a daemon, see [In-Container Daemons](#in-container-daemons)) surfaces count-down warnings into the web overlay. See **[booth runtime](docs/BOOTH_RUNTIME.md)**.


## Idle Auto-Shutdown

```bash
booth --idle-time 1800,300 --idle-exit-code 0
```

Shuts the booth down after 1800 seconds of inactivity, with a 300-second warning. Activity is detected via throttled keyboard / mouse events in the web UI and reported to the in-container `booth--idle-monitor` daemon.

Inside the booth, the **Idle Pause/Disable chip** in the web UI lets users pause or disable the timer for a session, with a sectioned dialog for changing the base timeout inline. State is persisted to `.booth/.tmp/`.


## Connecting to Booths

Attach to a running booth without SSH:

```bash
booth shell                  # interactive shell
booth exec <cmd> [args...]   # run a single command
```

See **[booth connect](docs/BOOTH_CONNECT.md)**.


## Messaging

CodingBooth has a built-in messaging layer for surfacing events and notifications inside the booth:

```bash
booth message send "Build finished"
booth message list
booth message response <id>
booth message adjust <id> ...
```

The host CLI is the **outside half**. The **inside half** is the in-container daemon `booth-message-api-server` plus the web overlay (modal / toast / banner primitives). For text-only variants, [`booth--msg`](#in-container-helpers) is a terminal UI replacement for the missing overlay. See **[booth message](docs/BOOTH_MESSAGE.md)**.


## Building Images

```bash
booth build              # build the image for this project's variant
booth build --push       # build and push to a container registry
```

For the full build reference, see **[booth build](docs/BOOTH_BUILD.md)**.

### Boothfile

A simplified, script-like alternative to a hand-written Dockerfile. The DSL is parsed and compiled to a real Dockerfile by the binary; setups already provided by the chosen variant are skipped automatically. See **[Boothfile reference](docs/implementations/BOOTHFILE.md)**.

### Build cache

Each build computes a hash of inputs (Boothfile / Dockerfile / build args / variant) and reuses the existing image when possible.

### Diagnostic emitters

| Command                                | Purpose                                                |
|----------------------------------------|--------------------------------------------------------|
| `booth emit-dockerfile`                | Print the compiled Dockerfile (for inspection / CI)    |
| `booth print-default-allowlist.txt`    | Print the default sandbox allowlist                    |


## Scaffolding Projects

CodingBooth generates `.booth/` from templates. There are four entry points:

### `booth config` — Template-driven scaffolding

Multi-tab interactive TUI with live preview. Non-interactive equivalents:

```bash
booth config --no-tui --select go:1.25+linter --select claude-code+auto-accept
booth config --env KEY=VALUE --expose 5173 --mount /host:/container --version 1.2.3
```

Cycle-field edit mode, validation, and a warning when `.booth/` is unwritable. See **[booth config](docs/BOOTH_CONFIG.md)**.

### Templates

```bash
booth template list           # all 77+ templates across categories
booth template help <name>    # template metadata
```

Selection DSL examples:

```
go:1.25+linter
python:3.13/scala
java+maven+m2/scala
claude-code+auto-accept
```

- `:VERSION` — pin a version
- `+EXTENSION` — auto-select or explicit add-on
- `/` — separator between top-level selections

Templates merge into existing config with deterministic rules: segment ordering (40 / 50 / 60 / 65 / 70 / 90), scalar match-or-error, array dedup with paired-flag awareness. They emit into:

- **Boothfile** segments (build-time setups)
- **`config.toml`** scalars and arrays (`dind`, `run-args`, `build-args`, ...)
- **Home seeding** (`files.home`, `files.home-seed`)
- **Cache** (`cache-files`, `cache-dirs`)
- **Startup scripts** (`.booth/startups/NN-name--startup.sh`)

Implementation: **[Booth Init](docs/implementations/BOOTHINIT.md)**.

### Recipes

A `.recipe` file packages a template selection in plain text — multiline with `+` continuation. Loaders:

| Form         | Source                |
|--------------|-----------------------|
| `<file>`     | Local file            |
| `@file`      | Implicit-file form    |
| `@@<url>`    | Fetched over HTTPS    |
| `-`          | stdin                 |

Recipes are sugar over the template selection DSL.

### Examples

```bash
booth example list
booth example try <name> <folder>
```

~45 ready-to-use workspaces. See **[booth example](docs/BOOTH_EXAMPLE.md)** and **[Examples implementation](docs/implementations/EXAMPLES.md)**.

### `.booth/.gitignore`

The `.booth/.gitignore` file is auto-written during scaffolding (it ignores `.booth/.tmp/`, `.booth/cache/`, `.booth/tools/`, `.booth/.env`, etc.). It is also (re)written by the wrapper's binary download flow to keep both authors in sync.


## The `.booth/` Folder

All booth configuration lives in a single `.booth/` folder in your project root:

```
my-project/
└── .booth/
    ├── config.toml     # Launcher configuration (TUI reads/writes this)
    ├── Boothfile       # Simplified build script (preferred)
    ├── Dockerfile      # Custom Docker build (fallback)
    ├── .env            # Personal env vars (gitignored, must be)
    ├── setups/         # Custom setup scripts
    ├── startups/       # Per-session startup scripts (NN-name--startup.sh)
    ├── home/           # Team-shared home directory files (seed)
    ├── cache/          # Local persistent state (gitignored)
    ├── .tmp/           # Ephemeral runtime state (per session)
    └── tools/          # Managed by booth wrapper (binary cache + lock)
```

> **Read-only by default:** The `.booth/` folder is mounted **read-only** inside the container. Use `--writable-booth` to opt out.

For the customization reference, see **[Booth Customization Guide](docs/BOOTH_CUSTOMIZATION.md)**.


## Built-in Tools

Every CodingBooth image comes with a curated baseline:

- **Shells & process management:** `bash`, `zsh`, `tini`
- **Networking & transfers:** `curl`, `wget`, `httpie`, `socat`
- **Source control:** `git`, `gh`, `tig`
- **Editors & file browsers:** `nano`, `tilde`, `ranger`, `less`
- **Data processing:** `jq`, `yq`, `tree`
- **Compression:** `unzip`, `zip`, `xz-utils`
- **System utilities:** `ca-certificates`, `locales`, `sudo`

Each variant extends the baseline — `notebook` adds Jupyter, `codeserver` adds a web-based IDE, the desktop variants add a window manager and noVNC.


## Setup Layer

The image's *capability* (Java? Python? VS Code? AI tools?) comes from ~186 build-time scripts under `variants/base/setups/`. Each runs once during `docker build`, as root, and may install up to three runtime artifacts:

| Artifact          | Path                                                       | Runs as / when                          |
|-------------------|------------------------------------------------------------|-----------------------------------------|
| Startup script    | `/usr/share/startup.d/<LEVEL>-cb-<name>--startup.sh`       | `coder` user, container start, idempotent |
| Profile script    | `/etc/profile.d/<LEVEL>-cb-<name>--profile.sh`             | Every shell                             |
| Starter wrapper   | `/usr/local/bin/<name>`                                    | When the user invokes the tool          |

`<LEVEL>` orders execution:

| Range  | Purpose                       |
|--------|-------------------------------|
| 50–54  | Base                          |
| 55–59  | OS / UI                       |
| 60–64  | Languages                     |
| 65–69  | Language extensions           |
| 70–74  | Dev tools                     |
| 75–79  | Tool extensions               |

### Categories of available setups

- **Language toolchains:** bun, cabal, cargo, clojure, conan, go, gradle, java/jdk, kotlin, lua, nodejs, php, python, ruby, rust, sbt, scala, ...
- **Package install layer:** pip, uv, conda, npm, yarn, bun, deno, go, cargo, gem, brew, cabal, hex, luarocks, pecl, conan
- **Cloud CLIs:** aws-cli, aws-cdk, aws-sam-cli, azure-cli, gcloud, firebase
- **IDE / editor:** codeserver, bluej, neovim
- **AI tools:** claude-code, codex, aider, cursor, gh-copilot, ollama, antigravity, warp
- **Browsers / databases / build tools:** chromium-browser; cloudbeaver; cmake
- **Code-server extensions:** bash, bun, clojure, codex, booth-message, booth-restart, booth-shutdown, ...
- **Notebook kernels:** bash, ...
- **Desktop bits:** noVNC, XFCE / KDE wallpaper branding, `cb-has-desktop*.sh`
- **Hardening / cleanup:** `no-sudo`, `cleanup-after--setup.sh`, `tls--setup.sh` (pinned Caddy)

### AI agent integration

AI tools that come with CodingBooth land an `AGENT.md` operational guide at:

- `/opt/codingbooth/AGENT.md`

The setup layer also creates a **symlink farm** so each agent finds it under its expected name: `CLAUDE.md`, `COPILOT.md`, `CURSOR.md`, `GPT.md`, `GEMINI.md`, `CODEIUM.md`, `WARP.md`. To wire your own:

```bash
# .booth/startup.sh
ln -sf /opt/codingbooth/AGENT.md /home/coder/CLAUDE.md
```

### Image-side cache seeding

Setups that want to pre-populate the cache use the same `smart_copy` + `.mount-this` mechanism as the host-side cache (see [Local Cache](#local-cache)).


## In-Container Helpers

Bash scripts named `booth--*` that the user invokes from a terminal **inside** the booth. Each shells back to the host or talks to the in-container message API server.

| Command                  | What it does                                                                                |
|--------------------------|---------------------------------------------------------------------------------------------|
| `booth--expose [port]`   | Request a runtime TCP tunnel host↔container. Writes a control file in `.booth/.tmp/`. `--permanent` persists into config |
| `booth--restart`         | Write a restart message; the lifecycle watcher acts on it. `--yes` skips confirmation. Rebuilds image if needed and preserves CLI args |
| `booth--shutdown`        | End the booth (same control-file pattern)                                                   |
| `booth--msg list/send/dismiss` | Terminal UI for the messaging system (replaces the missing overlay in `base`)         |
| `booth--info`            | Print booth identity and runtime info                                                       |
| `booth--envs`            | Print container env vars                                                                    |


## In-Container Daemons

Always-on background services started by each variant's entry scripts.

| Daemon                       | Role                                                                                       |
|------------------------------|--------------------------------------------------------------------------------------------|
| `booth--idle-monitor`        | Detects activity from the web UI; signals idle state; persists Pause/Disable to `.booth/.tmp/` |
| `booth-timer-notifier`       | Surfaces session-timer events (count-down warnings) into the web overlay                   |
| `booth-lifecycle-watcher`    | Watches `.booth/.tmp/` for restart/shutdown control files and executes them                |
| `booth-message-api-server`   | HTTP bridge (bash + socat) at `/booth-messages/api/` between web UI and message files      |


## Web UI

The browser-facing presentation layer for the web variants. Reaches into the binary and the in-container daemons via the message system.

- **Web overlay** (`booth-message-overlay.html`, JS / CSS) — modal / toast / banner primitives consuming the message API
- **Lifecycle panel** — Restart and Shut Down buttons, timer display, idle chip; every action goes through the message system
- **Idle Pause/Disable chip** — sectioned dialog with inline change-base-timeout; activity detection (throttled keyboard / mouse events) feeds `booth--idle-monitor`
- **"Container stopped" page** — across all web variants, including console (since v0.42)
- **Web proxy pane** (`/proxy/{port}/`) — nginx `sub_filter` plus an iframe toggle in the console UI; `X-Frame-Options` and CSP headers are stripped, with an open-in-new-tab fallback
- **Console UI** — `index.html` in `web-ttyd-split/`: terminal split view + overlay + proxy toggle
- **Nginx config** — `web-ttyd-split/nginx.conf.template`
- **Per-variant wrapper integration** — setup scripts (`booth-message-wrapper--setup.sh`, `booth-message-{codeserver,notebook,desktop}-wrapped--setup.sh`) wire the overlay into each variant's UI
- **Shutdown / restart confirmation dialogs** — zenity / kdialog on desktop variants; the web overlay on web variants

For the web overlay reference, see **[booth message](docs/BOOTH_MESSAGE.md)** and **[BOOTH_UI_OVERLAY](docs/BOOTH_UI_OVERLAY.md)**.


## Wrapper Tooling

Wrapper-only commands that don't touch the binary at all:

| Command                                | Purpose                                                                       |
|----------------------------------------|-------------------------------------------------------------------------------|
| `booth help`                           | Wrapper help (heredoc; no binary needed)                                      |
| `booth version`                        | Wrapper banner + version constant; appends binary version when available       |
| `booth tools-cache list`               | Inspect the shared binary cache                                               |
| `booth tools-cache clean [--all\|VERSION]` | Prune the shared binary cache                                              |

The wrapper is location-aware: invoking `/path/to/project/booth` from anywhere on the host always operates on that project. It also detects nested invocation (running `booth run` inside an existing booth) and warns.


## How It Works

CodingBooth mirrors your host identity inside the booth. Whoever you are on the host, the booth runs as the **`coder`** user, with passwordless `sudo` and a UID/GID that matches yours.

Only your project folder is mounted inside the booth as `/home/coder/code`.
The `.booth/` folder is mounted as `/home/coder/code/.booth` and made **read-only by default**; use `--writable-booth` to opt out. The `no-sudo` template removes passwordless sudo if you want a stricter container.

For deeper details — data persistence rules, in-container documentation, UID/GID handling, variant resolution, desktop+noVNC mechanics, sandbox internals, and booth-in-booth — see:

- **[How It Works Guide](docs/HOW_IT_WORKS.md)**
- **[Booth Setup Guide](docs/BOOTH_SETUP.md)**
- **[User Permissions](docs/implementations/USER_PERMISSIONS.md)**
- **[Variant Selection](docs/implementations/VARIANTS.md)**
- **[Desktop + noVNC](docs/implementations/DESKTOP_NOVNC.md)**
- **[Sandbox](docs/implementations/SANDBOX.md)**
- **[Booth-in-Booth](docs/implementations/BOOTH_IN_BOOTH.md)**


## Troubleshooting

### "Docker not found" or "Cannot connect to Docker daemon"

```bash
docker version
sudo usermod -aG docker $USER  # then logout/login
```

### "Permission denied" on project files

```bash
id
booth --dryrun --verbose | grep HOST_UID
```

### "Port already in use"

```bash
lsof -i :10000
booth --port 10001
booth --port NEXT
```

### "Container exits immediately"

```bash
booth --variant base
docker logs <container-name>
```

Common causes: command failed, missing dependencies, syntax error in `.booth/startup.sh`.

### "Build takes forever"

Layer-cache hygiene: rare-changing commands first; `COPY requirements.txt` before `RUN pip install`; don't separate `apt-get update` from `apt-get install`.

### Desktop variant shows black screen

- Wait — VNC takes a few seconds
- Check `~/.vnc/*.log` inside the container
- Verify `pgrep dbus-daemon`

### "Network timeout" behind a proxy

```toml
# .booth/config.toml
run-args = [
    "-e", "HTTP_PROXY=http://proxy.company.com:8080",
    "-e", "HTTPS_PROXY=http://proxy.company.com:8080"
]
```

### Still stuck?

1. `--verbose` for detailed debug output
2. `--dryrun` to see the exact Docker command
3. [GitHub Issues](https://github.com/NawaMan/CodingBooth/issues)


## Contributor Tooling

Repo-only scripts that exist for people hacking on CodingBooth itself. End users who install CodingBooth never see these.

```bash
./on-board-me.sh
```

Installs `.githooks/pre-commit`, which prevents committing when `version.txt` and `README.md` have mismatched versions. The hook only triggers when either file is staged.


## Guidance & Limitations

- **Host file ownership:** Files in your project remain owned by your host user — no root-owned files.
- **Consistent user mapping:** Each container creates a matching user and group via `booth-entry`.
- **Cross-OS caveats:** CodingBooth doesn't paper over all host-OS differences — line endings, symlinks, and file attributes may still vary.

### Security

CodingBooth is built for **development environments**, not production workloads.

| Aspect              | Behavior                                                                  |
|---------------------|---------------------------------------------------------------------------|
| **User privileges** | Processes run as unprivileged `coder` user, not root                      |
| **Sudo access**     | `coder` has passwordless sudo (use `no-sudo` template to remove)          |
| **File ownership**  | Files match your host UID/GID                                             |
| **`.booth/` config**| Read-only inside the container by default; `--writable-booth` to opt out  |
| **Network**         | Full access by default                                                    |
| **Egress sandbox**  | `--sandboxed` restricts outbound to allowlisted domains via Envoy + iptables |
| **DinD**            | Requires `--privileged` — elevated permissions; use only when needed      |

**Best practices:**
- Don't run untrusted code inside CodingBooth
- Avoid mounting sensitive host directories beyond what's needed
- Use `--sandboxed` when running third-party or AI-driven code
- Keep `.booth/.env` gitignored (the binary enforces this)

### JetBrains IDE licensing

JetBrains activation is machine-specific. Inside a fresh container, you may be asked to sign in again. Recommendations:

- **JetBrains Gateway (preferred):** license stays on your host
- **Persistent volumes:** mount configs/caches/plugins (`--persist-home`)
- **License Vault:** for short-lived containers


## Community & Feedback

- **Issues & feature requests:** [GitHub Issues](https://github.com/NawaMan/CodingBooth/issues)
- **Pull requests** are welcome — but the maintainer reserves the right to reject PRs that don't align with the project's vision
- **Sponsor:** [GitHub Sponsors](https://github.com/sponsors/NawaMan) · [Buy me a coffee](https://buymeacoffee.com/NawaMan)
- **Connect:** Twitter/X [@nawaman](https://x.com/nawaman) · [LinkedIn](https://www.linkedin.com/in/nawaman/) · [Blog](https://nawaman.net/blog/)

---

> Every issue, idea, and pull request — big or small — helps make CodingBooth better for everyone.
