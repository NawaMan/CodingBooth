# LLM Project Summary: CodingBooth

## What This Project Does

**CodingBooth** is a Docker-based development environment launcher. It solves the "root-owned files" problem when using containers for development by automatically mapping the container user's UID/GID to match the host user.

**Core value proposition**: Run `./booth` in any project, get a consistent dev environment with proper file permissions.

---

## LLM Checklist

Before and during work on this project, remember:

- [ ] **Plan first** - Remind the human to make a plan for the feature before implementation. They may decline, but always offer.
- [ ] **Branch/version check** - Remind the human if we should create a new branch or bump to a new version (RC) for this feature.
- [ ] **Offer to write tests** - Always offer to write tests for new functionality.
- [ ] **Test philosophy** - Don't go overboard with tests. Cover main cases (happy path + error cases) and obvious edge cases. No need for exhaustive coverage or 100% code coverage.
- [ ] **Update documentation** - For every new feature, update:
  - `README.md` - User-facing documentation
  - `docs/CHANGELOG.md` - What changed
  - `docs/TODO.md` - Remove completed items, add new ones
  - `docs/LLM.md` - If it affects how LLMs should work with the project

### Markdown Formatting

All tables in markdown files should use alignment markers for readability:

```markdown
| Left-aligned | Right-aligned | Centered    |
|:-------------|--------------:|:-----------:|
| text         |           123 | middle      |
```

---

## Architecture Overview

```
User runs ./booth (bash wrapper)
    ↓
Downloads/runs coding-booth (Go binary, cross-platform)
    ↓
Parses config: CLI flags → config.toml → env vars → defaults
    ↓
Builds/pulls Docker image (variant or custom Dockerfile)
    ↓
Runs container with:
  - HOST_UID/HOST_GID env vars
  - Volume mount: $PWD → /home/coder/code
  - Port mapping: host port → 10000
    ↓
Container entrypoint (booth-user-setup) aligns UID/GID
    ↓
User lands in consistent environment
```

---

## Key Directory Structure

```
/
├── booth                    # Bash launcher (downloads + runs binary)
├── coding-booth             # Go binary (the actual CLI)
├── version.txt              # Version (currently 0.12.0--rc6)
│
├── cli/src/                 # Go source code
│   ├── cmd/coding-booth/    # CLI entry: main.go, run.go, help.go
│   └── pkg/
│       ├── appctx/          # Immutable config context (AppContext)
│       ├── booth/           # Core logic: runner, image, port, dind
│       ├── docker/          # Docker CLI wrapper
│       └── ilist/           # Immutable list utilities
│
├── variants/                # Docker image definitions
│   ├── base/                # Base image + 46 setup scripts
│   │   ├── Dockerfile
│   │   ├── booth-user-setup # Container entrypoint
│   │   └── setups/          # Tool installers (python, nodejs, go, etc.)
│   ├── ide-codeserver/      # Browser-based VS Code
│   ├── ide-notebook/        # Jupyter notebook
│   ├── desktop-xfce/        # XFCE desktop
│   └── desktop-kde/         # KDE desktop
│
├── examples/workspaces/     # Example project configurations
├── tests/                   # Test suites (basic, dryrun, unit)
└── build/                   # Build scripts
```

---

## Configuration System

### Config File: `.booth/config.toml`

Located in project root. All options optional.

```toml
# Image selection (pick one)
variant = "desktop-xfce"       # Prebuilt: base, ide-codeserver, ide-notebook, desktop-xfce, desktop-kde
dockerfile = ".booth/Dockerfile"  # Or custom build
image = "myrepo/myimage:tag"   # Or existing image

version = "latest"             # Image version tag

# Container settings
name = "my-container"          # Container name (default: folder name)
port = "NEXT"                  # NEXT | RANDOM | <number>

# UID/GID (auto-detected, rarely needed)
host-uid = "1000"
host-gid = "1000"

# Flags
daemon = false                 # Run in background
dind = false                   # Docker-in-Docker sidecar
keep-alive = false             # Don't remove container on stop
pull = false                   # Always pull image

# Extra docker args
run-args = ["-e", "MYVAR=value"]
build-args = ["ARG1=val1"]
cmds = ["bash"]                # Default command
```

### Config Precedence

CLI flags > config.toml > environment variables > defaults

### Environment Variables

All config options available as `CB_*` env vars:
- `CB_VARIANT`, `CB_VERSION`, `CB_PORT`, `CB_NAME`
- `CB_DRYRUN`, `CB_VERBOSE`, `CB_DAEMON`, `CB_DIND`
- Full list in `cli/src/pkg/appctx/app_config.go`

---

## CLI Commands

```bash
./booth                           # Run in foreground (default variant)
./booth --variant base            # Use specific variant
./booth --daemon                  # Run in background
./booth -- bash                   # Interactive shell
./booth -- make test              # Run command and exit
./booth --dryrun                  # Print docker commands only
./booth help                      # Show help
./booth version                   # Show version
```

---

## Variants

| Variant          | Description                    | Port 10000 Serves |
|:-----------------|:-------------------------------|:------------------|
| `base`           | Minimal CLI with ttyd terminal | Web terminal      |
| `ide-codeserver` | Browser VS Code                | VS Code UI        |
| `ide-notebook`   | Jupyter with Bash kernel       | Jupyter           |
| `desktop-xfce`   | Full XFCE desktop              | noVNC desktop     |
| `desktop-kde`    | Full KDE desktop               | noVNC desktop     |

