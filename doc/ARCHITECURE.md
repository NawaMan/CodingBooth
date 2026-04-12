# CodingBooth Architecture

This document itemizes the features and components of CodingBooth.

---

## Overview

CodingBooth is a CLI tool (written in Go) that creates fully reproducible, isolated development environments using Docker containers. It wraps Docker with developer-friendly abstractions for image management, port mapping, UID/GID mapping, session lifecycle, and interactive configuration.

```
User
  |
  v
booth (wrapper script)          # Downloads/manages the Go binary
  |
  v
codingbooth (Go binary)         # Core CLI application
  |
  v
Docker CLI                      # Container runtime (not Docker SDK -- uses CLI directly)
  |
  v
Container (variant image)       # The running development environment
```


---

## CLI Commands

### Core

| Command              | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| `run`                | Launch a booth container (default command)                         |
| `list`               | List booth-managed containers with filtering                       |
| `start`              | Start a stopped keep-alive booth                                   |
| `stop`               | Stop a running booth                                               |
| `restart`            | Restart a running booth                                            |
| `remove`             | Remove booth container(s)                                          |
| `prune`              | Remove all stopped booth containers                                |
| `shell`              | Open interactive shell in a running booth                          |
| `exec`               | Execute a command in a running booth                               |
| `message`            | Send interactive messages/notifications to booth users             |

### Project Setup

| Command              | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| `config`             | Configure `.booth/` projects via TUI or CLI                        |
| `template`           | Browse and manage project templates                                |
| `example`            | Manage and try pre-built example workspaces                        |

### Build & Publish

| Command              | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| `build`              | Build and optionally push booth images to registries               |
| `emit-dockerfile`    | Compile Boothfile to Dockerfile                                    |

### Home Volume Management

| Command              | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| `home-volume-list`   | List persisted home volumes                                        |
| `home-volume-export` | Export home volume to tar.gz                                       |
| `home-volume-import` | Import tar.gz into home volume                                     |

### Utility

| Command              | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| `version`            | Show version information                                           |

### Wrapper-Only (in `booth` shell script)

| Command              | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| `install`            | Download and install CodingBooth binary                            |
| `shell-config`       | Configure shell integration                                        |


---

## Go Package Structure

```
cli/src/
├── cmd/codingbooth/           # CLI entry point and command definitions
│   ├── main.go                # Cobra root command setup
│   ├── run.go                 # `booth run` command
│   ├── lifecycle_cmd.go       # start/stop/restart/remove/prune/list/shell/exec/message
│   ├── config.go              # `booth config` command
│   ├── template.go            # `booth template` command
│   ├── example.go             # `booth example` command
│   ├── build.go               # `booth build` command
│   ├── emit.go                # `booth emit-dockerfile` command
│   └── version.go             # `booth version` command
│
└── pkg/
    ├── appctx/                # Application context and configuration
    ├── booth/                 # Core booth runtime engine
    ├── boothfile/             # Boothfile parser and compiler
    ├── boothinit/             # Project initialization and template system
    ├── docker/                # Docker CLI wrapper
    ├── lifecycle/             # Container lifecycle management
    ├── defaults/              # Default values and constants
    ├── ilist/                 # Immutable list utility
    └── nillable/              # Nullable value utility
```

### Package Details

#### `appctx` -- Application Context

Manages configuration loading and resolution. Configuration follows a strict precedence order:

```
CLI flags  >  config.toml  >  environment variables  >  defaults
```

Key files:
- `app_context.go` -- Immutable `AppContext` snapshot holding all resolved booth settings
- `app_context_builder.go` -- Mutable builder that collects config from all sources
- `app_config.go` -- TOML configuration model and parsing

#### `booth` -- Core Runtime Engine

Orchestrates the entire booth launch pipeline: image resolution, Docker command construction, port allocation, environment setup, and container execution.

Key files:
- `booth.go` -- Main `Booth` type and Docker run command assembly
- `booth_runner.go` -- Pipeline orchestration (preparation phase + execution phase)
- `booth_tmp.go` -- Ephemeral runtime state in `.booth/.tmp/`
- `ensure_docker_image.go` -- Image existence checks; pull or build as needed
- `build_image.go` -- Docker image building
- `build_hash.go` -- Content-based hash for image caching
- `port_determination.go` -- Port allocation (static, NEXT, RANDOM)
- `resolve_relative_ports.go` -- Relative port offset arithmetic
- `tcp_tunnel.go` -- Runtime TCP tunnel creation via `docker exec` + `socat`
- `dind_setup.go` -- Docker-in-Docker sidecar setup
- `sandbox_setup.go` -- Envoy proxy egress filtering setup
- `validate_variant.go` -- Variant name resolution and alias handling
- `apply_env_file.go` -- `.env` file processing
- `init/` -- Application context initialization and dependency resolution

#### `boothfile` -- Boothfile Format

A simplified, script-like syntax for defining container environments (alternative to Dockerfile).

