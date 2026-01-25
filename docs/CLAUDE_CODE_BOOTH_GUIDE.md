# Claude Code in CodingBooth: Environment Guide

This document explains how Claude Code operates inside a CodingBooth container and how to help users set up their development environment.

## Understanding Your Environment

You are running inside a Docker container managed by CodingBooth.
The key idea is that the container is re-created from a set of configuration files every time the user starts a booth.
The host user will be mapped to the user `coder` inside the container.
The project folder is mounted from the host to `/home/coder/code/`.
Therefore, everything else not in the project folder is ephemeral (the configuration files are also in the project folder).

## Key locations on the container:

| Path                       | Purpose                              | Host Location                                         |
|----------------------------|--------------------------------------|-------------------------------------------------------|
| `/home/coder/`             | User home directory                  | not exist on host                                     |
| `/home/coder/code/`        | Project directory (mounted from host)| the project folder on the host                        |
| `/home/coder/code/.booth/` | Booth configuration                  | the `.booth` folder on the project folder on the host |
| `/opt/codingbooth/setups/` | Available built-in setup scripts     | from the base booth image                             |

## The `.booth/` Folder Structure

| Path                       | Purpose                                                                 |
|----------------------------|-------------------------------------------------------------------------|
| `Dockerfile`               | Custom image build (tools, dependencies)                                |
| `setups`                   | Any project sepecfic scripts for the Dockerfile                         |
| `config.toml`              | Booth configuration                                                     |
| `home/`                    | Any files to be seeded in $HOME at startup (copied to $HOME at startup) |
| `startup.sh`               | Any scripts to be run at startup as a user                              |

When a booth is started, the following steps are taken:

1. The Dockerfile is used to build the image. Note that the Dockerfile will derived from one of the variant images.
2. The image is run as a container.
3. The startup.sh is run as the user.
4. The home/ is copied to $HOME at startup.

```
project/
└── .booth/
    ├── config.toml     # Runtime configuration
    ├── Dockerfile      # Custom image build (tools, dependencies)
    └── home/           # Team-shared dotfiles (copied to $HOME at startup)
        ├── .bashrc
        ├── .gitconfig
        └── .config/
```

## Adding Tools and Dependencies

When a user asks to install tools that should be available every time the booth starts, add them to `.booth/Dockerfile`.

### Basic Pattern

```dockerfile
# .booth/Dockerfile
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=base
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

# Install system packages
RUN apt-get update && apt-get install -y \
    some-package \
    another-package \
    && rm -rf /var/lib/apt/lists/*

# Use built-in setup scripts for common tools
RUN /opt/codingbooth/setups/python--setup.sh
RUN /opt/codingbooth/setups/nodejs--setup.sh
RUN /opt/codingbooth/setups/java--setup.sh 21

# Custom installations
RUN curl -fsSL https://example.com/install.sh | bash
```

### Available Setup Scripts

Check `/opt/codingbooth/setups/` for pre-built setup scripts. Common ones:

| Script                       | Purpose                                |
|------------------------------|----------------------------------------|
| `python--setup.sh [version]` | Python with pip, venv                  |
| `nodejs--setup.sh [version]` | Node.js with npm                       |
| `java--setup.sh [version]`   | Java JDK                               |
| `go--setup.sh [version]`     | Go language                            |
| `rust--setup.sh`             | Rust with cargo                        |
| `claude-code--setup.sh`      | Claude Code CLI (desktop variants only)|
| `docker--setup.sh`           | Docker CLI tools                       |

To list available setups:
```bash
ls /opt/codingbooth/setups/
```

### Choosing the Right Variant

The base image variant determines what's pre-installed:

| Variant        | Use Case                           |
|----------------|------------------------------------|
| `base`         | Minimal shell environment          |
| `notebook`     | Jupyter notebooks                  |
| `codeserver`   | VS Code in browser                 |
| `desktop-xfce` | Full Linux desktop (lightweight)   |
| `desktop-kde`  | Full Linux desktop (feature-rich)  |

Set in `.booth/config.toml`:
```toml
variant = "codeserver"
```

Or in Dockerfile FROM line:
```dockerfile
FROM nawaman/codingbooth:codeserver-latest
```

