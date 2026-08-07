# CodingBooth Template Authoring Guide

**Purpose:** the `template.toml` / `*--extension.toml` **schema** — every key the loader accepts,
what it does, and how selections merge. Reference material for the `templates/` tree in this repo.

> **Working on the catalog?** The **`setup-work` skill** is the workflow that uses this file —
> adding, modifying, or fixing a setup, template, or extension, including how to try a change
> without rebuilding an image.
>
> | Also see | For |
> | --- | --- |
> | `templates/README.md` | which segment **order band** to use, and the per-order catalogue of existing patterns |
> | `docs/BOOTH_SETUP.md` | the setup **scripts** a template's Boothfile calls |
> | `docs/AGENT_RECIPE.md` | recipe files (`--select @name`) |

---

## Overview

Templates define what gets installed when a user runs `codingbooth config --no-tui [path] --select <templates>`. Each template produces Boothfile segments, config settings, and file references that are merged together into a `.booth/` directory.

Templates live under the `templates/` directory, organized by category.

---

## Directory Structure

```
templates/
├── languages/                          # Category
│   ├── meta.toml                       # Category metadata
│   ├── go/                             # Template (name = "go")
│   │   ├── template.toml               # Template spec + inline segments (required)
│   │   ├── linter--extension.toml      # Extension (name = "linter")
│   │   └── vscode-ext--extension.toml  # Extension (name = "vscode-ext")
│   ├── python/
│   │   ├── template.toml
│   │   ├── home-seed/                  # Files copied to ~ (no-clobber)
│   │   ├── uv--extension.toml
│   │   └── vscode-ext--extension.toml
│   └── java/
│       ├── template.toml
│       ├── maven--extension.toml       # Extension with its own params
│       └── vscode-ext--extension.toml
└── tools/                              # Another category
    ├── meta.toml
    └── claude-code/
        └── template.toml
```

**Key rules:**
- Template name = folder name (must be unique across ALL categories)
- Extensions are `<name>--extension.toml` files beside the parent's `template.toml`
  (a subdirectory with its own `template.toml` also works — see *Extensions*)
- Special subdirectories (`setups/`, `home/`, `home-seed/`) are for files, not extensions

---

## Category meta.toml

Every category directory needs a `meta.toml`:

```toml
display-name = "Languages"
order = 1
```

| Field          | Required | Description                          |
|----------------|----------|--------------------------------------|
| `display-name` | Yes      | Human-readable category name         |
| `order`        | Yes      | Sort order (lower = first)           |

---

## Template template.toml

Every template and extension needs a `template.toml`:

```toml
display-name = "Go"
display-disc = "Go language toolchain"
display-order = 10
tags = ["go", "golang", "backend"]

# Extension only: auto-select when parent is selected
# auto-select = true

# Config scalars (match-or-error if multiple templates set the same one)
# variant = "codeserver"
# port = "NEXT"
# timezone = "America/Toronto"
# dind = true

# Config arrays (combined and deduped across templates)
# cmds = ["start-notebook"]
# build-args = ["--build-arg", "FOO=bar"]
run-args = [
    "-e", "GOPROXY=https://proxy.golang.org,direct",
]

# Dependencies: error if these templates are not also selected
# requires = ["python"]

# Parameters: positional mapping uses declaration order in this file
[params.GO_VERSION]
default = "1.25.7"
suggests = ["1.25.7", "1.24.13", "1.23.12"]

# Inline segments: Boothfile and startup content
[segments]
Boothfile = """
setup go ${GO_VERSION}
install go golang.org/x/tools/gopls@latest
"""
```

### Spec Fields Reference

| Field           | Type       | Description                                              |
|-----------------|------------|----------------------------------------------------------|
| `display-name`  | string     | Human-readable name                                      |
| `display-disc`  | string     | Short description — the list view                        |
| `display-detail`| string     | Long description — the TUI detail pane / `template show` |
| `display-order` | int        | Sort order within category (lower = first)               |
| `tags`          | []string   | Searchable tags                                          |
| `primary`       | bool       | Show in list/search by default; others need `--full`     |
| `auto-select`   | bool       | Extension only: auto-include when parent selected        |
| `variant`       | string     | Config: booth variant                                    |
| `port`          | string     | Config: port mapping                                     |
| `timezone`      | string     | Config: timezone                                         |
| `dind`          | bool       | Config: Docker-in-Docker                                 |
| `sudo`          | bool       | Config: give the booth user passwordless sudo            |
| `cmds`          | []string   | Config: default commands                                 |
| `build-args`    | []string   | Config: Docker build arguments                           |
| `run-args`      | []string   | Config: Docker run arguments (flag-value pairs deduped)  |
| `requires`      | []string   | Other template names that must also be selected          |
| `cache-files`   | []string   | Files to persist in `.booth/cache/` (see below)          |
| `cache-dirs`    | []string   | Directories to persist in `.booth/cache/`                |
| `shared-files`  | []string   | Files to bind-mount live from `.booth/shared/`           |
| `shared-dirs`   | []string   | Directories to bind-mount live from `.booth/shared/`     |
| `unsupported-arch`      | []string | Architectures with no build (`"arm64"`, `"amd64"`)  |
| `unsupported-arch-note` | string   | Why, and what to use instead — required with the above |

