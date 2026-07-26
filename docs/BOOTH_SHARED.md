# Shared State (Team / Git)

> Files outside `/home/coder/code` that are **live** in the container **and** meant to be **committed**.

`.booth/shared/` is a host-side mirror of selected container paths. Its structure mirrors the container filesystem — the same layout rules as [`.booth/cache/`](BOOTH_LOCALCACHE.md) — but it is **intended for git**. Edits inside the booth write straight into the project tree so teammates pick them up on the next pull.

```
.booth/shared/
  home/coder/
    .chrome-data/Default/Bookmarks
    .local/share/code-server/User/settings.json
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Shared vs Cache vs Home](#shared-vs-cache-vs-home)
- [How It Works](#how-it-works)
- [Mount Rules](#mount-rules)
- [Protected Paths](#protected-paths)
- [What Belongs Here](#what-belongs-here)
- [Available Shared Templates](#available-shared-templates)
- [User-Defined Shared Paths](#user-defined-shared-paths)
- [Secrets and Hygiene](#secrets-and-hygiene)

---

## Overview

By default, everything outside `/home/coder/code` is ephemeral. Three mechanisms keep selected paths around:

| Mechanism | Host path | Live bind mount? | Git? |
|-----------|-----------|------------------|------|
| **Shared** | `.booth/shared/` | Yes | **Yes — intended** |
| **Local cache** | `.booth/cache/` | Yes | **No — forbidden** |
| **Home seed / override** | `.booth/home-seed/`, `.booth/home/` | No (copy at start) | Yes |

Use **shared** when the team should edit the same file (bookmark bar, editor settings, DB connection defs) and commit it. Use **cache** for personal session state (shell history, full browser profile). Use **home-seed** when you only need a one-time default that users may then diverge from.

---

## Shared vs Cache vs Home

| | **shared** | **cache** | **home / home-seed** |
|--|------------|-----------|----------------------|
| Container effect | Bind mount onto home/app path | Bind mount | Copy into `~` at start |
| Survives restart | Yes | Yes | Seed once / override always |
| Live write-back to project | Yes | Yes (local only) | No |
| Git | Commit it | Must stay untracked | Commit it |
| Typical content | Bookmarks, settings.json, data-sources.json | History, full profiles, tokens | Dotfiles, team configs |

---

## How It Works

The directory structure inside `.booth/shared/` mirrors the container root. CodingBooth walks the tree and creates bind mounts the same way as [local cache](BOOTH_LOCALCACHE.md):

```
.booth/shared/
  home/coder/
    .chrome-data/Default/Bookmarks
      --> -v .booth/shared/home/coder/.chrome-data/Default/Bookmarks:/home/coder/.chrome-data/Default/Bookmarks
```

Templates declare `shared-files` and `shared-dirs`. On `booth config`, empty files / `.mount-this` markers are created under `.booth/shared/` (no-clobber). At start, booth also re-materializes any paths still listed in `config.toml` if files were deleted.

Unlike cache, there is **no** gitignore requirement. Shared state is expected to be versioned.

---

## Mount Rules

Same rules as [local cache](BOOTH_LOCALCACHE.md#mount-rules):

1. **Directory with `.mount-this`** — mount the whole directory; stop descending.
2. **Otherwise** — mount individual **files**; recurse into subdirectories.

| What's found | Mount behavior |
|--------------|----------------|
| Directory with `.mount-this` | Whole directory mount |
| File in a non-marker directory | Individual file mount |
| Directory without marker | Structural only (not mounted itself) |

---

## Protected Paths

The following container paths must not be overridden. If `.booth/shared/` would mount onto one of them, the booth **refuses to start**:

| Path | Reason |
|------|--------|
| `/opt/codingbooth` | CodingBooth install |
| `/home/coder/code` | Project bind mount |

---

## What Belongs Here

**Good candidates**

- Small text/JSON configs the whole team should share
- Chrome/Chromium **Bookmarks** (not History, not the full profile)
- code-server / VS Code **`User/settings.json`**
- DBeaver **`data-sources.json`** without passwords

**Keep out**

- Cookies, login sessions, OAuth tokens
- Full browser profiles (`~/.mozilla`, `~/.chrome-data` wholesale)
- Shell history, package caches
- Database passwords inside connection files
- Large binary SQLite history databases (poor merges)

For full browser profiles or IDE extension stores, use **`+profile-cache` / `+settings-cache`** (local) or **`--persist-home`**.

---

## Available Shared Templates

| Template selection | Shared path |
|--------------------|-------------|
| `google-chrome+bookmarks-shared` | `~/.chrome-data/Default/` (**directory**) |
| `chromium+bookmarks-shared` | `~/.chrome-data/Default/` (**directory**, same path as Chrome) |
| `firefox+bookmarks-shared` | `~/.mozilla/firefox/` (**directory**) |
| `codeserver+settings-shared` | `~/.local/share/code-server/User/settings.json` |
| `dbeaver+connections-shared` | `~/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json` |

All are **opt-in** (`auto-select = false`).

```bash
booth config --no-tui . \
  --select google-chrome+bookmarks-shared/dbeaver+connections-shared/codeserver+settings-shared
