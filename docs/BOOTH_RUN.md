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
- [Shutdown & Restart](#shutdown--restart)
- [Docker-in-Docker (DinD)](#docker-in-docker-dind)
- [Public Access (`--public`)](#public-access---public)
- [TLS Support](#tls-support)
- [Help](#help)

---

## Image Selection

**Defaults**
- **Repository:** `nawaman/codingbooth`
- **Variant:** `base` (aliases: `default`, `console`, `terminal`)
- **Version:** `latest`

**Supported variants:** `base`, `notebook`, `codeserver`, `desktop-xfce` (alias: `xfce`), `desktop-kde` (alias: `kde`), `desktop-lxqt` (alias: `lxqt`).
Additional aliases: `default`/`console` → base, `terminal` → base with bash, `ide` → codeserver, `desktop` → desktop-xfce.
See [Variants Guide](BOOTH_VARIANTS.md) for details.

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
>
> **Tip:** Use [`booth build`](BOOTH_BUILD.md) to build and optionally push your booth image to a registry, then run it with `--image`.

---

## Container Name

**Default**
The container name defaults to a sanitized version of the current folder name. If the directory name cannot be determined, it falls back to `booth`.

**Overrides**
- **Environment variable:** `CONTAINER_NAME`
- **Configuration file:** `.booth/config.toml`
- **CLI option:** `--name <name>`

### Auto-suffix on collision

When the default (folder-derived) name is **already in use**, booth does not fail —
it automatically appends the resolved host port, so a second booth of the same
project gets a unique name without any extra flags:

```bash
~/myproj $ ./booth          # container: myproj
~/myproj $ ./booth          # 'myproj' taken → container: myproj-12000
```

The **stable base name stays with the first booth**, so no-argument lifecycle
commands keep targeting it:

```bash
~/myproj $ ./booth stop            # stops 'myproj' (the first)
~/myproj $ ./booth stop myproj-12000   # stop the second explicitly
```

Auto-suffix applies only to the derived default name. An **explicit** `--name`
is a contract: if the name you asked for is taken, booth errors rather than
silently renaming. Use a [placeholder](#name-placeholders) template (e.g.
`--name '{project}-{port}'`) when you want an explicit name that is still unique.

### Name placeholders

The name may contain `{…}` placeholders that are expanded **after** the port is
chosen, so a name can follow an auto-picked port:

| Placeholder | Expands to |
|-------------|------------|
| `{port}`    | the resolved host port (e.g. `12000`) |
| `{project}` | the sanitized project name (folder-derived) |
| `{variant}` | the variant name (e.g. `base`, `codeserver`) |

Because `{port}` is resolved after port selection, it pairs with `--port NEXT`
(or `RANDOM`) to give both a unique port **and** a matching unique name in one
command — the recommended way to run several booths of the same project:

```bash
./booth --port NEXT --name '{project}-{port}'
# picks a free port (say 12000) → container "myproj-12000"

./booth --port NEXT --name '{project}-{port}'   # again, in another terminal
# picks 13000 → container "myproj-13000" — no --name / --port collision
```

The template is stored literally, so setting it once in `.booth/config.toml`
(`name = "{project}-{port}"`) re-resolves on every run. Characters that are not
Docker-name-safe in the literal parts of the template are replaced with `-`.

> **Quote the value** (`'{project}-{port}'`) so your shell does not try to
> interpret the braces.

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
  When using `booth config`, these can be set via CLI shorthands: `--expose` (for `-p`), `--env` (for `-e`), and `--mount` (for `-v`).

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

> Values written in `.booth/.env`, `config.toml`, and `CB_*` env vars are resolved by booth with a bash-like rule set (`$VAR`, `${VAR:-default}`, `${VAR:?required}`, `~`, `"..."` / `'...'`). See [Variable Expansion](BOOTH_VARS.md) for the full rules and worked examples.

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

- **Must be gitignored.** CodingBooth refuses to run if the file exists but is not gitignored. `booth config` adds `.env` to `.booth/.gitignore` automatically.
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

When using `booth config`, you can set these with the `--env` shorthand:

```bash
booth config --no-tui --select python --env TZ=Asia/Bangkok --env DEBUG=true
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

**Everything after `--` is one shell command line, not an argument list.** The arguments are
joined with spaces and handed to `bash -lc` inside the container, so the container's shell — not
your host shell — does the final parsing.

Shell operators therefore work, as long as your host shell doesn't eat them first:

```bash
./booth -- echo hi '>' out.txt        # '>' quoted on the host, redirects in the container
./booth -- 'ls | wc -l'               # pipeline runs in the container
```

The flip side: **quoting does not survive the join**, so an argument containing spaces is
re-split. Wrap the whole thing in one quoted argument when the command has its own quoting:

```bash
./booth -- python -c "print('hi there')"     # ✗ breaks: becomes  python -c print('hi there')
./booth -- 'python -c "print(1 + 1)"'        # ✓ quote the entire command line
```

> `booth exec` is the other way round — it passes the arguments straight to `docker exec` with no
> shell in between, so quoting survives but operators like `|` and `>` do **not**. Use
> `booth exec <name> -- bash -c '<line>'` when you need a shell there. See
> [BOOTH_CONNECT.md](BOOTH_CONNECT.md).

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

### Log Time (`--log-time`)

Prefixes progress messages with timestamps, useful for debugging startup timing:

```bash
./booth --variant codeserver --daemon --log-time
# [18:04:05] 📦 Running booth in daemon mode.
# [18:04:05] 👉 Visit 'http://localhost:10000'
# ...
```

Can also be set via environment variable (`CB_LOG_TIME=true`) or in `config.toml`:

```toml
log-time = true
```

### Session Timers (`--show-run-time`, `--show-count-down`)

Display session timers in the booth UI — elapsed time and/or countdown to a deadline.

```bash
# Elapsed time from now
./booth --show-run-time

# Elapsed time from a specific epoch
./booth --show-run-time $(date +%s)

# Countdown to 2 hours from now
./booth --show-count-down $(( $(date +%s) + 7200 ))
```

When the countdown reaches 5 minutes, a warning dialog prompts the user to save their work. At zero, the booth auto-shuts down. Use `--count-down-exit-code <code>` to set the exit code (default: 0).

For full details, color thresholds, and variant-specific behavior, see **[booth runtime](BOOTH_RUNTIME.md)**.

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
- `NEXT` — find the next available port (1000 increment from 10000)
- `RANDOM` — assign a random open port (1000 increment from 10000)
- `NEXT:<base>` — like `NEXT`, but start scanning from `<base>` instead of 10000
- `RANDOM:<base>` — like `RANDOM`, but pick from ports at or above `<base>`

```bash
./booth --port NEXT          # first free port ≥ 10000
./booth --port NEXT:20000    # first free port ≥ 20000
./booth --port RANDOM:20000  # random free port ≥ 20000
```

`<base>` is any port in 1–65535 (it need not be a multiple of 1000; scanning then
steps by 1000 from that base). `NEXT` is exactly `NEXT:10000`.

> When running multiple booths at once, use `--port NEXT` to avoid conflicts
> automatically. Give related projects their own ranges with `NEXT:<base>` (e.g.
> one project on `NEXT:20000`, another on `NEXT:30000`) so their auto-picked
> ports stay in separate, predictable bands.

### The offset base

A published port written as `+OFFSET` is not an absolute host port — it is resolved
at start against the **offset base** (see
[Booth Config → Booth-relative host ports](BOOTH_CONFIG.md#booth-relative-host-ports)).
That base is the booth port by default, which is what makes the whole scheme work
locally: the booth port is the one number that already differs between two booths of
the same project, so every service moves with it and nothing collides.

That default stops making sense where the booth is alone on the machine. A cloud
booth has the entire port range to itself and its front door on a port someone else
picked — 443, or whatever the platform assigns — so counting service ports from it
lands them somewhere arbitrary. `--offset-base` sets the base directly and leaves the
booth port alone:

- CLI flag: `--offset-base <n>`
- Environment variable: `CB_OFFSET_BASE`
- Configuration file: `offset-base` in `.booth/config.toml`

```bash
./booth --port 20000                      # +4567 → 24567 (base = the booth port)
./booth --port 443 --offset-base 20000    # +4567 → 24567, booth still on 443
./booth --offset-base 0                   # +8090 → 8090 — offsets become absolute
```

`<n>` is 0–65535. **Zero is deliberately allowed** where a booth port of 0 is not: it
makes each `+OFFSET` resolve to the offset itself, so a config written in offsets
publishes at stock ports without being rewritten.

Nothing else changes: the booth's own port is still `--port`, published ports are
still checked for collisions after resolution (including against the booth port,
which a moved base can now reach), and `booth--expose +OFFSET` inside the container
uses the same base.

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

## Shutdown & Restart

CodingBooth provides commands that can be run **from inside the container** to shut down or restart the booth.

### `booth--shutdown`

Gracefully shut down the container from within.

```bash
booth--shutdown
```

### `booth--restart`

Restart the booth from within. The host binary re-runs the full pipeline — re-reading `config.toml`, `Boothfile`, rebuilding the image if needed — then launches a fresh container. CLI arguments from the original invocation are preserved.

```bash
booth--restart          # prompts for confirmation
booth--restart --yes    # skip confirmation
```

This is useful when you have modified `.booth/config.toml` or `.booth/Boothfile` and want to apply the changes without leaving the booth:

```bash
# Inside the container:
# 1. Edit configuration (e.g. add a new template or setup)
# 2. Restart to apply
booth--restart
```

> **Note:** `booth--restart` only works in foreground and command run modes, not in daemon mode. For daemon booths, use `booth restart` from the host. See [Lifecycle](BOOTH_LIFECYCLE.md).

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

## Public Access (`--public`)

By default a booth listens on `127.0.0.1` only — nothing outside your machine can reach it. `--public` binds it to every interface instead, and turns on password authentication and HTTPS together, because an open port without both would be an open shell.

```bash
./booth --public
```

The password is read from `.booth/.booth.password` (mode `600`, gitignored), or prompted for if that file is missing. It is never written to `config.toml`.

### Signing in

A booth started with `--public` greets you with its own sign-in page rather than the browser's built-in credential popup:

```
🌐 Open: https://localhost:19443
🔑 Login username: coder (prefilled)
```

**The username is always `coder`**, and the page fills it in for you — you only type the password. The field stays editable, but `coder` is the sole account a booth accepts.

A few things worth knowing:

- **The session lasts as long as the booth does.** Signing in sets a cookie tied to a token the booth generates at startup, so restarting a booth signs you out everywhere.
- **The certificate is self-signed** unless you pass `--tls-cert` / `--tls-key`, so expect a browser warning on first visit.
- **Everything behind the front door is protected**, including the terminal panes and the booth's own control API — not just the landing page.

> `--public` exposes your development environment to your whole network. Use a password you would not mind an attacker seeing attempts against, prefer a real certificate over the self-signed one, and shut the booth down when you are done with it.

---

## TLS Support

CodingBooth supports self-signed certificate generation for HTTPS access to web-based variants (codeserver, notebook, desktop-xfce, desktop-kde, desktop-lxqt).

---

## Help

Display detailed usage information, supported flags, and configuration notes.

```bash
./booth --help
# or
./booth -h
```
