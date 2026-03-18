# Local Cache

> Files that stay across sessions but live only on this host.

`.booth/cache/` is a gitignored directory for persisting files across container sessions. Its structure mirrors the container filesystem — files placed here are automatically bind-mounted into the container at the corresponding path. Think of it as a local, disposable cache: useful to keep around, but safe to delete at any time.

```
.booth/cache/
  home/coder/
    .bash_history
    .zsh_history
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Mount Rules](#mount-rules)
- [Protected Paths](#protected-paths)
- [Gitignore Requirement](#gitignore-requirement)
- [Examples](#examples)
- [Implementation Plan](#implementation-plan)

---

## Overview

Container home directories are ephemeral — shell history, tool configs, and other runtime state are lost every time the container is recreated. `.booth/cache/` solves this by letting users place files and directories that get bind-mounted into the container automatically.

The directory is:
- **Per-project** — lives inside `.booth/`, scoped to this project
- **Per-host** — not committed to git, stays on this machine only
- **Disposable** — safe to delete; the booth still works without it

---

## How It Works

The directory structure inside `.booth/cache/` mirrors the container's root filesystem. CodingBooth traverses the tree and creates bind mounts based on what it finds.

```
.booth/cache/
  home/coder/
    .bash_history        --> -v .booth/cache/home/coder/.bash_history:/home/coder/.bash_history
    .zsh_history         --> -v .booth/cache/home/coder/.zsh_history:/home/coder/.zsh_history
  opt/ex-app/
    .mount-this          --> -v .booth/cache/opt/ex-app:/opt/ex-app (whole directory)
    config.yaml
    data/
      stuff.db
```

---

## Mount Rules

CodingBooth walks `.booth/cache/` top-down. At each directory:

1. **If `.mount-this` marker exists** — mount the entire directory at its corresponding container path. Stop traversing into it. The `.mount-this` file itself is not included in the mount content (it can be empty).

2. **Otherwise** — mount any individual **files** in this directory as file bind mounts, then continue traversing into subdirectories.

### Summary

| What's found                          | Mount behavior                | Traversal |
|---------------------------------------|-------------------------------|-----------|
| Directory with `.mount-this`          | Whole directory mount         | Stops     |
| Directory without `.mount-this`       | Not mounted (structural only) | Continues |
| File in a non-`.mount-this` directory | Individual file mount         | N/A       |

### Why `.mount-this`?

Mounting individual files is the safe default — it never accidentally overrides container directories like `/home/coder/`. The `.mount-this` marker is an explicit opt-in for when you want an entire directory mounted (e.g., an app's data directory with many files).

---

## Protected Paths

The following container paths must **not** be overridden. CodingBooth will refuse to mount (and print an error) if `.booth/cache/` contains entries that would map to:

| Path               | Reason                             |
|--------------------|------------------------------------|
| `/opt/codingbooth` | CodingBooth's own installation     |
| `/home/coder/code` | The bind-mounted project directory |

For example, `.booth/cache/opt/codingbooth/` or `.booth/cache/home/coder/code/` will cause an error.

---

## Gitignore Requirement

If `.booth/cache/` exists, it **must** be listed in `.booth/.gitignore`. CodingBooth checks for this at startup and errors out if the entry is missing. This prevents accidentally committing host-specific cached state.

The generated `.booth/.gitignore` from `booth init` always includes `cache/`. If you created `.booth/` manually, add it yourself:

```
cache/
```

---

## Examples

### Shell history across sessions

```
.booth/cache/
  home/coder/
    .bash_history
    .zsh_history
```

Both files are mounted individually. Your command history survives container recreation.

### Application data directory

```
.booth/cache/
  opt/ex-app/
    .mount-this
    config.yaml
    data/
      app.db
```

The entire `opt/ex-app/` directory is mounted at `/opt/ex-app` in the container, including `data/app.db`. The `.mount-this` file signals "mount this whole directory."

### Mixed: individual files and directory mounts

```
.booth/cache/
  home/coder/
    .bash_history
    .gitconfig
  var/lib/postgresql/
    .mount-this
    data/
      ...