Key files:
- `parser.go` -- Parse Boothfile format
- `compiler.go` -- Compile Boothfile to standard Dockerfile

#### `boothinit` -- Project Initialization

Drives the `booth config` and `booth template` commands with template discovery, selection, and code generation.

Sub-packages:
- `template/` -- Template loading, searching, and metadata model
- `tui/` -- Interactive terminal UI for configuration
- `selection/` -- Template selection string parsing and resolution
- `output/` -- Code generation for `.booth/` files (config.toml, Boothfile, etc.)
- `compiler/` -- Template-to-Dockerfile compilation
- `cache/` -- Caching for template and build metadata

#### `docker` -- Docker Interaction Layer

Thin wrapper around the Docker CLI. CodingBooth uses `docker` commands (not the Docker SDK) for simplicity and portability.

Key files:
- `docker.go` -- Command execution with error handling and exit codes
- `docker_build.go` -- `docker build` wrapper
- `docker_buildx.go` -- `docker buildx` for multi-platform builds

#### `lifecycle` -- Container Lifecycle Management

Manages running containers: start, stop, restart, remove, prune, shell/exec connections, messaging, and home volume operations.

Key files:
- `lifecycle.go` -- Core lifecycle operations
- `connect.go` -- Shell and exec connections to running containers
- `message.go` -- Host-to-container messaging system
- `home_volume.go` -- Home directory volume management (list/export/import)


---

## Container Variants

Pre-built container images that share a common base but differ in UI:

| Variant          | Description                                    |
|------------------|------------------------------------------------|
| `base`           | Minimal terminal session with essential tools  |
| `notebook`       | Jupyter Lab with multi-language kernels        |
| `codeserver`     | VS Code in browser with extension support      |
| `desktop-xfce`   | Full XFCE Linux desktop via browser (noVNC)   |
| `desktop-kde`    | Full KDE Plasma desktop via browser (noVNC)    |

Aliases: `default`/`console` -> base, `terminal` -> base+bash, `ide` -> codeserver, `desktop` -> desktop-xfce.

Variant Dockerfiles live in `variants/<name>/Dockerfile`.


---

## Configuration System

All booth configuration lives in a `.booth/` directory within the project root:

```
.booth/
├── config.toml       # Main configuration (image, ports, env, mounts, etc.)
├── Boothfile         # Simplified build script (preferred over Dockerfile)
├── Dockerfile        # Traditional Docker build spec (fallback)
├── .env              # User-specific environment variables (gitignored)
├── startup.sh        # Custom startup command hook
├── setups/           # Custom setup scripts
├── home/             # Team-shared home directory seed files
├── home-seed/        # Team defaults (no-clobber seeding)
├── cache/            # Local persistent state across sessions (gitignored)
├── tools/            # Managed by booth wrapper (binary lock file)
└── .tmp/             # Ephemeral runtime state (auto-cleaned)
```

### Key Configuration Options

- **Image selection**: variant, dockerfile, boothfile, or pre-built image
- **Port mapping**: static number, `NEXT` (auto-find), `RANDOM`
- **Container naming**: custom name or auto-generated
- **Timezone/locale**: via `TZ` environment variable
- **UID/GID mapping**: host user identity preservation inside container
- **Environment variables**: inline, `.env` file, or `run-args`
- **Build arguments**: Docker `--build-arg` passthrough
- **Volume mounts**: bind mounts via `-v` flag or `run-args`
- **Startup commands**: custom entrypoint hooks
- **Sudo access**: passwordless sudo for `coder` user
- **Idle timeout**: auto-shutdown after idle period
- **Sandbox mode**: egress filtering via allowlist


---

## Networking

### Port Management

- **Static**: `--port 10000` maps to host port directly
- **NEXT**: `--port NEXT` scans for the next available port
- **RANDOM**: `--port RANDOM` picks a random available port
- **Relative offsets**: port arithmetic for multi-service setups

### Runtime Port Tunneling (booth expose)

Ports can be exposed at runtime without restarting the booth:
1. A process inside the container writes a request to `.booth/.tmp/tcp-tunnels/`
2. The TCP tunnel watcher on the host detects the request
3. A tunnel is created via `docker exec` + `socat` to forward the port

### Network Modes

- **Localhost-only** (default): accessible only on 127.0.0.1
- **Public**: bind to 0.0.0.0 with password protection
- **TLS/HTTPS**: optional certificate support for public mode


---

## Session Management

### Run Modes

| Mode         | Flag            | Behavior                                  |
|--------------|-----------------|-------------------------------------------|
| Foreground   | (default)       | Interactive session in terminal            |
| Daemon       | `--daemon`      | Background container execution             |
| Command      | `-- <cmd>`      | Run single command and exit                |
| Keep-alive   | `--keep-alive`  | Persist container after exit for resume    |

### Lifecycle Operations

- **list** -- Query containers with filtering (running/stopped/name-only)
- **start** -- Resume a stopped keep-alive booth
- **stop** -- Graceful stop with timeout, or force kill
- **restart** -- Stop and start again
- **remove** -- Delete container(s)
- **prune** -- Batch remove all stopped booth containers