## Configuring Runtime Settings

### `.booth/config.toml` Options

```toml
# Image selection
variant = "codeserver"
version = "latest"

# Container settings
name = "my-project"
port = 10000

# Mount host directories/files into container
run-args = [
    # Mount a host directory
    "-v", "/host/path:/container/path",

    # Set environment variables
    "-e", "MY_VAR=value",

    # Home-seeding: mount credentials read-only to /etc/cb-home-seed/
    # They get copied to $HOME at startup
    "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro",
]

# Default command when booth starts
cmds = ["bash", "-lc", "code-server"]

# Docker build arguments
build-args = ["--no-cache"]
```

### Home-Seeding Pattern for Credentials

To share host credentials with the container safely:

1. Mount to `/etc/cb-home-seed/` with `:ro` (read-only)
2. At startup, files are copied to `/home/coder/` (writable copy)
3. The host's original files stay protected

```toml
run-args = [
    # Google Cloud credentials
    "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro",

    # Claude Code credentials
    "-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro",
    "-v", "~/.claude:/etc/cb-home-seed/.claude:ro",

    # SSH keys
    "-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro",
]
```

## Team-Shared Configuration (`.booth/home/`)

For dotfiles and configs that should be shared with the team (committed to git):

```
.booth/home/
├── .bashrc              # Shell customizations
├── .gitconfig           # Git settings (without credentials!)
├── .config/
│   └── nvim/
│       └── init.lua     # Editor config
└── .vscode/
    └── settings.json    # VS Code settings
```

**Warning**: Never put secrets in `.booth/home/` - it's version controlled.

## Common Workflows

### Starting a New Project

When a user wants to set up a new project with booth:

1. Create the `.booth/` folder structure:
```bash
mkdir -p .booth/home
```

2. Create `.booth/config.toml` with appropriate variant and settings

3. Create `.booth/Dockerfile` with required tools

4. User runs `./booth` to start the environment

### Adding a New Tool

When user asks "install X so it's always available":

1. Edit `.booth/Dockerfile` to add the installation
2. User needs to rebuild: `./booth --pull` or restart the booth

### Debugging Dockerfile Issues

If the booth fails to build:

1. Check Dockerfile syntax
2. Use `./booth --dryrun --verbose` to see what would run
3. Build manually to see errors: `docker build -t test .booth/`

### Temporary vs Permanent Installations

| User Request                 | Solution                                   |
|------------------------------|--------------------------------------------|
| "Install X for this session" | Run install command directly (ephemeral)   |
| "Install X permanently"      | Add to `.booth/Dockerfile`                 |
| "Add my personal config"     | Use home-seeding in `config.toml`          |
| "Add team-wide config"       | Put in `.booth/home/`                      |

## Environment Variables

The container has these pre-set:

| Variable   | Value          | Purpose               |
|------------|----------------|-----------------------|
| `HOME`     | `/home/coder`  | User home directory   |
| `USER`     | `coder`        | Username in container |
| `HOST_UID` | (varies)       | Host user's UID       |
| `HOST_GID` | (varies)       | Host user's GID       |

Set custom variables in `.booth/config.toml`:
```toml
run-args = ["-e", "MY_VAR=value"]
```

Or in `.env` file (for secrets, not committed):
```
API_KEY=secret123
DATABASE_URL=postgres://...
```

## File Permissions

Files created in `/home/coder/code/` are owned by your host user (thanks to UID/GID mapping). No `sudo` or permission fixes needed.

## Limitations to Remember

1. **Container is ephemeral** - installed packages outside Dockerfile don't persist
2. **No systemd** - use supervisor or direct process management
3. **Network** - container has its own network namespace
4. **GUI apps** - only work with desktop variants (xfce/kde)
5. **Docker-in-Docker** - requires `--dind` flag if user needs Docker inside booth

## Quick Reference

```bash
# Start booth
./booth

# Start with specific variant
./booth --variant codeserver

# Run a command and exit
./booth -- make test

# Start in background
./booth --daemon

# See what would run
./booth --dryrun --verbose

# Force rebuild
./booth --pull
```
