# Booth Lifecycle Management - Implementation Plan

## Overview

This document outlines the implementation plan for comprehensive booth lifecycle management commands, enabling users to manage containers, save states, and share environments.

## Command Set

### Container Lifecycle

| Command   | Description                     | Docker Equivalent             |
|-----------|---------------------------------|-------------------------------|
| `run`     | Create and start a new booth    | `docker run`                  |
| `list`    | Show all booth containers       | `docker ps -a --filter`       |
| `start`   | Start an existing stopped booth | `docker start`                |
| `stop`    | Stop a running booth            | `docker stop` [+ `docker rm`] |
| `restart` | Stop and start a running booth  | `docker restart`              |
| `remove`  | Remove a stopped booth          | `docker rm`                   |


### Image Workflow

| Command   | Description                   | Docker Equivalent |
|-----------|-------------------------------|-------------------|
| `commit`  | Save container state to image | `docker commit`   |
| `push`    | Push image to registry        | `docker push`     |
| `backup`  | Save image to file            | `docker save`     |
| `restore` | Load image from file          | `docker load`     |


## Lifecycle Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                                                                     │
│                         CONTAINER LIFECYCLE                         │
│                                                                     │
│   run ──────► RUNNING ◄─────── start                                │
│                  │                ▲                                 │
│                  │ stop           │                                 │
│                  ▼                │                                 │
│               STOPPED ────────────┘                                 │
│                  │                                                  │
│                  ├── (auto-removed if no --keep-alive)              │
│                  │                                                  │
│                  └── remove (explicit, if --keep-alive)             │
│                                                                     │
│               restart = stop + start (for running containers)       │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│                          IMAGE WORKFLOW                             │
│                                                                     │
│   CONTAINER ──commit──► IMAGE ──┬── push ────► REGISTRY             │
│                                 │                                   │
│                                 └── backup ──► FILE                 │
│                                                                     │
│   run --image ◄─── IMAGE ◄───┬── pull ─────── REGISTRY              │
│                              │                                      │
│                              └── restore ──── FILE                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## Container Labels

All booth-managed containers will include these labels for identification and filtering:

```go
--label cb.managed=true
--label cb.project=<project-name>
--label cb.variant=<variant>
--label cb.code-path=<absolute-path>
--label cb.created-at=<timestamp>
--label cb.version=<booth-version>
```

These labels enable:
- `list` command to filter booth containers via `cb.managed=true`
- `start` command to find container by `--code` path via `cb.code-path`
- Future analytics and cleanup tools

---

## Command Specifications

### `run` - Create and Start New Booth

**Current behavior** - already implemented. Enhancements needed:

- Add container labels (see above)
- Default command (no subcommand) continues to work as `run`

```bash
# Explicit
./coding-booth run --variant base --port 50000

# Implicit (backward compatible)
./coding-booth --variant base --port 50000

# With keep-alive
./coding-booth run --variant base --keep-alive

# With command
./coding-booth run --variant base -- 'npm start'
```

---

### `list` - Show All Booth Containers

**Purpose**: Display all booth-managed containers with status and metadata.

```bash
./coding-booth list              # All booth containers
./coding-booth list --running    # Only running
./coding-booth list --stopped    # Only stopped
```

**Output Format**:
```
NAME              STATUS   VARIANT     PORT    CODE PATH                     CREATED
my-project        Running  base        50000   /home/user/my-project         2m ago
api-service       Stopped  codeserver  50001   /home/user/api-service        1d ago
my-project-dev    Stopped  notebook    50002   /home/user/my-project         3d ago
```

**Implementation**:
```go
// Use docker ps with label filter
docker ps -a --filter "label=cb.managed=true" --format "..."
```

**Options**:
| Flag            | Description                  |
|-----------------|------------------------------|
| `--running`     | Show only running containers |
| `--stopped`     | Show only stopped containers |
| `--quiet`, `-q` | Show only container names    |

---

### `start` - Start Existing Stopped Booth

**Purpose**: Restart a stopped booth container (created with `--keep-alive`).

```bash
# From project directory (auto-detect name)
./coding-booth start

# Explicit name
./coding-booth start --name my-project
./coding-booth start my-project          # Positional shorthand

# By code path (from different directory)
./coding-booth start --code /home/user/my-project
```

