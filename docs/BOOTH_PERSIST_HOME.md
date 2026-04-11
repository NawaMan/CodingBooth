# Persist Home Directory

> Keep your IDE settings, browser history, and home directory state across booth sessions.

By default, `/home/coder` is rebuilt from scratch each time a container starts. With `--persist-home`, a Docker named volume stores the home directory so that everything survives across exits, restarts, and rebuilds.

```bash
./booth --persist-home --name myproject
# ... work, install VS Code extensions, customize settings ...
# exit and re-run:
./booth --persist-home --name myproject
# extensions and settings are still there
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Enabling Persist Home](#enabling-persist-home)
- [How It Works](#how-it-works)
- [Volume Management](#volume-management)
- [Use Cases](#use-cases)
- [Interaction with Other Features](#interaction-with-other-features)

---

## Overview

`--persist-home` creates a Docker named volume (`cb-home-<container-name>`) and mounts it at `/home/coder`. The project code directory (`/home/coder/code`) is still bind-mounted from the host as usual, overlaying on top of the volume.

This means:
- Project files are always from your host (as before)
- Everything else in `/home/coder` (IDE settings, shell history, app configs) persists in the volume
- The volume is invisible to git (it lives in Docker's storage, not in the project tree)

---

## Enabling Persist Home

**CLI flag:**
```bash
./booth --persist-home
```

**Config file (`.booth/config.toml`):**
```toml
persist-home = true
```

**Environment variable:**
```bash
CB_PERSIST_HOME=true ./booth
```

---

## How It Works

### First run

1. A Docker volume `cb-home-<container-name>` is created
2. The volume is mounted at `/home/coder`
3. Home directory seeding runs normally (all 4 layers: project seed, project override, image seed, image override)
4. A marker file (`.cb-home-seeded`) is written to track that seeding has been done

### Subsequent runs

1. The existing volume is reused (already has your files)
2. Seed layers (no-clobber) are **skipped** — your customizations are preserved
3. Override layers **still apply** — team-enforced configs are updated
4. The `chown` fixup is fast because most files already have the correct ownership

### On restart (`booth--restart`)

The volume survives. `booth--restart` removes and recreates the container, but Docker named volumes are not removed by `docker rm`. Your home directory state carries over.

---

## Volume Management

### Volume naming

Volumes are named `cb-home-<container-name>`. For example, a booth named `my-project` gets a volume called `cb-home-my-project`.

### Listing volumes

```bash
docker volume ls --filter label=cb.managed=true
```

### Cleanup

Volumes are automatically removed when you remove the booth:

```bash
./booth remove my-project  # removes both container and home volume
./booth prune              # removes stopped containers and their home volumes
```

To manually remove a volume:

```bash
docker volume rm cb-home-my-project
```

### Exit warning

When a persist-home container exits (but not on restart), a notice is printed:

```
Info: Home volume "cb-home-my-project" persists on disk.
      To reclaim space: docker volume rm cb-home-my-project
      Or: codingbooth remove my-project
```

---

## Use Cases

- **VS Code settings and extensions** — Extensions installed via the UI persist across sessions
- **Browser history** — Desktop variant browser state (bookmarks, history, cookies) survives
- **Application configs** — OpenOffice, JetBrains IDEs, and other app settings persist
- **Shell customizations** — Changes to `.bashrc`, `.zshrc`, tool configs beyond what seeding provides
- **Package manager caches** — pip, npm, cargo caches in home directory are retained

---

## Interaction with Other Features

### --keep-alive

Both features work together. `--keep-alive` preserves the entire container state (including system directories like `/tmp`, installed packages). `--persist-home` preserves only the home directory but works even without `--keep-alive` — the container is removed on exit but the home volume survives.

| Feature | Scope | Survives exit? | Survives remove? |
|---------|-------|---------------|-----------------|
| `--keep-alive` | Entire container | Yes (stopped) | No |
| `--persist-home` | `/home/coder` only | Yes (volume) | No (volume removed too) |

### .booth/cache/

Cache mounts overlay on top of the persist-home volume for their specific paths. If you have both `--persist-home` and `.booth/cache/home/coder/.bash_history`, the cache mount takes precedence for `.bash_history`.

### Home seeding (.booth/home-seed/, .booth/home/)

- **First run:** All seeding layers run normally
- **Subsequent runs:** Seed (no-clobber) layers are skipped; override layers always apply
- **Without persist-home:** No change to current behavior — all layers run every time
