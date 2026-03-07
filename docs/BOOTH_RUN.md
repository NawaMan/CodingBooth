# booth run

> Launch a fully configured development environment in one command.

`booth run` (or simply `./booth`) starts a containerized development environment using the configuration in `.booth/`. It handles image selection, port mapping, user permissions, and run modes automatically.

```bash
./booth                           # interactive shell (default)
./booth --variant codeserver      # VS Code in browser
./booth -- make test              # run a command and exit
```

Back to [README](../README.md)

---

## Table of Contents

- [Image Selection](#image-selection)
- [Container Name](#container-name)
- [Config Files](#config-files)
- [Environment Variables](#environment-variables)
- [Host UID/GID Handling](#host-uidgid-handling)
- [Run Modes](#run-modes)
- [Ports](#ports)
- [Pulling Images](#pulling-images)
- [Dry-Run Mode](#dry-run-mode)
- [Keep-Alive](#keep-alive)
- [Docker-in-Docker (DinD)](#docker-in-docker-dind)
- [TLS Support](#tls-support)
- [Help](#help)

---

## Image Selection

**Defaults**
- **Repository:** `nawaman/codingbooth`
- **Variant:** `base`
- **Version:** `latest`

**Overrides**
- **Environment variables:** `IMAGE_NAME`, `IMAGE_REPO`, `IMAGE_TAG`, `VARIANT`, `VERSION`
- **Configuration file:** `.booth/config.toml`
- **CLI options:** `--variant`, `--version`, `--image`, `--dockerfile`

**Precedence**
Command-line arguments > config file > environment variables > built-in defaults

> **Bootstrap note:** `--code` and `--config` are resolved from CLI (first pass) or defaults, and are not overridden by the config file or environment variables.

**Derived Values**
- `IMAGE_NAME` = `IMAGE_REPO:IMAGE_TAG`
- `IMAGE_TAG` = defaults to `${VARIANT}-${VERSION}`

> When both `--image` and `--dockerfile` are provided, `--image` takes precedence. Use `--dockerfile` when you want to build locally; otherwise, CodingBooth automatically pulls prebuilt images.

---

## Container Name

**Default**
The container name defaults to a sanitized version of the current folder name. If the directory name cannot be determined, it falls back to `booth`.

**Overrides**
- **Environment variable:** `CONTAINER_NAME`
- **Configuration file:** `.booth/config.toml`
- **CLI option:** `--name <name>`

> Using unique container names helps avoid conflicts when running multiple booth instances simultaneously.

---

## Config Files

CodingBooth supports several configuration files that control how containers are built and launched.

### Launcher Config (`.booth/config.toml`)

Loaded after bootstrap flags are determined and before full CLI parsing. Defines default values for image selection, user mapping, and runtime behavior.

Typical keys: `variant`, `version`, `image`, `dockerfile`, `name`, `host-uid`, `host-gid`, `port`, `dind`, and others.

#### Custom Argument Arrays

You can define special arrays in `.booth/config.toml` to customize Docker interaction:

- **`common-args`** — Pre-applied CLI flags merged before command-line parameters.
  ```toml
  common-args = ["--variant", "codeserver", "--port", "8080"]
  ```

- **`build-args`** — Extra args for `docker build` when a dockerfile is used.
  ```toml
  build-args = ["--no-cache", "--build-arg", "NODE_VERSION=20"]
  ```

- **`run-args`** — Extra args for `docker run`, appended automatically at launch.
  ```toml
  run-args = ["-e", "TZ=Asia/Bangkok", "-v", "/mnt/data:/data"]
  ```
  When using `booth init`, these can be set via CLI shorthands: `--expose` (for `-p`), `--env` (for `-e`), and `--mount` (for `-v`).

- **`cmds`** — Default command to run inside the container. CLI `-- <cmd>` overrides this (does not append).
  ```toml
  cmds = ["bash", "-lc", "make test"]
  ```

> These arrays allow you to version-control runtime and build options without hardcoding them into your CLI workflow.

### Environment Files (`.booth/.env`)

See [Environment Variables](#environment-variables) for the full guide on passing env vars into the container, including `.booth/.env`, `env-file`, `run-args -e`, and Boothfile `env`.

---

## Environment Variables

There are several ways to pass environment variables into the booth container, each suited to different use cases.

### At a Glance

| Method | Where | When Applied | Committed to Git? | Best For |
|--------|-------|-------------|-------------------|----------|
| `.booth/.env` | `.booth/.env` | Runtime (auto) | No (must be gitignored) | Personal secrets (tokens, keys) |
| `env-file` in config | `config.toml` | Runtime | Yes | Explicit env file path |
| `run-args` with `-e` | `config.toml` | Runtime | Yes | Individual vars with expansion |
| `env` in Boothfile | `Boothfile` | Build time | Yes | Baked-in defaults |

### 1. Local Secrets: `.booth/.env`

Automatically loaded when present — no configuration needed. Intended for personal secrets that should never be committed.

```env
GH_TOKEN=ghp_xxxxxxxxxxxx
GIT_USER=yourname
GIT_EMAIL=you@example.com
```

- **Must be gitignored.** CodingBooth refuses to run if the file exists but is not gitignored. `booth init` adds `.env` to `.booth/.gitignore` automatically.
- Always loaded first (lower priority than explicit `env-file` values on conflicts).

### 2. Explicit Env File: `env-file` in config.toml

Point to an environment file to pass into the container:

```toml
env-file = "config/dev.env"
```

`.booth/.env` is still loaded independently. Disable with `env-file = "-"`.

> **Note:** `.env` in the project root is **not** auto-detected by CodingBooth — it belongs to your application. Use `.booth/.env` for booth-specific secrets or `env-file` for an explicit path.

### 3. Inline Variables: `run-args` with `-e`

Pass individual environment variables via Docker run arguments in `config.toml`:

```toml
run-args = ["-e", "TZ=Asia/Bangkok", "-e", "DEBUG=true"]
```

When using `booth init`, you can set these with the `--env` shorthand:

```bash
booth init new --select python --env TZ=Asia/Bangkok --env DEBUG=true
```

These support **variable expansion** — you can reference host environment variables:

```toml
run-args = ["-e", "GH_TOKEN=${GH_TOKEN}"]
```

`$VAR`, `${VAR}`, and `~` (tilde for home directory) are expanded at config load time using host environment values.

> **Tip:** If the variable is already defined in `.booth/.env` or an explicit `env-file`, you don't need to repeat it in `run-args`. The env files pass variables directly to the container.

### 4. Build-Time Variables: `env` in Boothfile

Set environment variables that are baked into the Docker image:

```
env DJANGO_SETTINGS_MODULE=myproject.settings
env DEBUG=true
```

These become part of the image and are available in every container started from it. Use this for defaults that apply to all users of the project.

### Priority Order

When the same variable is defined in multiple places, later sources win:

```
Boothfile env (build-time, lowest)
  → .booth/.env
    → env-file (explicit)
      → run-args -e (highest at runtime)
```

---

## Host UID/GID Handling

CodingBooth ensures that all files created inside the container are owned by the same user and group as on your host system. This eliminates the common "root-owned files" problem when developing inside Docker.

**Defaults**
Automatically detects and uses your current user and group IDs:
```bash
HOST_UID=$(id -u)
HOST_GID=$(id -g)
```

---

## Run Modes

### Interactive Shell (default)

Launches an interactive terminal session. The container is removed automatically when you exit.

```bash
./booth
```

### Command Mode (`-- <cmd>`)

Executes a specific command inside the container and exits. Commands run under a login shell for a consistent environment.

```bash
./booth -- echo "Hello from container"
./booth -- make test
```

Exit codes are forwarded — booth exits with the same code as the command:

```bash
./booth -- false
echo $?  # prints: 1
```

### Silent Mode (`--silence-build`)

Suppresses container startup messages for cleaner output:

```bash
./booth --variant base --silence-build -- echo "Hello"
# Output: Hello
```

> Silent mode only hides startup messages. First runs may still take time for image pull/build.

### Daemon Mode (`--daemon`)

Starts the container in the background (detached). Commonly used for IDE variants that provide persistent services.

```bash
./booth --daemon --variant codeserver
```

> In daemon mode, attach later with `docker exec -it <container_name> bash`, or use lifecycle commands if `--keep-alive` is also set. See [Lifecycle](BOOTH_LIFECYCLE.md).

---

## Ports

CodingBooth automatically manages host-to-container port mappings.

**Default behavior**
The container exposes port 10000. If that port is unavailable, it tries 10001, 10002, and so on.

**Overrides**
- Environment variable: `CB_PORT`
- Configuration file: `.booth/config.toml`
- CLI flag: `--port <value>`

The value can be:
- A fixed number (`8080`)
- `NEXT` — find the next available port (1000 increment)
- `RANDOM` — assign a random open port (1000 increment from 10000)

> When running multiple booths at once, use `--port NEXT` to avoid conflicts automatically.

---

## Pulling Images

**Default behavior**
If the specified image does not exist locally, CodingBooth pulls it automatically. If the image is already present, it reuses the local copy.

**Forced pull**
```bash
./booth --pull
```

> Use `--pull` periodically to stay in sync with the latest base image, especially when sharing configurations across teams.

---

## Dry-Run Mode

Preview the exact `docker run` command without starting a container.

```bash
./booth --dryrun
```

No side effects — it does not check Docker status, pull images, or create containers.

> Combine `--dryrun` with `--verbose` to see detailed variable expansion and runtime configuration.

---

## Keep-Alive

By default, the container is removed when it exits. With `--keep-alive`, the container is preserved so you can resume it later.

```bash
./booth --keep-alive
```

Or in `.booth/config.toml`:

```toml
keep-alive = true
```

Once the container exits, use lifecycle commands to manage it:

```bash
./booth start myproject    # resume
./booth stop myproject     # stop
./booth remove myproject   # delete
```

See [Lifecycle](BOOTH_LIFECYCLE.md) for the full set of commands.

---

## Docker-in-Docker (DinD)

CodingBooth supports DinD mode for building and running Docker containers from inside your booth.

**Enable DinD**

```bash
./booth --dind
```

Or in `.booth/config.toml`:

```toml
dind = true
```

**How it works (sidecar mode)**

1. Creates a dedicated Docker network
2. Starts a `docker:dind` sidecar container running a Docker daemon
3. Shares the network namespace so `localhost` inside the booth reaches the sidecar
4. Sets `DOCKER_HOST=tcp://localhost:2375`

```
Host
└── Docker
    ├── DinD sidecar container
    │   └── Docker daemon (:2375)
    │       └── (your containers run here)
    └── Booth container
        ├── shares DinD's network (localhost = DinD)
        └── DOCKER_HOST=tcp://localhost:2375
```

> See `examples/workspaces/dind-example` for basic DinD usage and `examples/workspaces/kind-example` for KinD.

---

## TLS Support

CodingBooth supports self-signed certificate generation for HTTPS access to web-based variants (codeserver, notebook, desktop).

---

## Help

Display detailed usage information, supported flags, and configuration notes.

```bash
./booth --help
# or
./booth -h
```