Scalars merge **match-or-error** across selected templates; arrays **combine and dedup**.

### Cache and shared paths

Both take paths that **mirror the container filesystem**, without a leading slash — so the booth
user's home is `home/coder/…`. The difference is intent:

- **`cache-*`** — machine-local state that should survive a rebuild but is not worth committing:
  REPL history, a tool's settings dir. Materialised under `.booth/cache/`.
- **`shared-*`** — state you *want* in git so a team shares it: editor settings, DB connections,
  keyboard shortcuts. Materialised under `.booth/shared/` as a live bind mount.

```toml
# templates/languages/python/repl-history--extension.toml
cache-files = [
    "home/coder/.python_history",
]

# templates/ides/codeserver/settings-shared--extension.toml
shared-files = [
    "home/coder/.local/share/code-server/User/settings.json",
]
```

Directories get a `.mount-this` marker so the booth knows to mount them. Full behaviour:
`docs/BOOTH_LOCALCACHE.md` and `docs/BOOTH_SHARED.md`.

### Inline files — `[files.*]`

Ships a file's **content** from the template itself, keyed by its relative path. This is how an
inline extension carries a script or a config without needing a directory:

```toml
[files.setups]
"deno-pkg--install.sh" = """
#!/bin/bash
set -Eeuo pipefail
...
"""

[files.home-seed]
".claude/settings.json" = """
{ "permissions": { "allow": ["Bash", "Edit"] } }
"""
```

| Table              | Lands in            | Mode                        |
|--------------------|---------------------|-----------------------------|
| `[files.setups]`   | `.booth/setups/`    | —                           |
| `[files.home]`     | `.booth/home/`      | copied to `~` (override)    |
| `[files.home-seed]`| `.booth/home-seed/` | copied to `~` (no-clobber)  |

The directory equivalents (`setups/`, `home/`, `home-seed/` next to `template.toml`) do the same
thing from real files — see *File Directories* below. Directory-based files are unavailable to
inline `*--extension.toml` extensions; use `[files.*]` there.

### Templates with no build on some architecture

A few tools have no upstream build for an architecture — Google publishes no
linux/arm64 Chrome, so `google-chrome` cannot install in a booth built on Apple
Silicon. Declare it:

```toml
unsupported-arch = ["arm64"]
unsupported-arch-note = """\
Google publishes no linux/arm64 build of Chrome... Use "chromium" instead."""
```

This does **not** block selection. The booth still builds — the setup script is
expected to print a warning and `exit 0` rather than fail, so one missing tool
never takes down a build in which everything else succeeded. What the metadata
buys is that nobody finds out afterwards: `booth config` marks the row with `!`,
explains it in the detail panel, and warns when the box is ticked, and
`booth template show` prints the note.

Both keys go together — a declaration without a note falls back to a generic
sentence that says something is missing but not what to do instead. The
`tests/config/test92-arch-unsupported-is-declared.sh` guard enforces the pair,
and that arch bail-outs in setup scripts exit 0 with an explanation.

### Parameters

Parameters become `arg NAME=value` directives in the generated Boothfile.

```toml
[params.JDK_VERSION]
default = "25"
suggests = ["25", "21", "17", "11"]

[params.JDK_VENDOR]
default = "temurin"
suggests = ["temurin", "corretto", "openjdk"]
```

**Positional mapping:** When a user writes `java:25,corretto`, the values are mapped to params in **declaration order** in template.toml. In the example above, `25` maps to `JDK_VERSION` and `corretto` maps to `JDK_VENDOR`.

**Naming:** Use explicit, prefixed names (e.g., `GO_VERSION`, `PYTHON_VERSION`) to avoid collisions across templates.

**Variadic params:** the **last** declared param may set `variadic = true` to absorb every remaining
positional value, joined with `,`. Without it, passing more values than there are params is an
error (`too many parameters: got 3, template has 2`). This is how package-list templates take an
open-ended selection:

```toml
# templates/tools/apt-pkg/template.toml
[params.APT_PKGS]
default  = ""
variadic = true
```

```bash
booth config --no-tui --select "apt-pkg:jq,ripgrep,htop"   # APT_PKGS=htop,jq,ripgrep
```

