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

Also cleans up orphaned sidecar containers (DinD, sandbox) whose parent no longer exists.

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