```

History and gitconfig are individual file mounts. The PostgreSQL data directory is a whole-directory mount.

### Claude Code settings persistence

```
.booth/cache/
  home/coder/
    .claude/
      .mount-this
```

The entire `~/.claude/` directory is mounted as a single bind mount. Claude Code settings, projects, memory, and conversation history all persist across container sessions. Fresh credentials are provided separately via `/etc/cb-home/` override mount (see [Home Directory Guide](BOOTH_HOME.md#fine-grained-copy-with-mount-this)).

---

## Implementation Plan

### 1. Core: gitignore generation

**File:** `cli/src/pkg/boothinit/output/writer.go`

Add `cache/` to the always-generated `.booth/.gitignore` content.

### 2. Core: gitignore validation at startup

**File:** `cli/src/pkg/booth/booth.go`

When `.booth/cache/` exists on the host, verify that `.booth/.gitignore` contains a `cache/` entry. Error out with a clear message if missing.

### 3. Core: cache directory traversal and mount generation

**File:** `cli/src/pkg/booth/booth.go` (or new file `cli/src/pkg/booth/cache_mounts.go`)

After `addReadOnlyBoothDir`, scan `.booth/cache/` if it exists:

- Walk the directory tree top-down
- Apply the mount rules (`.mount-this` = directory mount, otherwise file mounts)
- Validate against protected paths (`/opt/codingbooth`, `/home/coder/code`)
- Append generated `-v` flags to `CommonArgs`

### 4. Template pipeline: cache file support

Thread a new `Cache` field through the existing template pipeline so templates can declare files to touch in `.booth/cache/`. Since cache files are just empty files (no content), use a simple `cache-files` string array in `template.toml`.

**Files to modify:**

| File | Change |
|------|--------|
| `cli/src/pkg/boothinit/template/model.go` | Add `CacheFiles []string` and `CacheDirs []string` to `Template` struct |
| `cli/src/pkg/boothinit/template/loader.go` | Parse `cache-files` and `cache-dirs` from `template.toml` |
| `cli/src/pkg/boothinit/compiler/compiler.go` | Merge cache refs from all selected templates into `BoothOutput.Cache` and `BoothOutput.CacheDirs` |
| `cli/src/pkg/boothinit/output/model.go` | Add `Cache []FileContent` and `CacheDirs []FileContent` to `BoothOutput` struct |
| `cli/src/pkg/boothinit/output/writer.go` | Touch empty files and create directories with `.mount-this` markers |

**Template syntax:**

```toml
# In template.toml or extension.toml

# Touch individual empty files (for simple history files)
cache-files = [
    "home/coder/.bash_history",
    "home/coder/.zsh_history",
]

# Create directories with .mount-this marker (for complex tool state)
cache-dirs = [
    "home/coder/.claude",
]
```

Each path is relative to `.booth/cache/` and mirrors the container filesystem.

- `cache-files`: Creates parent directories and touches empty files.
- `cache-dirs`: Creates the directory and a `.mount-this` marker inside it, causing the entire directory to be mounted as a single bind mount.

Existing files and markers are left untouched (no-clobber) so user data is never overwritten on `booth init adjust`.

### 5. Template: `shell-history`

**File:** `templates/tools/shell-history/template.toml` (new)

```toml
display-name = "Shell History"
display-disc = "Persist bash and zsh history across sessions"
display-order = 33
tags = ["shell", "history", "persistence"]

cache-files = [
    "home/coder/.bash_history",
    "home/coder/.zsh_history",
]
```

No Boothfile segments or startup scripts needed — bash and zsh already write to `~/.bash_history` and `~/.zsh_history` by default, and the core cache mount maps them automatically.

### 5b. Extension: Claude Code `settings-cache`

**File:** `templates/ai-tools/claude-code/settings-cache--extension.toml`

```toml
display-name = "Settings Cache"
display-disc = "Persist Claude Code settings and projects across sessions"
display-order = 91
auto-select = true
tags = ["claude", "persistence", "cache"]