Values are **deduped and sorted** into a canonical form, so the same set produces the same Boothfile
whether it came from the TUI, `--select`, or a recipe. Only the last param may be variadic.

---

## Inline Segments

Boothfile and startup content is defined inline in `template.toml` under a `[segments]` table. Boothfile segments are merged into `.booth/Boothfile`. Startup segments become individual files in `.booth/startups/` (e.g., `50-go--startup.sh`).

### Single Boothfile segment (default order 50):

```toml
[segments]
Boothfile = """
setup go ${GO_VERSION}
install go golang.org/x/tools/gopls@latest
"""
```

### Multiple ordered segments:

Use quoted keys with `--N` suffix to control ordering. Lower numbers run earlier.

```toml
[segments]
"Boothfile--30" = """
setup nodejs 20
"""
"Boothfile--80" = """
setup claude-code
"""
```

### Startup segments:

```toml
[segments]
"startup.sh" = """
echo "Environment ready"
"""
"startup--10.sh" = """
echo "Early startup..."
"""
```

### Segment key reference

| Key pattern         | Type      | Order |
|---------------------|-----------|-------|
| `Boothfile`         | Boothfile | 50    |
| `"Boothfile--30"`   | Boothfile | 30    |
| `"startup.sh"`      | Startup   | 50    |
| `"startup--10.sh"`  | Startup   | 10    |

Segments across all selected templates are sorted by order, with tiebreak by template name alphabetically.

### Boothfile commands

Reference params with `${PARAM_NAME}`:

| Command                     | Description                          |
|-----------------------------|--------------------------------------|
| `setup <tool> [args...]`    | Install a tool/runtime (runs as root)|
| `install <mgr> <pkg...>`   | Install packages (runs as coder)     |

The `setup` command maps to `<tool>--setup.sh` scripts in `variants/base/setups/`.
The `install` command maps to `<mgr>--install.sh` scripts.

### File-based segments (fallback)

For backward compatibility, segment files alongside `template.toml` are also supported:

```
Boothfile              # Gets order 50 (default)
Boothfile--30          # Order 30
startup.sh             # Gets order 50
startup--10.sh         # Order 10
```

**Mixing sources:** A template can use both inline and file-based segments of the same type, as long as no two segments share the same order number. For example, an inline `"Boothfile--10"` and a file `Boothfile--30` will be merged together. However, an inline `Boothfile` (order 50) and a file `Boothfile` (also order 50) will cause a duplicate order error.

---

## File Directories

Templates can include files to copy into the generated `.booth/`:

| Directory    | Copied to          | Description                               |
|--------------|--------------------|-------------------------------------------|
| `setups/`    | `.booth/setups/`   | Custom setup/install scripts              |
| `home/`      | `.booth/home/`     | Files copied to `~` (override mode)       |
| `home-seed/` | `.booth/home-seed/`| Files copied to `~` (no-clobber mode)     |

---

## Extensions

An extension is a sub-template of a template — "X support for language Y" is almost always an
extension rather than a template of its own. It is selected with `+` (`go+linter`,
`java:25,temurin+maven+gradle`), shares the parent's parameters, and is listed as a sub-item in the
selection summary.

### Inline form — `<name>--extension.toml` (use this)

A single file next to the parent's `template.toml`. **This is what the catalog uses** — every one
of the extensions in `templates/` is written this way:

```
templates/languages/go/
├── template.toml                 # the parent
├── linter--extension.toml        # → extension "linter"
├── kernel--extension.toml        # → extension "kernel"
├── go-pkg--extension.toml        # → extension "go-pkg"
└── vscode-ext--extension.toml    # → extension "vscode-ext"
```

The extension's name is the filename with `--extension.toml` stripped. The body is the same schema
as a `template.toml`, minus file-based segments and file directories — an inline extension carries
its content in `[segments]` and `[files]`:

```toml
# templates/languages/go/linter--extension.toml
display-name   = "golangci-lint"
display-disc   = "Fast Go linters runner"
display-order  = 20
auto-select    = false

[segments]
"Boothfile--60" = """
setup golangci-lint
"""
```

### Directory form (legacy, still supported)

A subdirectory holding its own `template.toml`. The loader accepts it, and it is the only form that
can carry **file-based** segments and `setups/` / `home/` / `home-seed/` directories of its own.
Nothing in the catalog uses it today — prefer the inline form unless you need those files.

```
go/
├── template.toml
└── linter/
    └── template.toml
```

Defining the same extension name **both** ways is an error:
`extension "linter" defined as both a directory and an inline file`.

### auto-select behavior

- `auto-select = true` — included automatically when the parent is selected (e.g. `vscode-ext`)
- `auto-select = false` — must be selected explicitly with `+` (e.g. `java+maven`)

