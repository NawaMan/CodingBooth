# Console Layout

> Check in the starting layout and Web view tabs for the Booth console web UI (the base variant's browser terminal) — so opening the booth looks the same for everyone, on any machine.

The **Booth console web UI** — "Console UI" for short — is the base variant's browser terminal: it splits into up to four panes, each either a plain terminal or a Web view holding its own tabs. `.booth/console.json` sets the Console UI's starting split layout and pre-opens Web view tabs in specific panes. It only ever supplies a *default*: the moment you customize a pane yourself (switch it to Web view, open or close a tab, resize the split), that customization is remembered in your browser and wins over the file on every later load — the file only fills in a pane nobody has touched yet in this browser.

```json
{
  "layout": "quad",
  "panes": {
    "1": { "web": true, "tabs": [":3000", "https://example.com"] },
    "3": { "web": true, "tabs": ["myserver:9000/dashboard"] }
  }
}
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [File Format](#file-format)
- [Tab Addresses](#tab-addresses)
- [Precedence](#precedence)
- [Saving Layout Changes Back](#saving-layout-changes-back)
- [Why a Separate File](#why-a-separate-file)
- [Examples](#examples)

---

## Overview

The Console UI is the base variant's default screen: a browser terminal that splits into up to four panes, each either a terminal or a Web view holding its own tabs. Normally you build that layout by hand each time — pick a split, click the globe on a pane, type an address. `.booth/console.json` lets a project check in that starting point instead, so a teammate (or you, on a different machine) opens the booth to the same layout every time, without repeating the clicks.

The file is:
- **Per-project** — lives inside `.booth/`, scoped to this project
- **Committable** — meant to be checked into git, unlike `.booth/cache/`
- **Optional** — the console works exactly as before with no file present, or with any pane the file doesn't mention

---

## File Format

```json
{
  "layout": "<layout-name>",
  "panes": {
    "<pane-number>": {
      "web": true,
      "tabs": ["<address>", "..."],
      "force": true
    }
  }
}
```

- **`layout`** — one of the six layout names the toolbar buttons themselves produce: `single`, `hsplit`, `vsplit`, `quad`, `left-main`, `top-main`. Anything else is ignored.
- **`panes`** — an object keyed by pane number as a string (`"1"` through `"4"`). A pane not listed here stays a terminal.
  - **`web`** — must be `true` for the pane to open in Web view at all. A pane listed with `"web": false` (or without `"tabs"`) is left as a terminal, same as not listing it.
  - **`tabs`** — an array of addresses, one per tab to open in that pane, in order. The last one ends up active. An empty or missing list leaves the pane as a terminal even with `"web": true`.
  - **`force`** — `true` makes this pane's entry win over whatever this browser already saved for it (see [Forcing a Pane](#forcing-a-pane)). Only meaningful alongside `"web": true`; `"web": false` already forces on its own.

The file is validated as JSON when the booth starts (`start-ttyd-split`, via `jq`); a syntax error is logged to the container's startup output and the console just starts with no preset at all rather than failing to load.

---

## Tab Addresses

Each string in `tabs` is parsed exactly the way typing it into a pane's own address bar would be — the same parser, so anything that works there works here:

| You write | Opens |
|---|---|
| `:3000` or `:3000/path` | This booth's port 3000, proxied through `/proxy/3000/...` |
| `booth:3000` | Same, alternate spelling |
| `myserver:9000` | `https://myserver:9000/` directly, unproxied — `myserver` isn't `booth`/`localhost`/`127.0.0.1` |
| `https://example.com` | That URL directly, unproxied |
| `localhost:3000` | `http://localhost:3000/` on the machine running the browser, not this booth |

A bare domain with no scheme (`example.com`) is assumed to be `https`; anything that isn't a URL or host shape at all falls back to a Google search, exactly as typing it into the address bar would.

A malformed individual address (an unsupported scheme, a reserved port) is silently skipped rather than blocking the rest of the file's tabs from opening.

---

## Precedence

On each load, in order:

1. **The URL hash** (`#mode=quad`) — if you followed a link that names a layout.
2. **What you last set in this browser** (`localStorage`) — a pane you've ever opened in Web view, even once, keeps whatever it was left as, forever, regardless of what the file says.
3. **`.booth/console.json`** — applies only to a layout nobody has picked yet, or a pane with no tabs ever recorded in this browser.
4. **The built-in default** — a single terminal pane.

This means editing the file after the fact doesn't retroactively change anyone's already-customized console — it only changes what a *fresh* browser (or a fresh `localStorage`) sees — unless the pane is forced.

### Forcing a Pane

Two per-pane settings skip step 2 and make the file win on **every** load, not just the first:

- **`"web": false`** — the pane is always a terminal. Any Web view this browser saved for it is cleared.
- **`"web": true` with `"force": true`** — the pane always opens exactly the file's `tabs`. Whatever tabs this browser saved for it are cleared first, so a changed tab list in the file actually takes effect.

Use it when the pane's contents are part of the project's setup rather than a starting suggestion — for example `examples/workspaces/kind-example`, which pins its Markdown viewer and the cluster's service tabs to pane 1 and keeps panes 2 and 3 as terminals:

```json
{
  "layout": "left-main",
  "panes": {
    "1": { "web": true, "tabs": ["booth:8765", "booth:30080", "booth:30081"], "force": true },
    "2": { "web": false },
    "3": { "web": false }
  }
}
```

The trade-off: a forced pane never remembers your own changes across reloads. The layout itself (step 2 for `layout`) is not affected by `force`.

---

## Saving Layout Changes Back

By default, `console.json` only ever flows one way: the container reads it at boot, but your later customizing of the Console UI (switching a pane to Web view, opening tabs, resizing) is remembered in `localStorage` only — the file on disk never changes. `--console-spec <mode>` (or `console-spec = "..."` in `.booth/config.toml`) turns on saving the current layout and tabs back to the file itself, so the *next* fresh browser — a teammate, or you on another machine — starts from what you last had, without anyone editing JSON by hand.

Two modes:

| Mode | Saves to | Requires | Git |
|---|---|---|---|
| `shared` | `.booth/console.json` | `--writable-booth` | Committable — this is the same file described above |
| `cache` | `.booth/.tmp/console.json` | Nothing extra — `.tmp/` is always writable | Never committed (already in `.booth/.gitignore`) |

Leaving `console-spec` unset keeps the read-only behavior documented above: an existing `.booth/console.json` is still honored as a starting layout, but nothing is ever written back.

`shared` needs `--writable-booth` because `.booth/` is otherwise bind-mounted read-only; without it, a `shared` save fails cleanly (logged, not fatal) and the change still lives on in `localStorage` for that browser. `cache` never needs `--writable-booth` — `.booth/.tmp/` is always mounted read-write, the same mount used for session/idle/lifecycle state — but because it isn't git-tracked, it only helps *your* next session, not a teammate's.

Saving is automatic and debounced: there's no explicit "save" button, it just happens shortly after you change layout or tabs.

**Caveat: takes effect on next restart, not live.** `index.html` is rendered once, from `console.json`'s contents at that moment, when the container boots — the same static page is then served for the container's entire lifetime. A save updates the file on disk right away, but the *currently running* container keeps serving the page it already rendered, so even a brand-new browser tab against that same running container won't see the change until the container restarts. This mirrors the read-only file's own load-once behavior — it isn't unique to saving.

This setting is only meaningful for the Console UI — other variants ignore it, so it's harmless to leave set in a shared `config.toml` that's used across variants.

---

## Why a Separate File

Most per-project settings — idle timeout, run-time display, and the like — live as scalar keys in `.booth/config.toml` and get forwarded into the container as a `BOOTH_*` environment variable. The layout/tabs data itself follows a different path: a layout name plus an arbitrary, per-pane list of tab addresses is genuinely structured data, not a string, bool, or flat list, and `config.toml`'s schema doesn't have a good way to express "an array of arrays" without real changes to the CLI itself.

Instead, `console.json` rides the same mechanism `.booth/cache/` and `.booth/shared/` already use: `.booth/` is bind-mounted into every booth at `/home/coder/code/.booth` (read-only by default), so the container's own startup script can just read the file directly — no `docker -e`, no environment variable needed for the *read* path. `console-spec` (above) is the one small piece of this feature that *is* a scalar `BOOTH_*` setting, since "which mode, if any" is exactly the kind of flat value `config.toml` already handles well.

---

## Examples

**A dev server pre-opened next to the terminal:**

```json
{
  "layout": "hsplit",
  "panes": {
    "2": { "web": true, "tabs": [":3000"] }
  }
}
```

**Two tabs in one pane, in a four-way split:**

```json
{
  "layout": "quad",
  "panes": {
    "1": { "web": true, "tabs": [":3000", ":3000/admin"] }
  }
}
```
