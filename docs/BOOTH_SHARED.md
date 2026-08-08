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
- Chrome/Chromium **Bookmarks**, **Preferences**, **Extensions/** (under shared, not cache)
- Firefox **profile tree** (bookmarks, prefs, add-ons under `~/.mozilla/firefox/`)
- code-server / VS Code **`User/settings.json`**
- DBeaver **`data-sources.json`** without passwords

**Keep out of shared (and never use cache for team state)**

- Cookies, login sessions, OAuth tokens, extension *storage* secrets
- Shell history, package caches
- Database passwords inside connection files

**Local-only** full browser profiles stay on **`+profile-cache`** (`.booth/cache/`,
gitignored) or **`--persist-home`**. Team-facing browser state uses **shared only**.

---

## Available Shared Templates

### Browsers (all `shared-dirs` / `shared-files` — **no cache**)

| Selection | Path under `.booth/shared/` | Notes |
|-----------|----------------------------|--------|
| `google-chrome+bookmarks-shared` | `…/.chrome-data/Default/` | Bookmarks; dir mount |
| `google-chrome+settings-shared` | `…/.chrome-data/Default/` | Preferences etc.; same as bookmarks |
| `google-chrome+extensions-shared` | `…/.chrome-data/Default/Extensions/` | CRX trees only (not Local Extension Settings) |
| `chromium+bookmarks-shared` | same Default/ as Chrome | Same wrapper data dir |
| `chromium+settings-shared` | same Default/ | |
| `chromium+extensions-shared` | same Extensions/ | |
| `firefox+bookmarks-shared` | `…/.mozilla/firefox/` | places.sqlite + profile |
| `firefox+settings-shared` | `…/.mozilla/firefox/` | prefs.js etc. |
| `firefox+extensions-shared` | `…/.mozilla/firefox/` | add-ons live in the profile |

Selecting bookmarks **or** settings for Chrome is enough for both (same `Default/`).
Selecting bookmarks **or** settings **or** extensions for Firefox is enough for all
three (same `firefox/` tree). Extensions-only Chrome mount is for sharing add-ons
without the rest of `Default/`.

### Managed policies (build-time, not shared/cache)

| Selection | Effect |
|-----------|--------|
| `google-chrome+managed-policies` / `chromium+managed-policies` | `setup chrome-managed-policies` → `/etc/opt/chrome/policies/managed/` |
| `firefox+managed-policies` | `setup firefox-managed-policies` → `/etc/firefox/policies/policies.json` |

Sample policies disable password manager / sync-friendly sign-in and enable the
bookmark bar. Edit the setup scripts under `variants/base/setups/` for your team.

### Desktop icons (`shared-dirs`)

| Selection | Path under `.booth/shared/` | Notes |
|-----------|----------------------------|--------|
| `xfce+desktop-icons-shared` | `…/Desktop/`, `…/.config/xfce4/desktop/` | Layout file is named after the workarea, so it applies only to teammates on the same `GEOMETRY`; others get the default arrangement |
| `lxqt+desktop-icons-shared` | `…/Desktop/`, `…/.config/pcmanfm-qt/` | Positions are plain pixel coordinates, so they carry across resolutions |

Both mount `~/Desktop` itself, and the image's own launchers are re-seeded into it on
every start — committing those freezes a stale copy, because the seed is no-clobber.
Use the sample gitignores below and commit only launchers your team wrote.

**No KDE equivalent.** Plasma keeps the desktop layout in a single `~/.config` file it
rewrites by rename. A file bind mount fails (`EBUSY`), a symlink is replaced by the
first save, and a copy-back mirror is worse than nothing — Plasma regenerates the
layout at session start and the mirror then overwrites the good saved copy with it.
`--persist-home` is the working answer for KDE.

### Sample gitignores

| File | Use under |
|------|-----------|
| [`docs/samples/browser-shared-chrome-Default.gitignore`](samples/browser-shared-chrome-Default.gitignore) | `.booth/shared/…/.chrome-data/Default/` |
| [`docs/samples/browser-shared-firefox.gitignore`](samples/browser-shared-firefox.gitignore) | `.booth/shared/…/.mozilla/firefox/` |
| [`docs/samples/desktop-shared-xfce-Desktop.gitignore`](samples/desktop-shared-xfce-Desktop.gitignore) | `.booth/shared/…/Desktop/` (XFCE) |
| [`docs/samples/desktop-shared-xfce-layout.gitignore`](samples/desktop-shared-xfce-layout.gitignore) | `.booth/shared/…/.config/xfce4/desktop/` |
| [`docs/samples/desktop-shared-lxqt-Desktop.gitignore`](samples/desktop-shared-lxqt-Desktop.gitignore) | `.booth/shared/…/Desktop/` (LXQt) |
| [`docs/samples/desktop-shared-lxqt-profile.gitignore`](samples/desktop-shared-lxqt-profile.gitignore) | `.booth/shared/…/.config/pcmanfm-qt/` |

### Editors & tools (shared only — **no secrets**)

| Selection | Path | Share | Never share |
|-----------|------|-------|-------------|
| `codeserver+settings-shared` | `User/settings.json` | team editor prefs | tokens, proxy passwords in settings |
| `codeserver+keybindings-shared` | `User/keybindings.json` | keybindings | — |
| `codeserver+snippets-shared` | `User/snippets/` | snippets | secrets in snippet bodies |
| `neovim+config-shared` | `~/.config/nvim/` | init.lua / Lua config | API tokens, credential files |
| `notebook+lab-settings-shared` | `~/.jupyter/lab/user-settings/` | Lab UI prefs | cookies, GitHub tokens |
| `dbeaver+connections-shared` | `…/.dbeaver/data-sources.json` | host/port/db/user | **passwords**, secure storage |
| `dbeaver+drivers-shared` | `…/DBeaverData/drivers/` | JDBC JARs (durable) | n/a (bulky; often gitignore jars) |
| `dbeaver+scripts-shared` | `…/workspace6/General/Scripts/` | saved SQL in DBeaver | credentials in SQL |
| `zsh+starship-shared` | `~/.config/starship.toml` | prompt theme | API keys in custom modules |
| `xfce+keyboard-shortcuts-shared` | XFCE keyboard xfconf XML | desktop shortcuts | full session / other xfce4 trees |

### DBeaver: separate concerns

| Extension | Path | Git? |
|-----------|------|------|
| **connections** | `.dbeaver/data-sources.json` | Yes — **no passwords** |
| **drivers** | `DBeaverData/drivers/` **and** `workspace6/.metadata/.config/` (for `drivers.xml`) | Durable mount; **gitignore JARs**; keep `drivers.xml` |
| **scripts** | `workspace6/General/Scripts/` | Yes — team SQL; or keep scripts under project `sql/` instead |

**Why drivers need two paths:** JARs land in `drivers/`, but DBeaver records
“which libraries belong to which driver” in
`workspace6/.metadata/.config/drivers.xml`. Sharing only the jars still forces a
re-download prompt on the next cold home.

**Settings (UI prefs):** other files under `workspace6/.metadata/` are mixed state.
**Do not** share the whole workspace by default. Prefer connections + drivers +
scripts; use `--persist-home` for a personal full UI state.

All use `shared-files` / `shared-dirs` only (**not** `cache-*`). Prefer **host seed**
for credentials (`/etc/cb-home-seed`). Prefer **project files** for lint/CI config
when the setting is really project-scoped.

### Explicitly out of scope (conservative)

| State | Why not shared |
|-------|----------------|
| code-server / VS Code **extensions** + **globalStorage** | large; often holds tokens |
| JetBrains full config / license | versioned product dirs; licenses; secrets |
| Warp / cloud CLI credentials | secrets — use credential seed extensions |
| Shell history, browser cookies, password DBs | secrets / personal |
| Whole `~/.config` or whole home | too broad; “works on my machine” |

### Example workspace

[`examples/workspaces/browser-shared-example/`](../examples/workspaces/browser-shared-example/) —
XFCE + Chrome + Firefox, shared dirs, sample gitignores, managed-policies setups.

All are **opt-in** (`auto-select = false`).

```bash
booth config --no-tui . \
  --select google-chrome+bookmarks-shared+extensions-shared/firefox+settings-shared
```

**Chrome data dir note:** wrappers set `--user-data-dir=~/.chrome-data` (not
`~/.config/google-chrome`).

### Chrome / Chromium (directory mounts)

Chrome and Chromium share `~/.chrome-data`. Bookmarks/settings need **`Default/`**
(rename-safe). Extensions alone can use **`Default/Extensions/`**. Do not use
`cache-dirs` for team sharing.

`Default/` can grow cookies and Local Storage. Prefer a `.gitignore` that keeps
only what you intend to commit (`Bookmarks`, `Preferences`, `Extensions/`, …).

### Firefox (directory mount)

Mount **`~/.mozilla/firefox/`** so first run can create `profiles.ini` and a
profile. Bookmarks (`places.sqlite`), settings (`prefs.js`), and extensions all
live under that tree — one shared dir covers them.

### Test checklist (desktop)

| Browser | Install | Shared | Host check |
|---------|---------|--------|------------|
| Chrome | `setup google-chrome` | `Default/` and/or `Default/Extensions/` | `Bookmarks` / `Preferences` / `Extensions/*` mtime |
| Chromium | `setup chromium-browser` | same paths | same |
| Firefox | `setup firefox` | `…/.mozilla/firefox/` | `**/places.sqlite`, prefs, `**/extensions` |

Launch via the desktop icon / wrapper. Restart the **booth** to confirm.

**First commit workflow (Chrome/Chromium):**

1. Select `google-chrome+bookmarks-shared` (and optionally `+extensions-shared`).
2. Start a desktop booth with a CLI that implements `.booth/shared/`.
3. Change settings / install an extension / add bookmarks.
4. Commit only the paths you want under `.booth/shared/…/Default/`.

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
