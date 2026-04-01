# booth tmp

> A clean slate every time your booth starts — ephemeral runtime state that never leaks into your project.

Every booth start wipes `.booth/.tmp/`, and every booth exit cleans it up. This gives you a predictable location for runtime files that exist only while the booth is running.

```bash
ls .booth/.tmp/
# booth-startup.txt    ← created automatically on every start
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [What Gets Created](#what-gets-created)
- [Use Cases](#use-cases)
- [Gitignore](#gitignore)
- [Lifecycle](#lifecycle)
- [Debugging: --leave-tmp-on-exit](#debugging---leave-tmp-on-exit)

---

## Overview

Development environments accumulate runtime artifacts — PID files, lock files, session tokens, tunnel control files. These files are useful while the booth is running but meaningless (or harmful) after a restart.

`.booth/.tmp/` is a convention: a directory that is **always empty at boot** and **cleaned on exit**. CodingBooth empties it as part of the container startup sequence (before any startup scripts run), and again on exit. Features that need ephemeral state can rely on this directory existing and being clean.

Since `.booth/` is part of the bind-mounted code directory, `.booth/.tmp/` is directly visible from the host at `<project>/.booth/.tmp/` — no extra mounts needed to inspect its contents while the booth is running.

---

## What Gets Created

On every booth start, CodingBooth:

1. Empties `.booth/.tmp/` (creates it if missing)
2. Writes `.booth/.tmp/booth-startup.txt` with:

```
started-at = 2026-03-29T14:32:07Z
session-id = a7f3b2c9e1d6
```

- **started-at** — timestamp of this boot (UTC)
- **session-id** — random identifier unique to this session

The `session-id` uniquely identifies a booth session. It can be used by features or scripts that need a per-session identifier.

---

## Use Cases

`.booth/.tmp/` is a general-purpose directory. Any tool or feature — built-in or user-created — can use it for runtime state.

| Subdirectory / File | Purpose |
|---------------------|---------|
| `booth-startup.txt` | Session metadata (created by CodingBooth) |
| `tcp-tunnels/` | TCP tunnel control files (see [booth expose](BOOTH_EXPOSE.md)) |
| Custom files | Your startup scripts or tools can write here too |

### Example: using session-id in a startup script

```bash
#!/bin/bash
# .booth/startups/my-startup.sh
SESSION_ID=$(grep session-id .booth/.tmp/booth-startup.txt | cut -d= -f2 | tr -d ' ')
echo "This session: $SESSION_ID"
```

---

## Gitignore

`.booth/.tmp/` should be gitignored. `booth config` adds it automatically:

```gitignore
# .booth/.gitignore
.tmp/
```

This directory is purely runtime state — there is never a reason to commit its contents.

---

## Lifecycle

```
booth start
  ├── empty .booth/.tmp/ (create if missing)
  ├── write .booth/.tmp/booth-startup.txt
  ├── run startup scripts (/usr/share/startup.d/, .booth/startups/)
  │   └── (scripts can now write to .booth/.tmp/)
  └── ready

booth exit / stop
  └── empty .booth/.tmp/

booth crash / kill -9
  └── .booth/.tmp/ left stale (cleaned on next start)
```

The directory contents are emptied rather than the directory itself being deleted and recreated. This keeps any bind mounts pointing to `.booth/.tmp/` intact.

On exit, the contents are cleaned by default. On a crash or forced kill, the startup cleanup acts as a safety net.

---

## Debugging: `--leave-tmp-on-exit`

By default, `.booth/.tmp/` is cleaned on exit. To preserve its contents for post-mortem debugging, use:

```bash
./booth --leave-tmp-on-exit
```

Or in `.booth/config.toml`:

```toml
leave-tmp-on-exit = true
```

When enabled, `.booth/.tmp/` is left as-is on exit. The contents will still be cleaned on the next booth start — unless you also use `--keep-tmp-on-start`.

This is useful when you need to inspect runtime state after a booth exits — tunnel control files, logs, or any artifacts written by your tools during the session.

---

## Debugging: `--keep-tmp-on-start`

By default, `.booth/.tmp/` is emptied on every start. To preserve leftover files from a previous session, use:

```bash
./booth --keep-tmp-on-start
```

Or in `.booth/config.toml`:

```toml
keep-tmp-on-start = true
```

When enabled, existing files in `.booth/.tmp/` are kept. A new `booth-startup.txt` is still written (overwriting the previous one), but all other files survive.

This is useful when you used `--leave-tmp-on-exit` in the previous session and want to inspect or continue using those files inside the container on the next start.

### Typical debugging workflow

```bash
# Session 1: leave .tmp/ on exit for inspection
./booth --leave-tmp-on-exit
# ... work, create files in .booth/.tmp/, exit ...

# Session 2: keep those files available inside the container
./booth --keep-tmp-on-start
# ... inspect .booth/.tmp/ from inside the booth ...
```