cache-dirs = [
    "home/coder/.claude",
]
```

This creates `.booth/cache/home/coder/.claude/.mount-this`, causing the entire `~/.claude/` directory to be persisted via cache mount. Used in combination with the credential extension which seeds fresh `.credentials.json` via `/etc/cb-home/` override.

### 6. Cache extensions for existing templates

Add `cache-files` extensions to existing language/tool templates. Each extension simply declares the history file to touch. No startup scripts needed — the tools already write to their default history paths.

| Parent template | Extension name | File | Cache file |
|-----------------|---------------|------|------------|
| `python` | `repl-history` | `templates/languages/python/repl-history--extension.toml` | `home/coder/.python_history` |
| `nodejs` | `repl-history` | `templates/languages/nodejs/repl-history--extension.toml` | `home/coder/.node_repl_history` |
| `postgresql` | `cli-history` | `templates/databases/postgresql/cli-history--extension.toml` | `home/coder/.psql_history` |
| `mysql` | `cli-history` | `templates/databases/mysql/cli-history--extension.toml` | `home/coder/.mysql_history` |
| `sqlite` | `cli-history` | `templates/databases/sqlite/cli-history--extension.toml` | `home/coder/.sqlite_history` |

Usage: `booth init new --select shell-history/python+repl-history/postgresql+cli-history`

### 7. Init test: `tests/init/test51-init-cache-files.sh`

**Pattern:** Uses `test-helpers--source.sh` (same as existing init tests like test47, test48). Runs `booth init` and checks the generated output on the host filesystem — no Docker needed.

**Tests:**

1. `booth init new --select shell-history` creates `.booth/cache/home/coder/.bash_history`
2. `booth init new --select shell-history` creates `.booth/cache/home/coder/.zsh_history`
3. `.booth/.gitignore` contains `cache/`
4. `booth init new --select python+repl-history` creates `.booth/cache/home/coder/.python_history`
5. Cache files are empty (zero bytes)
6. `booth init adjust --select shell-history` does NOT overwrite existing cache files (write content to file, adjust, verify content preserved)
7. `booth init new --select go` (no cache-files) does NOT create `.booth/cache/` directory

**File:** `tests/init/test51-init-cache-files.sh` (new)

### 8. Complex test: `tests/complex/test-cache-mount/`

**Pattern:** Uses `common--source.sh` + `run_coding_booth` (same as test-booth-home-seed, test-lifecycle-fs-persistence). Requires Docker — runs an actual container and verifies mount behavior.

**Structure:**
```
tests/complex/test-cache-mount/
  .booth/
    config.toml           # minimal config (variant = "base")
    Boothfile             # minimal Dockerfile (FROM nawaman/codingbooth:base-latest)
    cache/
      home/coder/
        .bash_history     # pre-populated with "CACHED_LINE_1"
      opt/testapp/
        .mount-this       # directory mount marker
        data.txt          # pre-populated with "CACHED_DATA"
  test--cache-mount.sh
```

**Tests:**

1. `.booth/cache/home/coder/.bash_history` is mounted and readable inside the container at `/home/coder/.bash_history` (content matches "CACHED_LINE_1")
2. `.booth/cache/opt/testapp/` is mounted as whole directory at `/opt/testapp` (content of `data.txt` matches "CACHED_DATA")
3. Writing to `/home/coder/.bash_history` inside the container persists to host `.booth/cache/home/coder/.bash_history`
4. Protected path rejection: `.booth/cache/home/coder/code/` causes an error (test creates the dir, runs booth, asserts non-zero exit)

**File:** `tests/complex/test-cache-mount/test--cache-mount.sh` (new)

### 9. Verification

- `go build` the CLI
- Run init tests: `cd tests/init && bash test51-init-cache-files.sh`
- Run complex test: `cd tests/complex/test-cache-mount && bash test--cache-mount.sh`
- Run full test suites: `tests/init/run-all-tests.sh` and `tests/complex/run-complex-tests.sh`
