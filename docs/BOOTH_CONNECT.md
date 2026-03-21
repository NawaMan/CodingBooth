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
- [Common Workflows](#common-workflows)
- [Differences from docker exec](#differences-from-docker-exec)

---

## Overview

Both commands operate on a **running** booth container. Under the hood they use `docker exec`, so there is nothing to install and no port to expose.

| Command | Purpose                              | Interactive    | Requires `--` |
|---------|--------------------------------------|:--------------:|:-------------:|
| `shell` | Open a new interactive shell session | Yes            | No            |
| `exec`  | Run a one-off command                | No (by default)| Yes           |

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
```

| Flag               | Description                                                           |
|--------------------|-----------------------------------------------------------------------|
| `--shell <shell>`  | Shell to launch (default: container's default shell)                  |
| `--dir <path>`     | Starting directory inside the container (default: `/home/coder/code`) |
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
```

| Flag              | Description                                                          |
|-------------------|----------------------------------------------------------------------|
| `-it`             | Force interactive mode with TTY (default: non-interactive)           |
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

If the target container is not running, the command exits with an error and suggests using `booth start` first.

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