### Timers and Idle

- **Idle timeout** (`--idle-time`): monitors activity, shuts down after idle period
- **Countdown** (`--show-count-down`): displays timer, exits at deadline
- **Run time** (`--show-run-time`): displays elapsed session time

### Container Identity

Containers are labeled with booth metadata (`cb.role`, `cb.parent`, etc.) for identification and lifecycle management.


---

## Messaging System

Host-to-container interactive messaging via JSON files in `.booth/.tmp/`.

### Message Types

| Type            | Description                      |
|-----------------|----------------------------------|
| `yes-no`        | Binary confirmation              |
| `yes-no-cancel` | Triple-choice dialog             |
| `text`          | Text input prompt                |
| `password`      | Masked password input            |
| `ok`            | Acknowledgment dialog            |
| `choice`        | Single-select from options       |
| `choice-text`   | Select with custom text input    |
| `radio`         | Radio button selection           |
| `checkbox`      | Multi-select checkboxes          |
| `toast`         | Non-blocking notification        |

Features: message ID tracking, TTL expiration, response persistence, JSON-based protocol.


---

## Docker-in-Docker (DinD)

Enabled via `--dind`. Launches a Docker daemon as a sidecar container that shares the network namespace with the main booth. Sets `DOCKER_HOST` for seamless Docker CLI access inside the booth.


---

## Sandbox (Egress Filtering)

Enabled via `--sandboxed`. Uses an Envoy proxy sidecar with iptables rules to restrict outbound network access to allowlisted domains only. Supports both a built-in default allowlist and custom allowlist configuration.


---

## Template System

Templates live in `templates/` organized by category:

```
templates/
├── languages/     # Python, Node.js, Go, Rust, Java, C#, Kotlin, Ruby, PHP, etc.  (26+)
├── tools/         # Docker, Kubernetes, Terraform, AWS, Ansible, Git, SSH, etc.    (42+)
├── ai-tools/      # Claude Code, Copilot, Cursor, Ollama, Aider, Codeium           (8+)
├── ides/          # VS Code Server, Jupyter Lab, JetBrains Gateway, Neovim, etc.
├── databases/     # PostgreSQL, MySQL, MongoDB, Redis, etc.                         (7+)
├── browsers/      # Firefox, Chrome, Chromium
└── desktops/      # XFCE and KDE configurations
```

Templates are composable: `booth config --select java+maven+claude-code` combines multiple templates into a single booth configuration.


---

## File Sharing and Home Management

### Mounts

- **Code directory**: project mounted at `/home/coder/code` inside container
- **Bind mounts**: custom mounts via `-v host:container`
- **`.booth/`**: mounted read-only by default (`--writable-booth` to override)

### UID/GID Mapping

The host user's UID/GID are passed into the container. The entrypoint (`booth-entry`) creates a matching `coder` user, so all files created inside the booth are owned by the host user.

### Home Directory Seeding

At startup, the home directory is populated from four sources in order:
1. `.booth/home-seed/` -- Team defaults (no-clobber)
2. `.booth/home/` -- Team overrides
3. `/etc/cb-home-seed/` -- Host personal defaults (no-clobber)
4. `/etc/cb-home/` -- Host personal overrides

### Home Persistence

- **`.booth/cache/`**: persist specific files (shell history, tool configs) across sessions
- **`--persist-home`**: persist entire `/home/coder` via Docker named volume
- **`home-volume-export/import`**: backup and restore home volumes


---

## Wrapper Script (`booth`)

The `booth` shell script is the user-facing entry point. It:

1. Determines the project directory (relative to its own location)
2. Reads the version lock from `.booth/tools/codingbooth.lock`
3. Downloads and caches the correct `codingbooth` binary for the platform
4. Verifies the binary checksum
5. Delegates to the Go binary for all container operations
6. Detects nested booth-in-booth scenarios

Binary cache location: `~/.cache/codingbooth/versions/<version>/`


---

## In-Container Resources

Every booth container includes:

```
/opt/codingbooth/
├── README.md          # Container documentation
├── AGENT.md           # Instructions for AI agents
├── version.txt        # CodingBooth version
├── variants/          # Dockerfiles for all variants
└── setups/            # Built-in setup scripts (python, nodejs, etc.)
```

Built-in tools in every image: bash, zsh, git, gh, curl, wget, httpie, jq, yq, nano, tilde, ranger, tree, and more.


---

## Example Workspaces

45+ pre-built examples in `examples/workspaces/` covering:

- Languages (Python, Node.js, Go, Rust, Java, C#, Kotlin, Ruby, PHP, etc.)
- Build tools (Maven, Gradle, npm, pip, Conda, etc.)
- Cloud platforms (AWS, GCP, Azure)
- Databases
- Container orchestration (Docker Compose, Kind, Kubernetes)
- Specialized tools (Playwright, Firebase, sandbox configurations)