```

**Chrome data dir note:** CodingBooth’s Chrome/Chromium wrappers set `--user-data-dir=~/.chrome-data`. Shared and profile-cache paths use that directory, not `~/.config/google-chrome`.

### Chrome / Chromium (directory mount required)

Chrome **and** CodingBooth’s Chromium wrapper both use
`--user-data-dir=~/.chrome-data`. They share the same `Default/` tree — so
`google-chrome+bookmarks-shared` and `chromium+bookmarks-shared` declare the
**same** `shared-dirs` path.

Chrome/Chromium save bookmarks by writing `Bookmarks.tmp` then **renaming** over
`Bookmarks`. A **file** bind-mount of `Bookmarks` alone is detached by that
rename. Extensions use `shared-dirs` for `…/Default/`.

`Default/` can also grow cookies, Local Storage, etc. Put a `.gitignore` that
keeps only `Bookmarks` / `Bookmarks.bak` before committing.

### Firefox (directory mount required)

Firefox profiles live under `~/.mozilla/firefox/<id>.default-release/` with a
random id and a `profiles.ini`. Mount the whole `firefox/` directory so first
launch can create `profiles.ini` + profile in place. Bookmarks live in
`places.sqlite` (binary; also holds history).

### Test checklist (desktop)

| Browser | Install | Shared path | Host check after bookmark |
|---------|---------|-------------|---------------------------|
| Chrome | `setup google-chrome` | `.booth/shared/…/.chrome-data/Default/` | `Bookmarks` mtime updates |
| Chromium | `setup chromium-browser` | same as Chrome | same |
| Firefox | `setup firefox` | `.booth/shared/…/.mozilla/firefox/` | `**/places.sqlite` mtime updates |

Launch via the desktop icon / wrapper (not a host browser). Restart the booth
(not only the browser) to confirm persistence.

**First commit workflow (Chrome/Chromium):**

1. Select `google-chrome+bookmarks-shared` (or chromium) and start a desktop
   booth with a CLI that implements `.booth/shared/`.
2. Open the browser (wrapper → `~/.chrome-data`).
3. Add bookmarks; they land under
   `.booth/shared/home/coder/.chrome-data/Default/Bookmarks`.
4. Commit `Bookmarks` only (sample `.gitignore` under that directory).

---

## User-Defined Shared Paths

Declare paths in `.booth/config.toml` without a template:

```toml
shared-files = [
    "home/coder/.config/myapp/config.yaml",
]

shared-dirs = [
    "home/coder/.config/myapp/snippets",
]
```

Or via CLI:

```bash
booth config --no-tui . --set shared-files=home/coder/.config/myapp/config.yaml
booth config --no-tui . --set shared-dirs=home/coder/.config/myapp/snippets
```

Paths are relative to the container root (`home/coder/.foo` → `/home/coder/.foo`).

---

## Secrets and Hygiene

- Treat `.booth/shared/` like source code: **no secrets**.
- Prefer empty password fields and [host credential seeding](BOOTH_HOME.md) for real credentials.
- Review diffs before commit — a browser can rewrite more than you expect (Chrome may rewrite Bookmarks on launch).
- If a path might hold credentials, use **cache** or host seed instead of shared.

---

Back to [README](../README.md)
