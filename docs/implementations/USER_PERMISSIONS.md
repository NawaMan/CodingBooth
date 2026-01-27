# User Permissions Implementation

> [!IMPORTANT]
> **Why this matters:** This feature is the magic that makes CodingBooth feel native.
It completely eliminates “permission denied” errors and root-owned files on your host machine — one of the most painful and common problems with Docker-based development.

**Develop inside containers without ever thinking about file permissions.**
CodingBooth dynamically mirrors your host identity inside every container, ensuring that every file you create is owned by you — not root, not UID 1000, and not some anonymous user. This removes the most persistent friction in container workflows: broken permissions, unreadable files, and constant sudo usage. By rewriting the container user at startup to match your host UID and GID, CodingBooth delivers seamless file ownership, clean Git workflows, and team-safe collaboration — all while keeping processes non-root and environments fully reproducible.

This document explains how CodingBooth handles user permissions to ensure seamless file ownership between host and container.

---

## The Problem

When developing inside Docker containers, files created inside often end up owned by the container's default user (typically `root` or a fixed UID like 1000). This causes permission issues on the host:

- Files created in mounted volumes are owned by a different user
- You can't edit or delete files without `sudo`
- Git commits show different authors
- Team members with different UIDs step on each other's files

---

## The Solution: Dynamic UID/GID Mapping

CodingBooth solves this by dynamically aligning the container's `coder` user with your host's UID/GID at container startup.

### How It Works

```
Host (UID=1001, GID=1001)
    │
    ▼ passes HOST_UID=1001, HOST_GID=1001
    │
Container starts
    │
    ▼ booth-entry runs as root
    │
    ├─► Ensures 'coder' group has GID=1001
    ├─► Ensures 'coder' user has UID=1001
    ├─► Fixes ownership of /home/coder
    ├─► Configures passwordless sudo
    │
    ▼ exec as 'coder' (UID=1001)
    │
All processes run as coder
Files created are owned by 1001:1001 (your host user!)
```

---

## Implementation Details

### 1. Passing Host UID/GID

The launcher (`coding-booth`) automatically detects and passes your UID/GID.
Ref: `cli/src/pkg/booth/booth.go` (PrepareCommonArgs function)

```go
// From the launcher (simplified)
builder.CommonArgs.Append(ilist.NewList[string]("-e", "HOST_UID="+ctx.HostUID()))
builder.CommonArgs.Append(ilist.NewList[string]("-e", "HOST_GID="+ctx.HostGID()))
```

### 2. The Entry Script (`booth-entry`)

The entry script (`variants/base/booth-entry`) runs as root and performs these steps:

#### Step 1: Ensure Group Exists

```bash
# Create 'coder' group if it doesn't exist
# Prefer HOST_GID if available
if ! getent group "$USER_NAME" >/dev/null 2>&1; then
  if getent group "$HOST_GID" >/dev/null 2>&1; then
    groupadd "$USER_NAME"
  else
    groupadd -g "$HOST_GID" "$USER_NAME"
  fi
fi
```

#### Step 2: Relocate Conflicting GID

If another group already has HOST_GID, move it to a free GID:

```bash
owner_of_host_gid="$(getent group "$HOST_GID" | cut -d: -f1 || true)"
if [ -n "$owner_of_host_gid" ] && [ "$owner_of_host_gid" != "$USER_NAME" ]; then
  tmp_gid="$(find_free_gid)"
  groupmod -g "$tmp_gid" "$owner_of_host_gid"
fi
```

#### Step 3: Set Coder Group's GID

```bash
current_gid="$(getent group "$USER_NAME" | cut -d: -f3)"
if [ "$current_gid" != "$HOST_GID" ]; then
  groupmod -g "$HOST_GID" "$USER_NAME"
fi
```

#### Step 4: Ensure User Exists with Correct UID

```bash
# If another user has HOST_UID, move them aside
if [ -n "$existing_uid_user" ] && [ "$existing_uid_user" != "$USER_NAME" ]; then
  temp_uid="$(find_free_uid)"
  usermod -u "$temp_uid" "$existing_uid_user"
fi
# Set coder's UID
usermod -u "$HOST_UID" -g "$USER_NAME" -s "$USER_SHELL" "$USER_NAME"
```

#### Step 5: Fix File Ownership

After UID/GID changes, fix ownership of files in home directory:

```bash
# Change ownership from old UID to new UID
find "$HOME_DIR" -xdev -path "$CODE_DIR" -prune -o \
  -user "$ORIG_UID" -exec chown "$HOST_UID" {} + 2>/dev/null || true

# Change group from old GID to new GID
find "$HOME_DIR" -xdev -path "$CODE_DIR" -prune -o \
  -group "$ORIG_GID" -exec chgrp "$HOST_GID" {} + 2>/dev/null || true
```

Note: The code directory (`/home/coder/code`) is excluded because it's bind-mounted from the host and already has correct ownership.

### 3. Passwordless Sudo

The entry script grants passwordless sudo to `coder`:

```bash
echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USER_NAME}
chmod 0440 /etc/sudoers.d/${USER_NAME}
```

This is necessary because:
- Setup scripts may need root access during development
- Some tools require sudo for installation
- It improves developer experience without security concerns (containers are ephemeral)

### 4. Final Execution

After all setup, the entry script drops privileges and runs the requested command:

```bash
if [ "$#" -eq 0 ]; then
  exec runuser -u "$USER_NAME" --login
else
  exec runuser -u "$USER_NAME" -- "$@"
fi
```

---

## Design Decisions

### Why Not Just Use `--user` Flag?

Docker's `--user` flag sets the UID/GID but doesn't create a proper user entry:

```bash
docker run --user 1001:1001 ubuntu whoami
# Output: I have no name!
```

This causes issues with:
- Tools that need a valid username
- Home directory setup
- Shell configuration
- sudo access

### Why Modify System Users at Runtime?

The alternative approaches have drawbacks:

| Approach | Problem |
|----------|---------|
| Build-time UID | Only works for one UID; breaks for other users |
| `--user` flag | No username, no home, no sudo |
| Fixed UID 1000 | Conflicts with some hosts; permission issues |
| Run as root | All files owned by root; security concerns |

Runtime modification handles all cases cleanly.

### Why Start from GID 2000 for Relocations?

```bash
find_free_uid() { local uid=2000; ... }
find_free_gid() { local gid=2000; ... }
```

Starting from 2000 avoids conflicts with:
- System users/groups (typically < 1000)
- Default user ranges (typically 1000-1999)
- Host users that might be mapped in

---

## File Permissions on Mount Points

The `/home/coder/code` directory is bind-mounted from the host. Files there:

- Retain their host ownership
- Are immediately accessible by the aligned `coder` user
- Changes are reflected on host in real-time

---

## Troubleshooting

### "Permission denied" on mounted files

Check that HOST_UID/HOST_GID match the file ownership on host:

```bash
# On host
ls -ln /path/to/project
# Note the UID/GID columns

# In container
id
# Compare with above
```

### "No such user" errors

Some tools cache user info. Try:

```bash
getent passwd coder
# Should show coder with correct UID
```

### Files still owned by root

Check if booth-entry ran successfully:

```bash
cat /tmp/startups.log
# Look for errors in user setup
```

---

## Related Files

- `variants/base/booth-entry` — The main entry script
- `variants/base/Dockerfile` — Base image with user creation
- `cli/src/pkg/booth/booth.go` — Passes HOST_UID/HOST_GID