Aliases: `notebook`, `codeserver`, `xfce`, `kde`

---

## Setup Scripts Pattern

Located in `variants/base/setups/`. Each `*--setup.sh` produces:
1. **Startup script** → `/usr/share/startup.d/` (runs once on container start)
2. **Profile script** → `/etc/profile.d/` (sourced per shell)
3. **Starter wrapper** → `/usr/local/bin/` (user-invocable command)

Available setups (47 total): `python`, `nodejs`, `go`, `java`, `jdk`, `mvn`, `gradle`, `deno`, `bun`, `codeserver`, `notebook`, `dind`, `docker-compose`, `jetbrains`, `idea`, `pycharm`, `eclipse`, `claude-code`, `xfce`, `kde`, `network-whitelist`, etc.

**Note:** For `network-whitelist` setup details, see `docs/URL_WHITELIST.md`.

---

## Home Directory Seeding

Two layers (applied in order):
1. `.booth/home/` - Team defaults (committed to git)
2. `/tmp/cb-home-seed/` - Personal files (mounted from host, never committed)

Uses `cp -rn` (no-clobber) for `.booth/home/`, then copies `/tmp/cb-home-seed/` which can overwrite.

---

## UID/GID Mapping (The Core Feature)

Container entrypoint `booth-user-setup`:
1. Reads `HOST_UID` and `HOST_GID` env vars
2. Creates/modifies `coder` user to match
3. Relocates conflicting UIDs/GIDs if needed
4. Files created in container are owned by host user

---

## Docker-in-Docker (DinD)

`--dind` flag enables a sidecar pattern:
1. Creates private Docker network
2. Starts `docker:dind` sidecar container
3. Sets `DOCKER_HOST=tcp://localhost:2375`
4. Main container uses `--network container:<sidecar>`

---

## Key Source Files

| File                                               | Purpose                                  |
|:---------------------------------------------------|:-----------------------------------------|
| `cli/src/cmd/coding-booth/run.go`                  | CLI entry point                          |
| `cli/src/pkg/booth/booth_runner.go`                | Orchestrates context prep and execution  |
| `cli/src/pkg/booth/booth.go`                       | Run modes (daemon, foreground, command)  |
| `cli/src/pkg/appctx/app_context.go`                | Immutable config snapshot                |
| `cli/src/pkg/appctx/app_config.go`                 | Config struct with TOML/env mappings     |
| `cli/src/pkg/booth/init/initialize_app_context.go` | Context initialization                   |
| `cli/src/pkg/docker/docker.go`                     | Docker CLI wrapper                       |
| `variants/base/booth-user-setup`                   | Container entrypoint (bash)              |
| `variants/base/Dockerfile`                         | Base image definition                    |

---

## Testing

```bash
# All automated tests
./tests/run-automate-tests.sh

# Specific suites
cd tests/unit && ./run-all-go-tests.sh    # Go tests
cd tests/basic && ./run-basic-tests.sh    # Docker tests
cd tests/dryrun && ./run-dryrun-tests.sh  # Config tests

# Single test
./tests/basic/test001--command.sh
```

---

## Building

```bash
# Build Go CLI (outputs to bin/)
./build/cli-build.sh

# Build Docker images
./build/docker-build.sh                # Local build
./build/docker-build.sh --push base    # Push to Docker Hub
```

---

## Code Style (This Project)

- **No single-letter vars**: Use `thisList`, `index`, `TYPE` not `l`, `i`, `T`
- **Spell out names**: `Length()` not `Len()`
- **One type per file**: `list.go` → `List`, `appendable_list.go` → `AppendableList`
- **Minimal docs**: One-liner comments, document surprises only
- **AppContext pattern**: Immutable snapshot, use `ToBuilder()` and `Build()` to modify

---

## Common LLM Tasks

### Adding a new setup script
1. Create `variants/base/setups/TOOLNAME--setup.sh`
2. Follow pattern from existing scripts (produces startup, profile, wrapper)
3. Optionally add to variant Dockerfiles

### Adding a CLI flag
1. Add to `AppConfig` struct in `cli/src/pkg/appctx/app_config.go`
2. Handle in `cli/src/pkg/booth/init/initialize_app_context.go`
3. Update help in `cli/src/cmd/coding-booth/help.go`

### Adding a new variant
1. Create `variants/VARIANTNAME/Dockerfile` extending `base`
2. Add variant recognition in `cli/src/pkg/booth/validate_variant.go`

### Debugging config issues
1. Use `--dryrun` to see generated docker command
2. Use `--verbose` for detailed logging
3. Check `AppContext.String()` output format for all config values

---

## Terminology

| Term         | Meaning                                                 |
|:-------------|:--------------------------------------------------------|
| booth        | The launcher CLI and overall system                     |
| variant      | Pre-built Docker image flavor (base, ide-*, desktop-*)  |
| setup script | Tool installer that produces startup/profile/wrapper    |
| home seeding | Copying dotfiles to container home                      |
| DinD         | Docker-in-Docker sidecar pattern                        |
| AppContext   | Immutable config snapshot in Go code                    |
| NEXT/RANDOM  | Port allocation strategies                              |
