# booth lifecycle

> Pause your work, resume it tomorrow — your container picks up right where you left off.

By default, CodingBooth containers are removed when they exit. With `--keep-alive`, the container is preserved after exit so you can resume it later with all state intact.

```bash
./booth --keep-alive --name myproject
# ... work, then exit ...
./booth start myproject          # resume where you left off
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Default vs Keep-Alive](#default-vs-keep-alive)
- [Lifecycle Commands](#lifecycle-commands)
- [Common Workflows](#common-workflows)
- [Persistence Rules](#persistence-rules)
- [Container Snapshots](#container-snapshots)

---

## Overview

CodingBooth provides a set of lifecycle commands for managing container state. These commands let you list running and stopped booths, resume stopped containers, restart running ones, and clean up when you are done.

All lifecycle features are built on top of Docker container management. CodingBooth labels every container it creates so lifecycle commands can reliably find and operate on the right containers.

---

## Default vs Keep-Alive

### Default (no keep-alive)

```
run → RUNNING → exit → REMOVED (automatic cleanup)
```

The container is created with `--rm`. Once it exits, everything inside (installed packages, modified files outside mounted volumes) is gone.

### Keep-alive mode

```
run --keep-alive → RUNNING → exit → STOPPED (preserved)
                                       ↓
                                   start → RUNNING (resumed)
                                       ↓
                                   stop → STOPPED
                                       ↓
                                   remove → REMOVED
```

The container persists after exit. You can resume it, restart it, or explicitly remove it when done.

Enable keep-alive via CLI flag or config:

```bash
./booth --keep-alive
```

Or in `.booth/config.toml`:

```toml
keep-alive = true
```

---

## Lifecycle Commands

> **Podman and Apple container (experimental):** when you have not chosen an engine and more than one of Docker, Podman and Apple container is installed, these commands look at all of them and act on the engine that owns the booth (`booth list` then shows an `ENGINE` column). Set `CB_ENGINE=docker`, `podman` or `apple` (or `engine =` in the `.booth/config.toml` that `--code` points to) to use just one. `booth shell` and `booth exec` find their booth the same way. See [Container Engine](BOOTH_RUN.md#container-engine-experimental).

### `list`

Show all booth-managed containers.

```bash
./booth list              # all booths
./booth list --running    # only running
./booth list --stopped    # only stopped
./booth list --name-only  # just container names
```

Output includes: name, status, variant, port, code path, daemon, keep-alive, and creation time.

### `start`

Resume a stopped booth container.

```bash
./booth start myproject           # by name
./booth start --code ~/projects   # by code path
./booth start --daemon myproject  # resume in background
```

Target resolution priority:
1. `--name <name>`
2. Positional argument
3. `--code <path>`
4. Default booth name from current directory

A started booth is the same container as before, so it keeps the image it was **created** from.
If that image has been rebuilt since — you changed the Boothfile or a setup, and `booth` or
`booth build` rebuilt it — those changes are not in the booth, and `start` says so:

```
Warning: booth "myproject" was created from an older build of codingbooth-local:myproject-base; changes since (Boothfile, setups) are not in it.
         To use the current image: booth remove --force --name myproject, then run booth again.
