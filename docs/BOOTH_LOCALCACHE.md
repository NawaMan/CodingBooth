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
- [Initial Content](#initial-content)
- [Examples](#examples)
- [Available Cache Templates](#available-cache-templates)
- [User-Defined Cache in config.toml](#user-defined-cache-in-configtoml)

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

A template's `cache-files` / `cache-dirs` are recorded in `config.toml`, and every start creates
any that are missing — so a fresh clone, which has no `.booth/cache/`, gets the same mounts.

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

2. **Otherwise** — mount any individual **files** in this directory one by one (see [Single files](#single-files-are-kept-in-sync)), then continue traversing into subdirectories.

### Summary

| What's found                          | Mount behavior                | Traversal |
|---------------------------------------|-------------------------------|-----------|
| Directory with `.mount-this`          | Whole directory mount         | Stops     |
| Directory without `.mount-this`       | Not mounted (structural only) | Continues |
| File in a non-`.mount-this` directory | Individual file, kept in sync | N/A       |

### Why `.mount-this`?

Mounting individual files is the safe default — it never accidentally overrides container directories like `/home/coder/`. The `.mount-this` marker is an explicit opt-in for when you want an entire directory mounted (e.g., an app's data directory with many files).

### Single files are kept in sync

A folder is a real bind mount. A single file is not mounted at its own path, because a mounted
file cannot be replaced: a tool that saves by writing a new file and renaming it over the old one
gets `EBUSY` and loses the save. zsh saves its history that way, and so do GLib apps (xfconf) and
readline's full rewrite.

Instead the file is mounted under `/var/lib/codingbooth/file-sync/<path>`. At start the booth
copies it to `<path>` as a plain file, and `booth--file-sync` copies it back every 2 seconds when
the booth's copy changed, or brings a host-side edit in when only that side changed. The booth's
side wins when both did. A clean stop, and the end of a one-shot `booth -- <cmd>`, copy once more.

| What changes | Effect |
|--------------|--------|
| Rename-based saves | Work |
| Edit on the host while the booth runs | Reaches the booth within 2 seconds |
| Hard kill (`docker kill`, a crash) | Loses at most the last 2 seconds |
| Two booths of one folder, one file | Last writer wins; a live mount would have interleaved appends |

An image built before this (one without the `com.codingbooth.file-sync` label) gets the file
mounted directly, as before.

---

## Protected Paths

The following container paths must **not** be overridden. **If `.booth/cache/` contains an entry that maps to one of them, the booth will not start.**

| Path               | Reason                             |
|--------------------|------------------------------------|
| `/opt/codingbooth` | CodingBooth's own installation     |
| `/home/coder/code` | The bind-mounted project directory |

So `.booth/cache/opt/codingbooth/` or `.booth/cache/home/coder/code/` is an error, and the message names every offending path at once. Booth refuses rather than skipping the entry, because a silently-dropped mount looks exactly like a cache that inexplicably does not work.

### Cache and Shared on the same path

[Shared](BOOTH_SHARED.md) mounts the same way from `.booth/shared/`, and the two trees are
checked against each other at start:

| What overlaps | Result |
|---------------|--------|
| One container path in both (`.booth/cache/home/coder/x` and `.booth/shared/home/coder/x`) | **Refuses to start**, naming both — Docker cannot mount two things on one path |
| One inside the other (a Shared path inside a Cache folder, or the reverse) | Starts, with a one-line **notice** saying which part goes to git |

The second is allowed because it is sometimes meant — but it is easy to do by accident.
`google-chrome+profile-cache` (all of `.chrome-data`) with `google-chrome+bookmarks-shared`
(`.chrome-data/Default`) sends `Default/` to git, and `Default/` also holds cookies and saved
logins. `booth config` prints the same notice when the selection makes such a pair.

---

## Gitignore Requirement

**If `.booth/cache/` exists, it must be gitignored. If it is not, the booth will not start.**

This is not housekeeping. The cache is whatever the container writes to the mounted paths, and that can include live secrets — with `claude-code+settings-cache`, the host's `~/.claude/.credentials.json` is copied into `~/.claude/` by the `/etc/cb-home` override layer on every start, and because `~/.claude/` *is* the bind mount, the token is written straight into `.booth/cache/` inside your project. Same story for browser profiles and cloud CLI state.

The generated `.booth/.gitignore` from `booth config` always includes `cache/`. If you created `.booth/` manually, add it yourself:

```
cache/
```

CodingBooth asks git, not the `.gitignore` file, and refuses to start on either failure:

| Situation | What you get |
|-----------|--------------|
| Cache is gitignored | Starts normally |
| No `cache/` rule anywhere | `is NOT gitignored` — add the rule |
| Cache files are **tracked** | `is tracked by git` — `git rm -r --cached .booth/cache` |
| Project is not a git repo | Check skipped (nothing to commit to) |

The tracked case is the one that bites. **A gitignore rule does not untrack a file that is already committed** — git keeps committing it, and a check that only greps `.booth/.gitignore` for `cache/` would report everything as fine while your credentials go into every commit. If you hit it, untrack the files (they stay on disk) and **rotate any credential that was committed**.

---

## Initial Content

A declared Cache path starts empty unless a **seed** covers it. `.booth/cache-seed/` holds the
seeds; unlike `.booth/cache/` it is **committed**, so every clone gets them. It uses the same
layout: the tree mirrors the container's root, a file stands for itself, and a folder holding a
`.mount-this` marker stands for the whole folder.

Before mounting, booth copies each seed into `.booth/cache/` where that path is still missing:

| Seed | Copied when |
|---|---|
| A file | the Cache file is missing **or empty** — empty is what booth creates for a path with no seed, so a seed added later still reaches it |
| A marked folder, whole | the Cache folder does not exist — once it does, it is the user's, and a file deleted from it stays deleted |

A seed never replaces content, files at the seed's root (a `README.md`) are skipped, and the start
says what it seeded. `booth config` does the same as soon as it writes the files, so a fresh
configure already has the content.

Put files in `.booth/cache-seed/` by hand, or let a template ship them — `[files.cache-seed]`
inline, or a `cache-seed/` folder beside `template.toml`:

```toml
cache-files = ["home/coder/.config/tool/state.json"]

[files.cache-seed]
"home/coder/.config/tool/state.json" = '{"firstRun": false}'
```

`.booth/shared-seed/` and `[files.shared-seed]` do the same for [Shared](BOOTH_SHARED.md). There
the file is committed anyway, so a seed matters for a template: it is how one gives a shared file
its first content instead of an empty one.

Never put a secret in a seed: both seed folders are committed.

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

## Available Cache Templates

Many templates include built-in cache extensions you can enable during `booth config`:

### Shell & REPL History (`cache-files`)

| Template Selection | What's Cached |
|--------------------|---------------|
| `shell-history` | `~/.bash_history`, `~/.zsh_history` |
| `python+repl-history` | `~/.python_history` |
| `nodejs+repl-history` | `~/.node_repl_history` |
| `ruby+repl-history` | `~/.irb_history` |

### Database CLI History

| Template Selection | What's Cached |
|--------------------|---------------|
| `postgresql+cli-history` | `~/.psql_history` |
| `mysql+cli-history` | `~/.mysql_history` |
| `sqlite+cli-history` | `~/.sqlite_history` |
| `redis+cli-history` | `~/.rediscli_history` |
| `mongodb+cli-history` | `~/.mongosh/` (directory) |

### REPL History (`cache-dirs`)

| Template Selection | What's Cached |
|--------------------|---------------|
| `elixir+repl-history` | `~/.cache/erlang-history/` |
| `php+repl-history` | `~/.config/psysh/` |

### IDE & Editor Settings (`cache-dirs`)

| Template Selection | What's Cached |
|--------------------|---------------|
| `claude-code+settings-cache` | `~/.claude/` |
| `codeserver+settings-cache` | `~/.local/share/code-server/` |
| `neovim+data-cache` | `~/.local/share/nvim/`, `~/.local/state/nvim/` |

### Desktop Icons (`cache-dirs`)

| Template Selection | What's Cached |
|--------------------|---------------|
| `xfce+desktop-icons-cache` | `~/Desktop/`, `~/.config/xfce4/desktop/` |
| `lxqt+desktop-icons-cache` | `~/Desktop/`, `~/.config/pcmanfm-qt/` |

Keeps both the launcher set and where each icon sits. Launchers the image ships are
still re-seeded from `/etc/skel/Desktop` on every start (no-clobber), so a rebuilt
image's new icons appear and take a free slot without disturbing icons you placed —
which `--persist-home` does *not* do, since it skips seeding after the first run.

On LXQt, pcmanfm-qt writes positions when the desktop process exits rather than on
each drag, so stop the booth cleanly. There is no KDE equivalent: Plasma stores the
layout in a single `~/.config` file it rewrites by rename, which defeats a bind
mount, a symlink, and a copy-back mirror alike. Use `--persist-home` there.

For the team/git version of either, see [Shared State](BOOTH_SHARED.md).

### Secrets (`cache-dirs`)

| Template Selection | What's Cached |
|--------------------|---------------|
| `envfolio+store-cache` | `~/.local/share/envfolio/` (the store is `store/` inside it), `~/.gnupg/` — both created `0700` |

The EnvFolio store and the GPG keyring that holds its private key (still protected by its
passphrase). The extension sets `ENVFOLIO_STORE_DIR` to a folder *inside* the cached one: a
mounted folder always holds the cache's `.mount-this` marker, and `envfolio store init` /
`store restore` only take a folder that is missing or empty. `.booth/cache/` stays on this machine
and out of git; `envfolio store backup` /
`restore` is the portable way to move a store.

### Browser Profiles (`cache-dirs`)

| Template Selection | What's Cached |
|--------------------|---------------|
| `firefox+profile-cache` | `~/.mozilla/` (can be large) |
| `chromium+profile-cache` | `~/.chrome-data/` (can be large; wrapper `--user-data-dir`) |
| `google-chrome+profile-cache` | `~/.chrome-data/` (can be large; wrapper `--user-data-dir`) |

> Browser profiles can grow to hundreds of megabytes. These extensions are opt-in and never auto-selected.
>
> For **team-shared bookmarks** (git-friendly, not full profiles), see [Shared State](BOOTH_SHARED.md) and `+bookmarks-shared`.

### Android Virtual Device (`cache-dirs`)

| Template Selection | What's Cached |
|--------------------|---------------|
| `android-sdk+emulator+avd-cache` | `~/.android/` (~2.8 GB — see below) |

The largest cache extension by a wide margin, and the only one with a shutdown requirement.

- **Size.** Roughly 450 MB of device disk plus a ~2.3 GB RAM snapshot. The snapshot is what makes a restore take seconds instead of half a minute (measured: 26–38s cold, 7–16s restored), so it is the cost of the feature rather than waste.
- **Stop with `cb-android-emulator-stop`.** The emulator does not reliably save a Quick Boot snapshot on its own way out — neither `adb emu kill` nor a SIGTERM leaves one — so the next start restores the previously saved snapshot and silently rolls back the session. The stop command saves first, then kills.
- **Stale locks are handled for you.** A container exit is always an unclean exit as far as the emulator is concerned, and it leaves `avd/running/` and `*.lock` behind. Cached, those would block every later start with *"a snapshot operation is pending and timeout has expired"*. The launcher clears them before starting.

Delete `.booth/cache/home/coder/.android` at any time to reclaim the space; the next start builds a clean device.

Usage example:

```
booth config --no-tui . --select go/shell-history/python+repl-history/redis+cli-history
```

---

## User-Defined Cache in config.toml

For tools without a built-in template, you can declare custom cache paths directly in `.booth/config.toml`:

```toml
cache-files = [
    "home/coder/.custom_history",
]

cache-dirs = [
    "home/coder/.custom_app_data",
]
```

Or via CLI:

```
booth config --no-tui . --select go --set cache-files=home/coder/.custom_history
booth config --no-tui . --select go --set cache-dirs=home/coder/.custom_app_data
```

- `cache-files` creates individual empty files that are bind-mounted as files — or, when
  `.booth/cache-seed/` has that path, a copy of the seed ([Initial Content](#initial-content))
- `cache-dirs` creates directories with `.mount-this` markers that are bind-mounted as whole directories
- A `cache-dirs` entry may end in an octal mode — `home/coder/.gnupg:0700` — for a tool that refuses a folder others can read (gpg, ssh). The mode is set when the folder is created; an existing folder keeps its own
- These paths are merged with any cache paths from selected templates — duplicates are automatically removed
- Paths are relative to the container root (e.g., `home/coder/.foo` maps to `/home/coder/.foo`)


---

Back to [README](../README.md)