**Behavior**:
1. Find container by name (derived from current dir, or explicit)
2. Verify container exists and is stopped
3. Run `docker start -ai <container>` (attached, interactive)

**Options**:
| Flag             | Description                                      |
|------------------|--------------------------------------------------|
| `--name <NAME>`  | Container name (default: current directory name) |
| `--code <PATH>`  | Find container by original code path             |
| `--daemon`, `-d` | Start in background (no attach)                  |


**Error Cases**:
```
Error: No stopped booth 'my-project' found.
Use './coding-booth list --stopped' to see available containers.

Error: Cannot determine booth name from current directory.
Use './coding-booth start --name <NAME>' or './coding-booth start --code <PATH>'
```

---

### `stop` - Stop Running Booth

**Purpose**: Stop a running booth. If `--keep-alive` was not set during `run`, container is removed.

```bash
# From project directory
./coding-booth stop

# Explicit name
./coding-booth stop --name my-project
./coding-booth stop my-project

# Force stop (kill)
./coding-booth stop --force
```

**Behavior**:
1. Find running container by name
2. Run `docker stop <container>`
3. If container was created WITHOUT `--keep-alive`, run `docker rm <container>`

**Note**: The `--keep-alive` state needs to be tracked. Options:
- Store in container label: `--label cb.keep-alive=true`
- Check if container was started with `--rm` flag (inspect container config)

**Options**:
| Flag            | Description                                     |
|-----------------|-------------------------------------------------|
| `--name <NAME>` | Container name                                  |
| `--force`, `-f` | Force stop (SIGKILL instead of SIGTERM)         |
| `--time <SEC>`  | Seconds to wait before force kill (default: 10) |


---

### `restart` - Restart Running Booth

**Purpose**: Stop and start a running booth (useful for applying changes).

```bash
./coding-booth restart
./coding-booth restart --name my-project
```

**Behavior**:
1. Run `docker restart <container>`

**Options**:
| Flag | Description |
|------|-------------|
| `--name <NAME>` | Container name |
| `--time <SEC>` | Seconds to wait before force kill (default: 10) |

---

### `remove` - Remove Stopped Booth

**Purpose**: Explicitly remove a stopped booth container.

```bash
./coding-booth remove
./coding-booth remove --name my-project
./coding-booth remove my-project

# Remove multiple
./coding-booth remove proj1 proj2 proj3

# Force remove (even if running)
./coding-booth remove --force my-project
```

**Options**:
| Flag            | Description                  |
|-----------------|------------------------------|
| `--name <NAME>` | Container name               |
| `--force`, `-f` | Force remove even if running |


---

### `commit` - Save Container to Image

**Purpose**: Create a Docker image from a container's current state.

```bash
# From current project
./coding-booth commit --tag mywork:v1

# Explicit container
./coding-booth commit --name my-project --tag mywork:v1

# With message
./coding-booth commit --tag mywork:v1 --message "Added dependencies"
```

**Behavior**:
1. Find container (running or stopped)
2. Run `docker commit <container> <tag>`

**Options**:
| Flag              | Description          |
|-------------------|----------------------|
| `--name <NAME>`   | Container name       |
| `--tag <TAG>`     | Image tag (required) |
| `--message <MSG>` | Commit message       |

---

### `push` - Push Image to Registry

**Purpose**: Push a committed image to a container registry.

```bash
./coding-booth push mywork:v1
./coding-booth push mywork:v1 --registry ghcr.io/username
```

**Behavior**:
1. Tag image for registry if needed
2. Run `docker push <image>`

**Options**:
| Flag               | Description                        |
|--------------------|------------------------------------|
| `--registry <URL>` | Registry URL (default: Docker Hub) |


---

### `backup` - Save Image to File

**Purpose**: Export a Docker image to a tar file for offline sharing.

```bash
./coding-booth backup mywork:v1 -o mywork.tar
./coding-booth backup mywork:v1 --output mywork.tar.gz --compress
```

**Behavior**:
1. Run `docker save -o <file> <image>`

