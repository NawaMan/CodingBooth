# booth connect

> Your booth is busy — open another terminal without stopping what's running.

Every booth variant except `terminal` has a built-in way to open additional terminals: the Launcher in Notebook, the integrated terminal in Code Server, or any terminal emulator on a Desktop. The `shell` and `exec` commands bring the same capability to the `terminal` variant — and work with every other variant too.

```bash
./booth shell myproject        # open a new interactive shell
./booth exec  myproject -- make test   # run a command and get the result
```

No SSH server required. No extra ports. Works on Linux, macOS, and Windows.

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [shell](#shell)
- [exec](#exec)
- [Target Resolution](#target-resolution)
- [Run the booth if it is not running](#run-the-booth-if-it-is-not-running)
  - [Cleanup](#cleanup-the-booth-is-brought-back-down-afterwards)
  - [Multiple connections](#multiple-connections-are-reference-counted)
- [Create flags vs an existing booth](#create-flags-vs-an-existing-booth)
- [Common Workflows](#common-workflows)
- [Differences from docker exec](#differences-from-docker-exec)

---

## Overview

Both commands connect into a booth with `docker exec` — nothing to install, no SSH, no extra ports.

| Command | Purpose                              | Interactive    | Requires `--` |
|---------|--------------------------------------|:--------------:|:-------------:|
| `shell` | Open a new interactive shell session | Yes            | No            |
| `exec`  | Run a one-off command                | No (by default)| Yes           |

By default the target booth must already be **running**. Pass **`--run`** to start or create it first — see [Run the booth if it is not running](#run-the-booth-if-it-is-not-running).

When creating a booth, create-time flags such as **`--port`** are forwarded to `booth run`. Against an existing booth those flags are a **contract**: a mismatch fails unless you pass **`--accept-existing`** — see [Create flags vs an existing booth](#create-flags-vs-an-existing-booth).

---

## `shell`

Open a new interactive shell inside a booth.

```bash
./booth shell myproject
```

The shell launched is the default shell configured for the `coder` user inside the container (typically `bash`).

### Options

```bash
./booth shell myproject --shell zsh                 # use a specific shell
./booth shell myproject --dir /tmp                  # start in a specific directory
./booth shell myproject -e DEBUG=1                  # set an environment variable
./booth shell myproject --envfile .env              # load variables from a file
./booth shell myproject --run                       # run the booth first if not running
./booth shell myproject --run --keep-alive          # ...and leave it running afterwards
./booth shell myproject --run --port 9000           # create (if needed) on host port 9000
./booth shell myproject --port 9000 --accept-existing  # attach even if port differs
```

| Flag                         | Description                                                                 |
|------------------------------|-----------------------------------------------------------------------------|
| `--shell <shell>`            | Shell to launch (default: container's default shell)                        |
| `--dir <path>`               | Starting directory inside the container (default: `/home/coder/code`)       |
| `--run`                      | Run the booth first if it is not already running                            |
| `--keep-alive`               | With `--run`, leave the booth running after you disconnect                  |
| `--port <n\|NEXT\|RANDOM>`   | Host port when **creating** a missing booth; asserted against existing ones |
| `--accept-existing`          | Connect even if create flags (e.g. `--port`) do not match the booth         |
| `-e <VAR=value>`             | Set environment variable for the session                                    |
| `--envfile <path>`           | Load environment variables from a file                                      |
| `--name <name>`              | Target container by name                                                    |

### What you get

- A fully interactive terminal session with TTY and stdin attached.
- The session runs as the `coder` user, in the `/home/coder/code` directory — the same context as the original terminal.
- Environment variables, installed tools, and filesystem state are shared with the running container.
- Exiting the shell (Ctrl+D or `exit`) closes only that session; the booth keeps running (unless this session brought up an ephemeral booth with `--run` and no `--keep-alive` — see [Cleanup](#cleanup-the-booth-is-brought-back-down-afterwards)).

---

## `exec`

Run a command inside a booth and return the result.

```bash
./booth exec myproject -- make test
./booth exec myproject -- python -c "print('hello')"
./booth exec myproject -- cat /etc/os-release
```

Everything after `--` is executed inside the container. The exit code is forwarded — `booth exec` exits with the same code as the command.

### Options

```bash
./booth exec myproject -it -- bash                       # force interactive + TTY
./booth exec myproject -e FOO=bar -- env                 # set an environment variable
./booth exec myproject --envfile .env -- env             # load variables from a file
./booth exec myproject --dir /tmp -- ls                  # run command in a specific directory
./booth exec myproject --run -- make test                # run the booth first if not running
./booth exec myproject --run --keep-alive -- make test   # ...and leave it running
./booth exec myproject --run --port 9000 -- make test    # create (if needed) on port 9000
./booth exec myproject --port 9000 --accept-existing -- make test
```

| Flag                         | Description                                                                 |
|------------------------------|-----------------------------------------------------------------------------|
| `-it`                        | Force interactive mode with TTY (default: non-interactive)                  |
| `--run`                      | Run the booth first if it is not already running                            |
| `--keep-alive`               | With `--run`, leave the booth running after the command finishes            |
| `--port <n\|NEXT\|RANDOM>`   | Host port when **creating** a missing booth; asserted against existing ones |
| `--accept-existing`          | Connect even if create flags (e.g. `--port`) do not match the booth         |
| `-e <VAR=value>`             | Set environment variable for the command                                    |
| `--envfile <path>`           | Load environment variables from a file                                      |
| `--dir <path>`               | Working directory inside the container (default: `/home/coder/code`)        |
| `--name <name>`              | Target container by name                                                    |

### Exit codes

The exit code of the executed command is forwarded to the caller:

```bash
./booth exec myproject -- test -f /tmp/flag
echo $?   # 0 if the file exists, 1 if not
```

This makes `exec` suitable for scripting and CI pipelines.

---

## Target Resolution

Both `shell` and `exec` resolve the target container using the same priority as other lifecycle commands:

1. `--name <name>` — explicit container name
2. Positional argument — first non-flag argument
3. Default — booth name derived from the current directory

```bash
./booth shell myproject              # positional
./booth shell --name myproject       # explicit flag
cd ~/projects/app && ./booth shell   # default from current directory
```

If the target container is not running, the command exits with an error — unless you pass `--run`.

---

## Run the booth if it is not running

By default `shell` and `exec` require the booth to already be running. Pass `--run` to bring it up automatically before connecting:

```bash
./booth shell myproject --run                  # run (if needed), then open a shell
./booth exec  myproject --run -- make test     # run (if needed), then run a command
./booth exec  myproject --run --port 9000 -- make test
```

When `--run` is given, the booth is made available in whatever way is needed:

| Booth state | What happens |
|-------------|--------------|
| **Already running** | Used as-is — nothing is restarted |
| **Stopped** (e.g. a `--keep-alive` booth that was stopped) | Started (equivalent to `booth start`) |
| **Does not exist** | Created from the current workspace with `booth run --daemon` |

On create, create-time flags such as **`--port`** and **`--name`** are forwarded to that run (along with **`--keep-alive`** when set), so the booth matches an equivalent `booth run` invocation.

`--name` accepts the same `{port}` / `{project}` / `{variant}` placeholders as `booth run` (see [Container Name](BOOTH_RUN.md#name-placeholders)). Combined with `--port NEXT`, this creates a uniquely named, non-colliding booth in one command — `exec` connects to the resolved container even though its final name is only known after the run:

```bash
./booth exec --port NEXT --name '{project}-{port}' --run -- ./dev-run.sh
```

A short note is printed to **stderr**, and the new booth's startup output also goes to stderr, so `exec`'s **stdout stays clean** for scripting. `shell`/`exec` then wait for the booth's `coder` user alignment to finish before connecting, so the first command never races container startup.

> **Why this matters:** a normal booth that is stopped is *removed* (only `--keep-alive` booths persist as stopped containers). So "the booth is not running" usually means "there is no container" — and `--run` recreates it from the workspace config rather than failing.

Because running a booth is a side effect (it can build an image and allocate ports), `--run` is opt-in: omit it and a non-running booth remains an error, which keeps `booth exec` predictable in scripts and CI.

### Cleanup: the booth is brought back down afterwards

A booth that `--run` had to bring up does **not** outlive your session. When you disconnect (the shell exits, or the command finishes), the booth is returned to the state it was in before — so a default `--run` session leaves no trace:

| Before connecting        | After disconnecting (default)         |
|--------------------------|----------------------------------------|
| Already running          | Still running — never touched          |
| Stopped (`--keep-alive`) | Stopped again (returned to its state)  |
| Did not exist            | Removed                                |

Pass **`--keep-alive`** to opt out and leave the booth running after you disconnect:

```bash
./booth exec myproject --run --keep-alive -- make test   # booth stays up afterwards
./booth shell myproject --run --keep-alive               # work, exit, booth still running
```

A booth created with `--run --keep-alive` is created as a `--keep-alive` booth, so it persists across a later `booth stop` just like one you launched directly.

### Multiple connections are reference-counted

If you open several `--run` sessions on the same booth (e.g. two `booth shell --run` in different terminals), the booth is only brought down when the **last** one disconnects. An earlier session exiting will not pull the booth out from under the others. Passing `--keep-alive` from any session promotes the booth to persistent, so none of the sessions will stop it.

---

## Create flags vs an existing booth

Flags that configure a **new** booth only reconfigure when no container exists. Against a **running or stopped** booth they are a **contract** — fail by default so scripts do not run against the wrong environment.

Today the create flag on `shell` / `exec` is:

| Flag | On create (`--run`, no container) | Against an existing booth |
|------|----------------------------------|---------------------------|
| `--port <n>` | Forwarded to `booth run` | Must match the booth's published host port |
| `--port NEXT` / `RANDOM` | Forwarded to `booth run` | **Not compared** (only meaningful on create) |
| `--name` / positional | Name used for create and lookup | Target identity (not a mismatch check) |
| `--keep-alive` | Creates a keep-alive booth | Session policy only — never a mismatch |

### Mismatch policy

| Situation | Default | With `--accept-existing` |
|-----------|---------|--------------------------|
| Explicit create flag **matches** the booth | Connect | Connect |
| Explicit create flag **mismatches** (e.g. `--port 9000` but booth is on `8080`) | **Error** — refuse to connect | Connect with a **warning** on stderr |
| Symbolic port (`NEXT` / `RANDOM`) | Not compared | Not compared |
| No create flags | Connect | Connect |

Mismatch checks apply whenever you connect to an **existing** booth — with or without `--run`. They do not reconfigure a live container; they only decide whether connecting is safe.

```bash
# Create on 9000 if missing; fail if myproject already runs on another port
./booth exec myproject --run --port 9000 -- make test

# Attach anyway when the existing booth differs
./booth exec myproject --port 9000 --accept-existing -- make test
```

Example error (stderr, exit code 1):

```text
Error: booth "myproject" does not match create flags (--port 9000 requested but booth is on port 8080).
       Refusing to connect so the command does not run against the wrong environment.
       Use --accept-existing to connect anyway, or remove the booth and re-run with the desired flags.
```

---

## Common Workflows

### Attach a second terminal to a busy booth

```bash
# Terminal 1: running a long build
./booth --variant terminal --keep-alive --name myproject
make build-all   # takes a while...

# Terminal 2: open another shell while the build runs
./booth shell myproject
```

### Run a quick command without interrupting work

```bash
# Check test results while a server is running in the booth
./booth exec myproject -- make test

# Inspect a file
./booth exec myproject -- cat config.yaml
```

### Script against a running booth

```bash
# CI step: verify the environment
./booth exec myproject -- java --version
./booth exec myproject -- node --version
./booth exec myproject -- python3 --version
```

### One-shot: run if needed, then exec

```bash
# From the project workspace — create/start as needed, tear down after
./booth exec --run -- make test

# Leave the booth up for later shells
./booth exec --run --keep-alive -- make test
./booth shell --run --keep-alive
```

### Create on a fixed port (or refuse a mismatch)

```bash
# Prefer host port 9000 when this command creates the booth
./booth exec myproject --run --port 9000 -- make test

# Scripts that must not silently use the wrong port fail by default;
# opt in only when attaching to whatever is already there is intentional:
./booth exec myproject --port 9000 --accept-existing -- make test
```

### Use with daemon booths

```bash
# Start a background booth
./booth --keep-alive --daemon --variant terminal --name worker

# Shell into it whenever needed
./booth shell worker

# Or run commands remotely
./booth exec worker -- ./run-pipeline.sh
```

---

## Differences from `docker exec`

`booth shell` and `booth exec` are thin wrappers around `docker exec` with a few conveniences:

| Feature           | `docker exec`                | `booth shell` / `booth exec`                |
|-------------------|------------------------------|---------------------------------------------|
| Target by name    | Container ID or name         | Booth name or current directory             |
| User              | Defaults to root             | Defaults to `coder`                         |
| Working directory | Container default            | `/home/coder/code`                          |
| Interactive shell | `docker exec -it <id> bash`  | `booth shell <name>`                        |
| Environment       | Manual `-e` flags            | Inherits booth environment                  |
| Env file          | `--env-file <path>`          | `--envfile <path>`                          |
| Auto start/create | Not available                | `--run` (+ optional create flags / cleanup) |

> **Tip:** If you need raw `docker exec` capabilities not exposed by these commands, you can always fall back to Docker directly. Use `booth list --name-only` to get the container name.
