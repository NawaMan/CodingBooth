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

- **`cmds`** — Default command to run inside the container. CLI `-- <cmd>` overrides this (does not append).
  ```toml
  cmds = ["bash", "-lc", "make test"]
  ```

> These arrays allow you to version-control runtime and build options without hardcoding them into your CLI workflow.

### Container Environment File (`.env`)

- Passed directly to Docker using the `--env-file` option.
- Commonly used for credentials or runtime configuration: `PASSWORD`, `JUPYTER_TOKEN`, `TZ`, `GH_TOKEN`, etc.
- Override the path with `env-file = "<path>"` in config.toml.
- Disable with `env-file = "none"` in config.toml.

### Local Environment File (`.booth/.env-local`)

- Automatically loaded when present — no configuration needed.
- Intended for **personal secrets** (API keys, tokens, credentials) that should never be committed.
- **Always gitignored:** `booth init` adds `.env-local` to `.booth/.gitignore`. CodingBooth refuses to run if the file exists but is not gitignored.
- **Merged with env-file:** When both files exist, env-file values take priority for any variables defined in both.
- Disabling the env-file (`env-file = "none"`) does **not** disable `.env-local`.

> **Configuration layers summary:**
> - **Build + Image:** `.booth/config.toml` (persistent project defaults)
> - **Local Secrets:** `.booth/.env-local` (personal, gitignored, always loaded)
> - **Container Environment:** `.env` (runtime secrets, overrides .env-local)

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