An extension may also declare `requires` — e.g. a notebook kernel sets `requires = ["notebook"]`, so
selecting it without the notebook variant is an error rather than a silent no-op.

---

## Merge Rules

When multiple templates are selected, their outputs merge:

| Type                   | Strategy         | Example                        |
|------------------------|------------------|--------------------------------|
| Boothfile segments     | Concatenate      | Sorted by order, tiebreak name |
| Startup segments       | Concatenate      | Sorted by order, tiebreak name |
| Scalars (variant, etc) | Match-or-error   | Conflict = error               |
| Arrays (run-args, etc) | Combine & dedup  | Flag-value pairs preserved     |
| Files                  | Collect all      | From templates + extensions    |
| Params                 | Error on conflict| Same key, different value      |

---

## Complete Examples

### Simple Language Template

**`templates/languages/rust/template.toml`:**
```toml
display-name = "Rust"
display-disc = "Rust language toolchain"
display-order = 40
tags = ["rust", "systems"]

[params.RUST_VERSION]
default = "stable"
suggests = ["stable", "nightly", "1.82.0"]

[segments]
Boothfile = """
setup rust ${RUST_VERSION}
"""
```

### Template with Auto-select Extension

**`templates/languages/rust/vscode-ext--extension.toml`:**
```toml
display-name = "Rust VS Code Extension"
display-disc = "rust-analyzer for VS Code"
display-order = 1
auto-select = true
tags = ["rust", "ide", "vscode"]

[segments]
Boothfile = """
setup rust-code-extension
"""
```

### Tool Template with Credentials

**`templates/tools/claude-code/template.toml`:**
```toml
display-name = "Claude Code"
display-disc = "Anthropic Claude Code AI assistant"
display-order = 10
tags = ["ai", "claude"]

run-args = [
    "-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro",
    "-v", "~/.claude:/etc/cb-home-seed/.claude:ro",
]

[segments]
Boothfile = """
setup claude-code
"""
```

### Template with Multiple Ordered Segments

Use ordered segment keys when a tool needs setup both early and late:

**`templates/tools/example/template.toml`:**
```toml
display-name = "Example"
display-order = 10

[segments]
"Boothfile--30" = """
setup nodejs 20
"""
"Boothfile--80" = """
setup my-tool
"""
```

This ensures Node.js (order 30) is installed before my-tool (order 80), regardless of what other templates add in between.

---

## Checklist for Creating a Template

- [ ] Create category directory with `meta.toml` (if new category)
- [ ] Create template directory with a unique name
- [ ] Write `template.toml` with display-name, display-disc, display-order, tags
- [ ] Add params with explicit prefixed names (e.g., `TOOL_VERSION`)
- [ ] Add `[segments]` with Boothfile content using `setup`/`install` commands referencing params
- [ ] Add `run-args` for credentials or environment variables if needed
- [ ] Create extensions as `<name>--extension.toml`, with `auto-select` for common add-ons (e.g. vscode-ext)
- [ ] Test with `codingbooth config --no-tui --dryrun --templates-path templates --select <name>`
- [ ] Verify param positional mapping: `codingbooth config --no-tui --dryrun --select "<name>:value1,value2"`
- [ ] Re-run the catalog guards (below)

### Catalog guards

Four tests in `tests/config/` enforce invariants across the whole catalog. They are cheap, need no
Docker, and are the fastest way to catch a template that looks fine on its own:

| Guard | Enforces |
| --- | --- |
| `test86-all-setups-exist.sh` | every `setup <name>` a template emits has a `<name>--setup.sh` |
| `test88-all-params-are-wired.sh` | every declared `[params.X]` is referenced as `${X}` in that template's directory |
| `test90-web-servers-have-desktop-icon.sh` | a template starting a web server registers a desktop icon |
| `test92-arch-unsupported-is-declared.sh` | `unsupported-arch` carries a note, and setups bail out with exit 0 |

A declared-but-unreferenced param is the nastiest of these: `booth config` shows the knob, writes
`arg X=<value>`, and nothing consumes it — the user's choice is silently dropped.

---

## Testing

**Tip:** Set `export CB_TEMPLATES_PATH=templates` to avoid repeating `--templates-path` on every command.

```bash
# Preview what a single template generates
codingbooth config --no-tui --dryrun --templates-path templates --select "go"

# Preview with params
codingbooth config --no-tui --dryrun --templates-path templates --select "java:21,corretto"

# Preview with extensions
codingbooth config --no-tui --dryrun --templates-path templates --select "java:25+maven+gradle"

# Preview multiple templates
codingbooth config --no-tui --dryrun --templates-path templates --select "go/python/claude-code"

# Generate for real
codingbooth config --no-tui ./my-project --templates-path templates --select "go/python"
```
