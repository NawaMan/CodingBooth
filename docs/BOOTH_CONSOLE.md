# Console Layout

> Check in the starting layout and Web view tabs for the Booth console web UI (the base variant's browser terminal) — so opening the booth looks the same for everyone, on any machine.

The **Booth console web UI** — "Console UI" for short — is the base variant's browser terminal: it splits into up to six panes, each either a plain terminal or a Web view holding its own tabs. `.booth/console.json` sets the Console UI's starting split layout and pre-opens Web view tabs in specific panes. It only ever supplies a *default*: the moment you customize a pane yourself (switch it to Web view, open or close a tab, resize the split), that customization is remembered in your browser and wins over the file on every later load — the file only fills in a pane nobody has touched yet in this browser.

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
- [When the File Is Wrong](#when-the-file-is-wrong)
- [Layouts](#layouts)
- [Keyboard Shortcuts (Tiling)](#keyboard-shortcuts-tiling)
- [Saving Layout Changes Back](#saving-layout-changes-back)
- [Why a Separate File](#why-a-separate-file)
- [Examples](#examples)

---

## Overview

The Console UI is the base variant's default screen: a browser terminal that splits into up to six panes, each either a terminal or a Web view holding its own tabs. Normally you build that layout by hand each time — pick a split, click the globe on a pane, type an address. `.booth/console.json` lets a project check in that starting point instead, so a teammate (or you, on a different machine) opens the booth to the same layout every time, without repeating the clicks.

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

- **`layout`** — one of the nine [layout names](#layouts) the toolbar buttons themselves produce: `single`, `hsplit`, `left-main`, `right-main`, `vsplit`, `top-main`, `bottom-main`, `quad`, `grid6` — or a [tiling layout](#tiling-layouts) such as `h(1,v(2,3))`. Anything else is ignored.
- **`panes`** — an object keyed by pane number as a string (`"1"` through `"6"`). A pane not listed here stays a terminal.
  - **`web`** — must be `true` for the pane to open in Web view at all. A pane listed with `"web": false` (or without `"tabs"`) is left as a terminal, same as not listing it.
  - **`tabs`** — an array of addresses, one per tab to open in that pane, in order. The last one ends up active. An empty or missing list leaves the pane as a terminal even with `"web": true`.
  - **`force`** — `true` makes this pane's entry win over whatever this browser already saved for it (see [Forcing a Pane](#forcing-a-pane)). Only meaningful alongside `"web": true`; `"web": false` already forces on its own.

The file is validated as JSON when the booth starts (`start-ttyd-split`, via `jq`); a syntax error is logged to the container's startup output and the console just starts with no preset at all rather than failing to load. Anything else it gets wrong falls back without breaking the console — see [When the File Is Wrong](#when-the-file-is-wrong).

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

A malformed individual address (an unsupported scheme, a reserved port) is skipped, with a warning in the browser console, rather than blocking the rest of the file's tabs from opening. A bare number in `tabs` is taken as a port (`3000` is `:3000`).

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

## When the File Is Wrong

The console always loads, whatever `console.json` holds. Each thing it cannot use is dropped with a warning in the browser's developer console (`.booth/console.json: …`), and the rest still applies:

| In the file | What happens |
|---|---|
| Not valid JSON, or not an object | Ignored; the console starts as if there were no file |
| `"layout"` with stray spaces or capitals (`" Quad "`) | Read as `quad` |
| `"layout"` that is not a layout (a typo, a pane above 6) | The smallest toolbar layout that shows every pane given tabs — pane 5 has tabs, so `grid6` — or `single` |
| No `"layout"`, but tabs in pane 2 or above | The same: those panes are shown, not left hidden |
| A pane key that is not `"1"` … `"6"`, or a pane that is not an object | That pane is ignored |
| `"web"` that is not `true` / `false` | The pane stays a terminal |
| A tab that is not a string or a port number | That tab is skipped; the pane's other tabs open |
| A tab with `</script>` or `<!--` in it | Read like any other text; it cannot end the page's own scripts |

A file with any of these problems is **never saved over**, even with [`console-spec`](#saving-layout-changes-back) set: what it got wrong is still yours to fix, and a save would replace it with only the part that was understood. Your changes stay in the browser until you fix the file and restart the booth.

---

## Layouts

The toolbar has a button for every way to divide the console into a 2×2 grid, and for a 3×2 grid of six:

| Name | Panes | Looks like |
|---|---|---|
| `single` | 1 | One terminal |
| `hsplit` | 2 | Two columns |
| `left-main` | 3 | Session 1 on the left, 2 and 3 stacked on the right |
| `right-main` | 3 | Session 1 on the right, 2 and 3 stacked on the left |
| `vsplit` | 2 | Two rows |
| `top-main` | 3 | Session 1 along the top, 2 and 3 side by side below |
| `bottom-main` | 3 | Session 1 along the bottom, 2 and 3 side by side above |
| `quad` | 4 | Two columns of two: 1 and 2 on top, 3 and 4 below |
| `grid6` | 6 | Three columns of two: 1, 2, 3 on top, 4, 5, 6 below |

Columns come first: the dividers running the full height split the console into columns, and each column has its own top/bottom divider, so in `quad` or `grid6` dragging one column's divider leaves the others where they are. (`top-main` and `bottom-main` are the exception by nature: their wide pane spans every column.) Each preset remembers its divider positions in the browser, so going back to it shows it the way you left it.

Any other arrangement — five panes, three columns, a [tiling layout](#tiling-layouts) built with the shortcuts — shows an **Other** button, lit and drawn in the layout's shape, for as long as it shows. The layout itself is remembered like any other, in the URL, the browser and [`console.json`](#saving-layout-changes-back).

The **+** and **−** buttons beside **Reload** open a pane next to the focused one and close the focused one, the same as `Ctrl+Alt+Enter` and `Ctrl+Alt+Shift+q`; they turn grey at six panes and at one. Going from `quad` to `grid6` one pane at a time passes through five, which shows as Other — or click `grid6` to get there in one step. Closing a pane only hides it: its session keeps running, and opening it again shows it as it was. To really end one, **reset** it — the ⏻ in a terminal pane's header, or `Ctrl+Alt+Shift+x` on the focused pane. It asks first, then ends that pane's tmux session (`s1` … `s6`), stopping whatever runs there, and the pane reconnects to a fresh shell.

**Reload** reloads what every visible pane shows. A terminal reattaches to its tmux session, so the shell and anything running in it carry on; a web tab reloads its page — for an outside site, the page the tab opened on, since where it has navigated since cannot be read.

---

## Keyboard Shortcuts (Tiling)

The Console UI tiles its six sessions the way the **i3** window manager tiles windows, with **Ctrl+Alt** as the modifier — the same keys as the i3 template's Ctrl+Alt bindings, so one set of habits works on both. The toolbar [layouts](#layouts) still work as before; the shortcuts reach every other arrangement of up to six panes as well, one pane at a time.

| Keys | Action |
|---|---|
| `Ctrl+Alt+h` / `j` / `k` / `l` (or arrows) | Focus the pane left / down / up / right |
| `Ctrl+Alt+Enter` (or **+**) | Open a pane next to this one (up to six) |
| `Ctrl+Alt+b` / `Ctrl+Alt+v` | The next pane opens beside / below this one |
| `Ctrl+Alt+1` … `6` | Go to session 1 … 6, opening it again if it was closed |
| `Ctrl+Alt+f` | The pane fills the console; again to restore |
| `Ctrl+Alt+e` | Turn the pane's split the other way (side by side ↔ stacked) |
| `Ctrl+Alt+=` | Equalize: every pane in the layout the same size, same layout |
| `Ctrl+Alt+Shift+h` / `j` / `k` / `l` (or arrows) | Move the pane left / down / up / right |
| `Ctrl+Alt+Shift+q` (or **−**) | Close the pane — it is only hidden; its session keeps running |
| `Ctrl+Alt+Shift+x` (or the pane's ⏻) | Reset the session: after asking, end its shell and anything running in it, and start a fresh one |

The focused pane has a highlighted border once there is more than one. The shortcuts work from inside a terminal or a booth web tab (`:3000` and the like). A web tab showing an outside site keeps its keys to itself, so click into a terminal pane first. `Ctrl+Alt+arrows` may be taken by your own desktop; `h`/`j`/`k`/`l` always work.

The **Keyboard Shortcut Hint** in the toolbar always shows the main keys, the `Ctrl+Alt` ones and then the `Ctrl+Alt+Shift` ones. While a mode is on it shows what the keys do there instead — a pane filling the console, or where the next pane will open after `Ctrl+Alt+b` / `v` — and a click leaves the mode. To resize a pane, drag a divider. Otherwise a click opens the full table, which is also in the console itself: open the floating **Booth** panel and pick **CodingBooth Help**, which opens on its **Console Shortcuts** tab (the desktop variants' i3 template adds an **i3 Shortcuts** tab to the same dialog).

### Tiling Layouts

A layout the toolbar has no button for is written as a tree: `h(…)` puts its parts side by side, `v(…)` stacks them, and the numbers are sessions. `@` gives a part's share in percent when the parts are not equal:

| Layout | Looks like |
|---|---|
| `h(1,2,3)` | Three columns |
| `h(v(2,3),1)` | Session 1 on the right, 2 and 3 stacked on the left |
| `v(h(2,3),1)` | Session 1 along the bottom, 2 and 3 above it |
| `h(1@60,v(2,3,4)@40)` | Session 1 on 60% of the width, three stacked on the right |

It appears in the URL (`#mode=h(1,2,3)`), is remembered in the browser like any layout, and works as `"layout"` in `console.json` — [console-spec](#saving-layout-changes-back) saves it there the same way it saves a preset name, sizes included (`"layout": "h(2@55,1@45)"`). Filling the console with `Ctrl+Alt+f` is temporary and never saved. When a shortcut produces the shape of one of the toolbar [layouts](#layouts), wherever its dividers sit, the console shows it as that layout and lights its button; any other layout shows the **Other** button. `quad` is columns first, `h(v(1,3),v(2,4))`, so the rows-first `v(h(1,2),h(3,4))` is Other.

A booth image older than this feature does not know tree layouts: it ignores one in `console.json` and starts with a single pane, as it would for any unknown name. The same goes for `right-main`, `bottom-main` and `grid6`, and for panes `5` and `6`, on an image from before six panes.

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

Saving is automatic and debounced: there's no explicit "save" button, it just happens shortly after you change layout or tabs. A preset is saved by name while its dividers are where the preset puts them, and as its whole tree once you have dragged them — `"layout": "h(v(1@30,3),v(2,4))"`, which reads back as `quad` with those positions — so the file reproduces the screen exactly.

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