```

`booth shell` / `booth exec` with `--run` warn the same way when they start a stopped booth.
Removing the booth deletes the container, and with it anything kept only inside it; files in
the project folder stay. `booth remove` also deletes the booth's `--persist-home` home volume —
export it first (`booth home-volume-export`) if you want to keep it.

### `stop`

Stop a running booth container.

```bash
./booth stop myproject              # graceful stop (10s timeout)
./booth stop --force myproject      # immediate kill
./booth stop --timeout 30 myproject # custom timeout
```

If the container was created **without** `--keep-alive`, stop also removes it automatically.

### `restart`

Restart a running booth in-place (same container, same configuration).

```bash
./booth restart myproject
./booth restart --timeout 30 myproject
```

> **From inside the container:** Use `booth--restart` to restart with full config re-processing (re-reads `config.toml`, `Boothfile`, rebuilds image if needed). This is different from `booth restart` on the host, which keeps the same container and configuration. See [`booth run` — Shutdown & Restart](BOOTH_RUN.md#shutdown--restart).

### `remove`

Explicitly delete a booth container.

```bash
./booth remove myproject                 # remove a stopped booth
./booth remove --force myproject         # force-remove even if running
./booth remove container1 container2     # remove multiple
```

### `prune`

Batch-remove all stopped booth containers.

```bash
./booth prune        # prompts for confirmation
./booth prune --yes  # skip confirmation
```

Also cleans up orphaned sidecar containers (DinD, egress) whose parent no longer exists.

### `logs`

Show what a booth printed, or the logs its services wrote.

```bash
./booth logs                       # container output, like `docker logs <booth>`
./booth logs -f --tail 100         # follow, starting from the last 100 lines
./booth logs --list                # the service log files in the booth's /tmp
./booth logs excalidraw -f         # follow /tmp/excalidraw.log
./booth logs --startup             # /tmp/startups.log, the image's startup hooks
./booth logs --name myproject      # another booth
./booth logs lifecycle             # what happened to the booth: started, stopped, idle, …
```

With no service named it is `<engine> logs` for the booth: the main process (ttyd, code-server,
Jupyter, …), booth-entry, and your `.booth/startups/` scripts. `-f`/`--follow`, `--tail`/`-n`,
`--since`, `--until` and `-t`/`--timestamps` are passed through. (Apple container has no
`--since`, `--until` or `--timestamps`, so those are refused there.)

Most autostarted services log to a file instead, so `docker logs` never shows them. A service
name selects `/tmp/<service>.log`, or, when there is none, every `/tmp/<service>-*.log`:
`booth logs n8n` shows `n8n-sandbox.log` and `n8n-search.log` together, with a `==> file <==`
header for each, the way `tail` shows several files. `--startup` is the service `startups`.
`--list` prints the names to use:

```
SERVICE       SIZE  MODIFIED             FILE
excalidraw    4.1K  2026-10-04 13:45:40  /tmp/excalidraw.log
startups      669B  2026-10-04 13:45:40  /tmp/startups.log
```

Positional arguments are service names, so the booth is picked with `--name` or `--code` (by
default, the booth of the current folder).

A stopped keep-alive booth still has its logs. Both forms read them from the stopped container
(log files through `<engine> cp`, which Apple container does not offer: start the booth there
first). `-f` then prints what is there and returns. A booth run without `--keep-alive` is removed
when it stops, and its logs go with it — all but the lifecycle log.

#### The lifecycle log

`booth logs lifecycle` answers "what happened to my booth?": one line per event, with the time,
the booth's name, and who or what caused it.

```
2026-10-04T14:42:23-0400 demo started version=0.80.0 variant=base mode=FOREGROUND port=10000
2026-10-04T14:42:38-0400 demo idle-prompted msg=idle-1791139358376557610 expires=2026-10-04T18:42:48Z
2026-10-04T14:42:48-0400 demo idle-timeout after=25s no answer to the prompt
2026-10-04T14:42:51-0400 demo shutdown reason=idle by=bash /opt/codingbooth/setups/booth--idle-monitor
2026-10-04T14:42:52-0400 demo exited status=0 idle-shutdown by=host-cli
```

| Event | Written when |
| --- | --- |
| `started` | the booth comes up (version, variant, run mode, host port) |
| `stop-requested`, `restart-requested`, `remove-requested` | `booth stop` / `restart` / `remove` is run on the host |
| `shutdown-requested`, `restart-requested` `by=web-ui` | the overlay's or console's Shut down / Restart button is pressed |
| `shutdown`, `restart` | `booth--shutdown` / `booth--restart` runs: `reason=` `idle`, `timer` or `requested` (a button), and `by=` the process that called it |
| `idle-monitor-started`, `idle-prompted`, `idle-answered`, `idle-paused`, `idle-disabled`, `idle-timeout` | the [idle monitor](BOOTH_IDLE.md) decides |
| `console-pane-exited` | a console pane's terminal server (`ttyd`) exits outside a shutdown: that pane then shows 502 until the booth restarts |
| `console-session-reset` | a console pane's session is reset from the Console UI (`session=s1` … `s6`): its shell and what ran in it were ended |
| `exited` | a booth the CLI ran in the foreground ends: its `status`, the `signal` behind it (`SIGINT` = Ctrl+C, `SIGTERM` = `docker stop`, `SIGKILL` = `docker kill`), and whether a restart or idle shutdown asked for it |

The file is `.booth/.tmp/lifecycle.log` in the booth's code folder, on the host. The booth writes
to it through the `.booth/.tmp/` mount and the CLI appends to it directly, so it outlives the
container — `booth logs lifecycle` reads it with no booth running, and `--code <path>` reads one
whose booth is long removed. Unlike the rest of `.booth/.tmp/`, it is kept across runs (trimmed to
its newest half once it passes 256 KB), and like the rest of it, it is gitignored. A booth run
without a `.booth/` folder has no `.booth/.tmp/` mount, and so no lifecycle log.

Stopping a follow — Ctrl+C, a closed pipe, a killed terminal — also stops the `tail` inside the
booth, so following never leaves processes behind.

---

## Common Workflows

### Day-to-day development

```bash
# Day 1: Start a persistent booth
./booth --keep-alive --name myproject

# Work inside the container...
# Exit when done (Ctrl+D or exit)

# Day 2: Resume
./booth start myproject

# Day 3: Resume in the background (for web-based variants)
./booth start --daemon myproject
```

### Check what's running

```bash
./booth list
```

### Clean up old containers

```bash
# See what's stopped
./booth list --stopped

# Remove all stopped booths
./booth prune --yes

# Or remove a specific one
./booth remove myproject
```

### Run a daemon booth for a web IDE

```bash
./booth --keep-alive --daemon --variant codeserver --name my-ide
# Access VS Code at http://localhost:10000

# Later, stop and resume
./booth stop my-ide
./booth start --daemon my-ide
```

---

## Persistence Rules

When a container is resumed via `start` or `restart`, its configuration is unchanged. The following **cannot be modified** without removing and recreating the container:

- Container name (`--name`)
- UI port (`--port`)
- Bind mounts (`-v`)
- Port mappings (`-p`)

### Home directory persistence

Use `--persist-home` to preserve `/home/coder` (IDE settings, shell history, app configs) across sessions via a Docker named volume. See [Persist Home Directory](BOOTH_PERSIST_HOME.md) for details.

To change these values, remove the container and run a new one:

```bash
./booth remove myproject
./booth --keep-alive --name myproject --port 9000
```

---

## Container Snapshots

Stopped keep-alive containers can be saved and shared using standard Docker commands.

### Save container state as a new image

```bash
docker commit <container-name> <image-name>:<tag>
```

### Export/import container filesystem

```bash
# Export
docker export -o backup.tar <container-name>

# Import as a new image
cat backup.tar | docker import - my-image:restored
```

### Save/load images

```bash
# Save image to file
docker save -o my-image.tar <image-name>:<tag>

# Load on another machine
docker load -i my-image.tar
```

See the [Docker documentation](https://docs.docker.com/) for more options.