**Options**:
| Flag             | Description                 |
|------------------|-----------------------------|
| `--output`, `-o` | Output file path (required) |
| `--compress`     | Compress with gzip          |


---

### `restore` - Load Image from File

**Purpose**: Load a Docker image from a tar file.

```bash
./coding-booth restore mywork.tar
./coding-booth restore mywork.tar.gz
```

**Behavior**:
1. Run `docker load -i <file>`
2. Display loaded image name/tag

**After restore**, user can run:
```bash
./coding-booth run --image mywork:v1
```

---

## Implementation Phases

### Phase 1: Core Container Management
- [ ] Add container labels to `run` command
- [ ] Implement `list` command
- [ ] Implement `start` command
- [ ] Implement `stop` command (with keep-alive awareness)
- [ ] Implement `remove` command

### Phase 2: Container State Persistence
- [ ] Implement `restart` command
- [ ] Add `cb.keep-alive` label tracking
- [ ] Improve error messages and suggestions

### Phase 3: Image Workflow
- [ ] Implement `commit` command
- [ ] Implement `push` command
- [ ] Implement `backup` command
- [ ] Implement `restore` command

### Phase 4: Polish
- [ ] Add shell completion for container names
- [ ] Add confirmation prompts for destructive operations
- [ ] Documentation and help text
- [ ] Integration tests for all commands

---

## File Changes Required

### New Files
- `cli/src/cmd/coding-booth/list.go`
- `cli/src/cmd/coding-booth/start.go`
- `cli/src/cmd/coding-booth/stop.go`
- `cli/src/cmd/coding-booth/restart.go`
- `cli/src/cmd/coding-booth/remove.go`
- `cli/src/cmd/coding-booth/commit.go`
- `cli/src/cmd/coding-booth/push.go`
- `cli/src/cmd/coding-booth/backup.go`
- `cli/src/cmd/coding-booth/restore.go`

### Modified Files
- `cli/src/cmd/coding-booth/main.go` - Add subcommand routing
- `cli/src/pkg/booth/booth.go` - Add label generation in `PrepareCommonArgs`
- `cli/src/pkg/docker/docker.go` - Add helper functions for ps, start, stop, etc.

---

## Usage Examples

### Daily Workflow
```bash
# Start work
./coding-booth run --variant codeserver --keep-alive

# End of day - stop but keep container
./coding-booth stop

# Next day - continue where you left off
./coding-booth start

# Done with project - clean up
./coding-booth remove
```

### Team Sharing via Registry
```bash
# Developer A: Save and share environment
./coding-booth commit --tag team/myproject:configured
./coding-booth push team/myproject:configured

# Developer B: Use shared environment
./coding-booth run --image team/myproject:configured
```

### Offline Sharing via File
```bash
# Export for colleague without registry access
./coding-booth commit --tag myproject:v1
./coding-booth backup myproject:v1 -o myproject-env.tar

# Send file to colleague...

# Colleague imports and runs
./coding-booth restore myproject-env.tar
./coding-booth run --image myproject:v1
```

---

## UID/GID Migration on Commit/Restore

### Problem Statement

When a container is committed (`docker commit`) or backed up/restored, the files in `/home/coder` retain their original UID/GID ownership. If a different user (with different UID/GID) later runs the restored image, they face permission issues:

**Scenario:**
1. User A (UID 1000, GID 1000) runs booth, creates files in `/home/coder`
2. Container is committed: `docker commit container myimage:v1`
3. Image saved with `/home/coder` owned by `1000:1000`
4. User B (UID 1001, GID 1001) runs `./booth --image myimage:v1`
5. `booth-user-setup` creates user `coder` with UID 1001, GID 1001
6. **Problem**: `/home/coder` files are still owned by `1000:1000` — User B cannot access their own home directory

**Edge cases:**
- Same UID, different GID (e.g., 1000:1000 → 1000:1001): Can read files but group permissions broken
- Different UID, same GID: Cannot access files owned by different UID
- UID collision with system user: Potential security/access issues

### Proposed Solution

**Marker file approach**: Track the previous UID/GID and perform targeted migration at startup.

#### Implementation

**Marker file location:** `/home/coder/.booth-owner`

