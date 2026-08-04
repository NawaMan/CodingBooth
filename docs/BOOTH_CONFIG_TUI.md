# booth config — Interactive Configuration

> Browse templates, select what you need, and generate your booth — all from a single TUI.

`booth config` provides an interactive terminal interface for configuring a CodingBooth environment. Instead of memorizing template names and DSL syntax, you can visually browse all available templates, select what you need, and generate the `.booth/` configuration in one step.

Back to [README](../README.md) | See also: [booth config reference](BOOTH_CONFIG.md)

---

## Table of Contents

- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [TUI Layout](#tui-layout)
- [The Config Tab](#the-config-tab)
- [Keybindings](#keybindings) · [Mouse](#mouse)
- [Pre-populating with Flags](#pre-populating-with-flags)
- [Selection Behavior](#selection-behavior)
- [Saving over Hand-Written Files](#saving-over-hand-written-files)
- [Flags](#flags)
- [Examples](#examples)

---

## Quick Start

```bash
# Browse and select interactively
booth config

# Pre-select some templates, then fine-tune in the TUI
booth config --select go+linter --variant codeserver

# Configure into a specific directory
booth config ./my-project

# Edit an existing booth — reads .booth/Boothfile and pre-populates the TUI
booth config ./existing-project
```

---

## How It Works

1. **Launch** — `booth config` loads all available templates and opens the TUI
2. **Load existing** — If the target path has a `.booth/Boothfile`, its configuration is loaded as the baseline (existing selections, variant, port, etc. appear pre-checked)
3. **Override** — CLI flags (`--select`, `--variant`, etc.) override the existing values
4. **Browse** — Navigate the template tree grouped by category (Languages, Tools, Databases, etc.)
5. **Select** — Toggle templates and extensions with Space. Dependencies and auto-select extensions are handled automatically
6. **Configure** — Set variant and port using the config bar at the top
7. **Save** — Press Ctrl+S to generate `.booth/` files

The output is identical to running `booth config --no-tui --select <your-selections>` — same Boothfile, config.toml, startup scripts, and files.

If the booth holds hand-written files, step 2 also raises a warning on open and step 7 asks what to do with them — see [Saving over hand-written files](#saving-over-hand-written-files).

---

## TUI Layout

```
══════════════════════════════════════════════════════════════
 CodingBooth Configuration                     [5 selected]
 Search: ·····················································
 Config  Languages  Databases  Tools  ...
──────────────────────────────────────────────────────────────
 [x] go                   │ go
     [x] *linter          │ Go programming language
     [ ] air              │ ─────────────────────────
     [ ] protobuf         │ Installs Go toolchain,
 [ ] python               │ sets up GOPATH, and
     [ ] poetry           │ configures common tools.
     [ ] jupyter          │
     [ ] *ruff            │ Parameters:
 [ ] nodejs               │   GO_VERSION = 1.24.1
     [ ] pnpm             │   options: 1.24.1, 1.23.5
     [ ] *typescript      │
 [ ] rust                 │ Extensions:
     [ ] *clippy          │   * linter (auto-select)
     [ ] wasm             │     air
──────────────────────────────────────────────────────────────
 Auto-selected: go/linter
 Space: select │ ↑↓: navigate │ ◄►: tab │ Ctrl+S: save │ Ctrl+Q: quit
══════════════════════════════════════════════════════════════
```

- **Header**: Title and selection count
- **Search bar**: Type to filter templates/extensions across all tabs (Tab to focus)
- **Tab bar**: Tab 0 = Config, Tabs 1..N = categories. Switch with `←`/`→`
- **Left panel**: Scrollable template/extension list for the active category
- **Right panel**: Details of the highlighted item (description, parameters, dependencies, extensions)
- **Footer line 1**: Messages and notifications (auto-select, dependency resolution)
- **Footer line 2**: Context-sensitive keybinding hints

Extensions marked with `*` are auto-selected when their parent template is selected.

---

## The Config Tab

Tab 0 holds the settings that end up in `.booth/config.toml`, grouped and
scrollable. Every setting a booth can hold has a field here, with three
deliberate exceptions listed below.

| Group | Settings |
|---|---|
| Booth | Booth Version |
| General | Variant, Port, Name, Templates Version |
| Container | Docker-in-Docker, Keep Alive, Daemon, Sudo, Writable `.booth/`, Persist Home, Project Name, Timezone, Host UID, Host GID |
| Egress | Egress, Egress Mode, Egress Enforcement, Egress Allowlist, Egress Allowlist File, Egress Policy File |
| Build | Silence Build, Always Pull, Strict, Emit Dockerfile, Dockerfile, Boothfile, Build Args, Common Args |
| Advanced | Image, Image Version, Startup Command, Env File, Commands |
| Network & Volumes | Expose, Env, Mount |
| Cache | Cache Files, Cache Dirs |
| Session | Idle Time, Idle Shutdown Time, Idle Exit Code, Show Run Time, Show Count Down, Count Down Exit Code |
| Temp Files | Leave Tmp On Exit, Keep Tmp On Start |
| Debug | Verbose, Dry Run, Log Time, Debug |

Four fields are not `config.toml` settings and are not written to it:

- **Booth Version** writes the `.booth/` lock file — which CLI binary the booth runs.
- **Templates Version** picks the release whose templates *this configure run*
  compiles from. It is recorded in the `Configured by:` header, not as a setting.
  (**Image Version**, under Advanced, is the separate `version` key: which
  prebuilt booth image to run.)
- **Debug** prints the resolved selection for this run, like `--debug`.
- **Expose / Env / Mount** compile into `run-args` — see
  [run-args ownership](BOOTH_CONFIG.md#run-args-ownership-convention).

And three settings are deliberately absent:

- **`--public` / `--tls-cert` / `--tls-key`** are start-time only. `config.toml`
  is committed, so a stored `public = true` would expose the booth for everyone
  who clones it, while the password it requires lives in a gitignored file they
  do not have. Booth never reads these from a file.
- **`config` / `code`** name *which* booth to read and configure. They are
  arguments to the run, not settings inside it.
- **`run-args`** is compiled from Expose / Env / Mount; a raw field would fight them.

The field list is generated from the settings booth actually reads, so it cannot
fall behind: a setting added to booth has no field until one is written for it,
and a setting removed from booth loses its field automatically. A save rewrites
`config.toml` from scratch but only speaks for the keys on this tab — anything
else the booth holds is carried through untouched.

---

## Keybindings

### Search

| Key | Action |
|-----|--------|
| `Tab` | Focus the search bar (from content) |
| Type | Filter templates/extensions by name or description |
| `←` / `→` / `Home` / `End` | Move the cursor within the query (see [Text fields](#text-fields)) |
| `Tab` / `Enter` / `↓` | Return to content (keep search text) |
| `Esc` | Clear search and return to content |

### Text fields

Every text box in the TUI — the search bar, a Config string or list entry, a
[parameter](#editing-parameters) value, a package row, and the
[overwrite confirmation](#saving-over-hand-written-files) — takes the same four
keys, so a value can be fixed in place instead of retyped:

| Key | Action |
|-----|--------|
| `←` / `→` | Move the cursor one character |
| `Home` | Jump to the start of the value |
| `End` | Jump to the end of the value |
| `Backspace` | Delete the character before the cursor |

Typing and pasting both insert at the cursor, which is drawn the way a terminal
draws its own — a **reversed block on the character it is on**, and on the blank
cell past the end of the value. While a field is open the
arrows belong to the text — they do not switch tabs until the edit is finished
with `Enter` or `Esc`.

### Tree Navigation (default focus)

| Key | Action |
|-----|--------|
| `↑` | Move cursor up |
| `↓` | Move cursor down |
| `←` / `→` | Switch tab |
| `PgUp` | Page up |
| `PgDn` | Page down |
| `Home` | Jump to top of tab |
| `End` | Jump to bottom of tab |
| `Space` | Select / deselect item |
| `Tab` | Focus search bar |

### Config Fields

| Key | Action |
|-----|--------|
| `↑` / `↓` | Navigate config fields |
| `Space` / `Enter` | Toggle bool, cycle option, or edit string |
| `←` / `→` / `Home` / `End` (when editing) | Move the cursor within the value (see [Text fields](#text-fields)) |
| `Esc` (when editing) | Finish editing |
| `←` / `→` | Switch tab |
| `Tab` | Focus search bar |

### Global

| Key | Action |
|-----|--------|
| `Ctrl+S` | Save selection and run init (on a booth with [hand-written files](#saving-over-hand-written-files), asks first) |
| Terminal paste (`Ctrl+Shift+V`, middle-click) | Insert clipboard text into the focused text field — search, config strings, [parameters](#editing-parameters) |
| `Ctrl+Q` / `Ctrl+C` | Quit (asks for confirmation) |
| `Enter` (when quitting) | Confirm quit |
| `Esc` (when quitting) | Cancel quit |

### Mouse

The mouse is live — no flag, nothing to turn on:

| Click | Action |
|-------|--------|
| A tab | Switch to it |
| The search box | Focus it |
| A template / extension **row** | Move the cursor there (the right panel follows) |
| The row's `[ ]` **marker** | Select or deselect it — the marker is the mouse's `Space` |
| A **config field** | Bool flips, cycle opens for stepping, string or list entry opens for editing, `(+ add new)` adds one |
| A **parameter** in the right panel | Focus the parameter editor on that row; on a package list's `(+ add)` it starts a new entry straight away |
| The `◄` / `►` of a focused parameter | Step to the previous / next suggested value — the arrows appear once the row is focused |
| A footer **button** | `[ Save (Ctrl+S) ]` writes the booth; `[ Cancel (Ctrl+E) ]` asks first (below) |
| **Wheel** | Scroll the list, or walk the rows of a focused parameter list |

Clicking away from a field you were editing **keeps** what you typed, exactly as
`Enter` would. The two dialogs are deliberately not clickable in the same way: the
startup warning is dismissed by a click, but the
[overwrite confirmation](#saving-over-hand-written-files) ignores the mouse
entirely — it exists to make destroying hand-written files take more than a reflex,
and a stray click is precisely a reflex.

#### Save and Cancel

The bottom-right of the footer carries the two buttons that end a session:

```
  Space: select  │  Enter: edit params  │  ↑↓: navigate      [ Save (Ctrl+S) ]  [ Cancel (Ctrl+E) ]
```

While a cancel waits on an answer, the same corner holds the reply:

```
 Quit without saving? Press ENTER to quit  │  ESC to go back
  Enter: quit  │  Esc: cancel                                   [ Discard (ENTER) ]  [ Back (ESC) ]
```

`Save` is `Ctrl+S`: it writes `.booth/` and exits — and on a booth with
[hand-written files](#saving-over-hand-written-files) it opens the same typed
confirmation the key does, because a button is not a way around that guard.

`Cancel` is `Ctrl+E`. It **asks before discarding anything — but only when there is
something to discard.** On a session you have not changed, it just leaves: opening
the TUI to look at a booth and closing it again costs one click, not two. "Changed"
is measured against the state the TUI opened with, so selecting a template and
deselecting it again really is no change, and values pre-filled by
[flags](#pre-populating-with-flags) are not your edits. A value you are still typing
counts as unsaved work, so it asks.

When it does ask, the pair becomes `[ Discard (ENTER) ]` and `[ Back (ESC) ]`, so
the mouse that raised the question can answer it; `Enter` and `Esc` do the same.
Until you answer, nothing is written and nothing is lost — and while the question is
up, a click anywhere *other* than those two buttons is ignored, so a stray click
cannot throw a configuration away.

Both keys work from anywhere, including while a field is being edited: `Ctrl+S`
commits what you typed and saves, `Ctrl+E` weighs it and asks.

On a terminal too narrow to hold them, the buttons are left out rather than drawn
somewhere misleading; `Ctrl+S` and `Ctrl+E` work either way.

**The trade:** while the TUI is up it owns the mouse, so your terminal's own
click-drag text selection does not work. Hold **Shift** and drag to select text
the terminal's way (this is how most terminals bypass mouse reporting). The TUI
says so in the footer when it opens.

---

## Pre-populating with Flags

`booth config` accepts all configuration flags. Pre-passed values appear as initial selections in the TUI:

```bash
# Start with go and python pre-selected
booth config --select go/python

# Start with variant and port pre-set
booth config --variant notebook --port 10080

# Combine everything
booth config --select go+linter --variant codeserver --port 10080 --expose 8080
```

Flags like `--env`, `--expose`, `--mount`, `--set`, and `--cmd` are passed through to the init pipeline after the TUI completes.

---

## Selection Behavior

### Auto-select Extensions

When you select a template, extensions marked as auto-select are automatically checked. For example, selecting `go` automatically selects its `linter` extension. You can manually deselect these if you don't want them.

### Dependencies

Some templates require others. When you select a template with dependencies:
- Required templates are automatically selected
- A notification appears showing what was auto-selected
- Their auto-select extensions are also included

Example: Selecting `kotlin` automatically selects `java` (its dependency).

### Parent Template

Selecting an extension automatically selects its parent template if it isn't already selected.

### Deselecting

Deselecting a template also deselects all of its extensions.

---

## Editing Parameters

When a selected template or extension has parameters, press **Enter** on its row
to move focus to the right panel and edit them.

- **Single-value parameters** (e.g. `GO_VERSION`) — use `◄`/`►` to cycle through
  suggested values, or just start typing for a custom value. `↑`/`↓` move between
  parameters. `Esc` returns to the list.

### Package-list parameters

Package parameters that accept multiple values — `apt-pkg`, `npm-pkg`, `pip-pkg`,
`cargo-pkg`, `go-pkg`, `gem-pkg`, and the other `*-pkg` / install extensions — are
edited as a **multi-row list** in the right panel, one row per package (the same
style as the Expose / Env / Mount fields on the Config tab):

```
Parameters:  (editing)
  APT_PKGS:
    • htop
    • jq
    (+ add)
```

- `↑`/`↓` — move between package rows
- `Space` / `Enter` on **(+ add)** — add a new package, then type its name and press `Enter`
- `Space` / `Enter` on a package — edit it
- `Delete` / `Backspace` on a package — remove it
- `Esc` — return to the template list

Each package is stored as its own entry and compiled into a single install step
(e.g. `install apt htop jq`). This is exactly equivalent to the CLI form
`--select apt-pkg:htop,jq`.

You keep your packages in whatever order you add them while editing. On save the
list is **deduplicated and sorted** into a canonical form (so the generated
Boothfile is stable regardless of entry order); the same canonicalization applies
to the CLI and recipe forms. Package install order is not significant to these
package managers, so this never changes what gets installed.

**Paste works in every text field** — package rows, single-value parameters, the
string fields on the Config tab, and the search bar. Paste with your terminal's
own shortcut (usually `Ctrl+Shift+V`, or middle-click on X11); a module path copied
from a browser does not have to be retyped. Whatever whitespace came along with the
copy is dropped, so a copied *line* pastes as a value rather than as a value plus a
stray newline. A paste that holds several comma-separated packages
(`gopls@latest,dlv@latest`) becomes several rows, because a comma is what separates
entries.

**How to write a version is on the page.** Each install extension's description
names its own pin syntax and shows both forms — unversioned and pinned — because
they differ per package manager (`black` / `black==24.4.2` for pip, `ripgrep` /
`ripgrep@14.1.0` for cargo, `rails` / `rails:7.1.3` for gem). `go-pkg` is the one
with no unversioned form at all: `go install` refuses a bare module path, so the
floating form is `golang.org/x/tools/gopls@latest`. The description stays on screen
while the field is focused, so it is readable exactly when you are typing a value.
See [REPRODUCIBILITY.md — Tier 1](REPRODUCIBILITY.md#tier-1--pin-versions-convenience)
for the whole table.

---

## Saving over Hand-Written Files

Saving regenerates `.booth/Boothfile` and `.booth/config.toml` **from scratch** — the TUI does not edit them in place. If either holds hand-written content, saving over it would destroy work the TUI cannot reproduce from your selection. So it won't, not without asking.

A file counts as hand-written if `booth config` never wrote it, or wrote it and a human edited it afterwards. See [BOOTH_CONFIG.md — Hand-Written Files](BOOTH_CONFIG.md#hand-written-files) for how that is detected.

### On open — a heads-up

The TUI tells you as soon as it starts, so you find out *before* configuring rather than after:

```
┌──────────────────────────────────────────────────┐
│                   ⚠ Warning                      │
│                                                  │
│ This booth contains hand-written files:          │
│                                                  │
│   .booth/Boothfile                               │
│                                                  │
│ These were not written by booth config, or were  │
│ edited afterwards. Configuring regenerates them  │
│ from your selection, so they cannot simply be    │
│ written over.                                    │
│                                                  │
│ Nothing is decided yet. When you save, you       │
│ choose: keep yours and have the generated        │
│ content written beside them as .new files to     │
│ merge, or replace them (the originals are kept   │
│ as .bak).                                        │
│                                                  │
│ Go on in and look around — nothing is touched    │
│ until you save.                                  │
│                                                  │
│        Enter/Space: continue  │  Esc: quit       │
└──────────────────────────────────────────────────┘
```

This is a heads-up, not a blocker. Press `Enter` and browse, select, and configure exactly as normal — nothing is written until you save.

### On save — the choice

`Ctrl+S` does not save straight away. It raises:

```
┌──────────────────────────────────────────────────────────────┐
│              ⚠  THESE FILES ARE HAND-WRITTEN  ⚠              │
│                                                              │
│ Saving regenerates .booth/ from your selection. These files  │
│ were not written by booth config — or were edited afterwards │
│ — so saving over them would destroy that work:               │
│                                                              │
│   .booth/Boothfile                                           │
│                                                              │
│  ENTER   Keep them. Write what I generated beside them:      │
│          .booth/Boothfile.new                                │
│          Nothing is destroyed — you merge the two by hand.   │
│                                                              │
│ To replace them instead (a .bak is kept), type "overwrite"   │
│ and press Enter:                                             │
│    █                                                         │
│                                                              │
│   Enter: keep mine, write .new  │  Esc: back out  │  Ctrl+C  │
└──────────────────────────────────────────────────────────────┘
```

| Key | Action |
|-----|--------|
| `Enter` (empty field) | **Keep your files.** The generated content is written beside them as `<name>.new` for you to merge. Nothing is destroyed. |
| Type `overwrite`, then `Enter` | **Replace your files.** Each original is kept as `<name>.bak`. |
| `Esc` | Back out to the TUI. Nothing is touched. |
| `Ctrl+C` | Quit without saving. |

Typing the word in full is deliberate: destroying someone's work should take more than a reflex keystroke, while merely getting at the generated output should not. A half-typed word does nothing.

The CLI equivalents are `--beside` and `--overwrite`.

---

## Flags

| Flag | Description |
|------|-------------|
| `--select <dsl>` | Pre-select templates (repeatable) |
| `--no-tui` | Non-interactive CLI mode |
| `--dryrun` | Preview output without writing files |
| `--variant <name>` | Pre-set variant (default, console, terminal, base, notebook, codeserver, xfce, kde) |
| `--port <port>` | Pre-set port |
| `--templates-path <dir>` | Use local templates directory |
| `--version <ver>` | Use templates from a specific release version |
| `--overwrite` | Overwrite existing files without prompting, including [hand-written](#saving-over-hand-written-files) ones (`--no-tui` only) |
| `--beside` | Keep [hand-written](#saving-over-hand-written-files) files; write the generated content as `<name>.new` to merge (`--no-tui` only) |
| `--start` | Start the booth after creation |
| `--debug` | Print debug output |
| `--cmd <command>` | Set default start command (repeatable) |
| `--expose <port>` | Expose extra port (repeatable) |
| `--env <KEY=VALUE>` | Set environment variable (repeatable) |
| `--mount <host:container>` | Mount volume (repeatable) |
| `--set <key=value>` | Set config.toml value (repeatable) |

---

## Examples

### Interactive from scratch

```bash
booth config
```

### Pre-select a data science stack, fine-tune in TUI

```bash
booth config --select python+uv+kernel/notebook/postgresql
```

### Configure into a new project directory

```bash
booth config ./my-new-project --variant codeserver
```

### Full desktop with AI tools pre-selected

```bash
booth config --select "java:21+maven/claude-code" --variant desktop-xfce
```

### Edit an existing booth

If the target path already has `.booth/Boothfile`, the existing configuration is loaded automatically:

```bash
# Opens TUI with existing selections pre-checked
booth config ./my-existing-project

# Override the variant while keeping existing template selections
booth config ./my-existing-project --variant codeserver
```

The loading priority is:
1. Existing `.booth/Boothfile` `# Adjust with :` header (baseline)
2. CLI flags (override the baseline)
3. TUI changes (final)
