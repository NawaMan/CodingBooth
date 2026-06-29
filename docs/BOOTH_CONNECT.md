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
- [Common Workflows](#common-workflows)
- [Differences from docker exec](#differences-from-docker-exec)

---

## Overview

Both commands operate on a **running** booth container. Under the hood they use `docker exec`, so there is nothing to install and no port to expose.

| Command | Purpose                              | Interactive    | Requires `--` |
|---------|--------------------------------------|:--------------:|:-------------:|
| `shell` | Open a new interactive shell session | Yes            | No            |
| `exec`  | Run a one-off command                | No (by default)| Yes           |

If the target booth is not running, both commands error by default. Pass `--run` to bring it up first — see [Run the booth if it is not running](#run-the-booth-if-it-is-not-running).

---

## `shell`

Open a new interactive shell inside a running booth.

```bash
./booth shell myproject
```

The shell launched is the default shell configured for the `coder` user inside the container (typically `bash`).

### Options

```bash
./booth shell myproject --shell zsh          # use a specific shell
./booth shell myproject --dir /tmp           # start in a specific directory
./booth shell myproject -e DEBUG=1           # set an environment variable
./booth shell myproject --envfile .env       # load variables from a file
./booth shell myproject --run                # run the booth first if not running
./booth shell myproject --run --keep-alive   # ...and leave it running afterwards
```

| Flag               | Description                                                           |
|--------------------|-----------------------------------------------------------------------|
| `--shell <shell>`  | Shell to launch (default: container's default shell)                  |
| `--dir <path>`     | Starting directory inside the container (default: `/home/coder/code`) |
| `--run`            | Run the booth first if it is not already running                      |
| `--keep-alive`     | With `--run`, leave the booth running after you disconnect            |
| `-e <VAR=value>`   | Set environment variable for the session                              |
| `--envfile <path>` | Load environment variables from a file                                |
| `--name <name>`    | Target container by name                                              |

### What you get

- A fully interactive terminal session with TTY and stdin attached.
- The session runs as the `coder` user, in the `/home/coder/code` directory — the same context as the original terminal.
- Environment variables, installed tools, and filesystem state are shared with the running container.
- Exiting the shell (Ctrl+D or `exit`) closes only that session; the booth keeps running.

---

## `exec`

Run a command inside a running booth and return the result.

```bash
./booth exec myproject -- make test
./booth exec myproject -- python -c "print('hello')"
./booth exec myproject -- cat /etc/os-release
```

Everything after `--` is executed inside the container. The exit code is forwarded — `booth exec` exits with the same code as the command.

### Options

```bash
./booth exec myproject -it -- bash                # force interactive + TTY
./booth exec myproject -e FOO=bar -- env          # set an environment variable
./booth exec myproject --envfile .env -- env       # load variables from a file
./booth exec myproject --dir /tmp -- ls           # run command in a specific directory
./booth exec myproject --run -- make test         # run the booth first if not running
./booth exec myproject --run --keep-alive -- make test  # ...and leave it running
```

| Flag              | Description                                                          |
|-------------------|----------------------------------------------------------------------|
| `-it`             | Force interactive mode with TTY (default: non-interactive)           |
| `--run`           | Run the booth first if it is not already running                     |
| `--keep-alive`    | With `--run`, leave the booth running after the command finishes     |
| `-e <VAR=value>`  | Set environment variable for the command                             |
| `--envfile <path>`| Load environment variables from a file                               |
| `--dir <path>`    | Working directory inside the container (default: `/home/coder/code`) |
| `--name <name>`   | Target container by name                                             |

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

If the target container is not running, the command exits with an error and suggests using `booth run` first — unless you pass `--run`.

---

## Run the booth if it is not running

By default `shell` and `exec` require the booth to already be running. Pass `--run` to bring it up automatically before connecting:

```bash
./booth shell myproject --run              # run (if needed), then open a shell
./booth exec  myproject --run -- make test     # run (if needed), then run a command
```

When `--run` is given, the booth is made available in whatever way is needed:

- If the booth is **already running**, it is used as-is — nothing is restarted.
- If a **stopped** container exists (e.g. a `--keep-alive` booth that was stopped), it is started (equivalent to `booth start`).
- If **no container exists**, a new booth is created from the current workspace with `booth run` in daemon mode, exactly as if you had run `booth` here yourself.

In every case a short note is printed to **stderr** and the new booth's startup output is also sent to stderr, so `exec`'s **stdout stays clean** for scripting. `shell`/`exec` then wait for the booth's `coder` user alignment to finish before connecting, so the first command never races container startup.

> **Why this matters:** a normal booth that is stopped is *removed* (only `--keep-alive` booths persist as stopped containers). So "the booth is not running" usually means "there is no container" — and `--run` recreates it from the workspace config rather than failing.

### Cleanup: the booth is brought back down afterwards

A booth that `--run` had to bring up does **not** outlive your session. When you disconnect (the shell exits, or the command finishes), the booth is returned to the state it was in before — so a `--run` session leaves no trace:

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

#### Multiple connections are reference-counted

If you open several `--run` sessions on the same booth (e.g. two `booth shell --run` in different terminals), the booth is only brought down when the **last** one disconnects. An earlier session exiting will not pull the booth out from under the others. Passing `--keep-alive` from any session promotes the booth to persistent, so none of the sessions will stop it.

Because running a booth is a side effect (it can build an image and allocate ports), `--run` is opt-in: omit it and a non-running booth remains an error, which keeps `booth exec` predictable in scripts and CI.

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

> **Tip:** If you need raw `docker exec` capabilities not exposed by these commands, you can always fall back to Docker directly. Use `booth list --name-only` to get the container name.