**Format:**
```
1000:1000
```

**Startup logic in `booth-user-setup`:**

```bash
MARKER="$HOME_DIR/.booth-owner"

# Check if migration is needed
if [[ -d "$HOME_DIR" && -f "$MARKER" ]]; then
    OLD_OWNER=$(cat "$MARKER")
    OLD_UID="${OLD_OWNER%:*}"
    OLD_GID="${OLD_OWNER#*:}"

    if [[ "$OLD_UID" != "$HOST_UID" || "$OLD_GID" != "$HOST_GID" ]]; then
        echo "⚠️  Home directory was owned by UID:GID $OLD_UID:$OLD_GID"
        echo "   Migrating ownership to $HOST_UID:$HOST_GID..."
        echo "   (This may take a while for large home directories)"

        # Only change files owned by the OLD booth user (targeted migration)
        if [[ "$OLD_UID" != "$HOST_UID" ]]; then
            find "$HOME_DIR" -user "$OLD_UID" -exec chown "$HOST_UID" {} +
        fi
        if [[ "$OLD_GID" != "$HOST_GID" ]]; then
            find "$HOME_DIR" -group "$OLD_GID" -exec chgrp "$HOST_GID" {} +
        fi

        echo "   Migration complete."
    fi
fi

# Always update marker with current UID/GID
echo "$HOST_UID:$HOST_GID" > "$MARKER"
chown "$HOST_UID:$HOST_GID" "$MARKER"
```

#### Key Design Decisions

1. **Targeted migration**: Only changes files owned by the *previous* booth user, not arbitrary files. This preserves intentional ownership of system files or files from other sources.

2. **Marker file in home**: Stored in `/home/coder/.booth-owner` so it survives `docker commit`. Alternative `/var/run/` would not persist.

3. **User warning**: Alerts user about migration and potential time cost for large home directories.

4. **Batched operations**: Uses `find ... -exec ... +` (batched) instead of `\;` (per-file) for better performance.

### Current Code State

**File:** `variants/base/booth-user-setup` (lines 157-162)

```bash
# OK, I don't know where are these from but it need to be belong to the user
find "${HOME_DIR}"         \
  -path "${CODE_DIR}" \
  -prune                   \
  -o                       \
  -exec chown "${HOST_UID}:${HOST_GID}" {} + >/dev/null 2>&1 || true
```

**Issues with current approach:**
- Unconditionally chowns everything in `$HOME_DIR` (except `$CODE_DIR`)
- No tracking of previous owner — cannot do targeted migration
- Silent — no warning about what it's doing or why
- Could change ownership of files that shouldn't be changed

### Implementation Location

Insert the migration logic in `booth-user-setup` around line 156, **before** the existing `find/chown` block.

The existing blanket chown can be:
- **Option A**: Removed entirely (rely on targeted migration)
- **Option B**: Kept as fallback for edge cases (e.g., first run, corrupted marker)

### Future Considerations

1. **Skip flag**: Add `CB_SKIP_MIGRATION=true` env var for users who know what they're doing

2. **Progress indicator**: For very large home directories, consider showing file count or progress

3. **Symlinks**: Decide whether to follow symlinks (`-H` or `-L` flag in find)

4. **Large caches**: `.cache`, `.local/share` can be huge. Consider:
   - Warning if home > N GB
   - Option to skip certain directories
   - Documentation about cleaning before commit

5. **Testing**: Add integration tests for:
   - Basic migration (different UID/GID)
   - UID-only change
   - GID-only change
   - First run (no marker)
   - Same UID/GID (no-op)

---

## Open Questions

1. **Default keep-alive behavior**: Should `--keep-alive` become the default? Current default removes container on exit.

2. **Auto-cleanup**: Should we add a `prune` command to remove old stopped containers?

3. **Container naming conflicts**: What happens if user runs `./coding-booth run` twice in same directory without `--name`? Currently fails on name collision - is this desired?

4. **Image naming convention**: Should `commit` suggest/enforce a naming convention? e.g., `cb/<project>:<timestamp>`

5. **UID/GID migration**: Should the blanket chown (current behavior) be kept as fallback, or replaced entirely with targeted migration?
