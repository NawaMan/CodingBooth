# CodingBooth Template Authoring Guide

**Purpose:** Guide for AI agents and developers to create init templates for `codingbooth init`.

---

## Overview

Templates define what gets installed when a user runs `codingbooth init new <path> --select <templates>`. Each template produces Boothfile segments, config settings, and file references that are merged together into a `.booth/` directory.

Templates live under the `templates/` directory, organized by category.

---

## Directory Structure

```
templates/
├── languages/                    # Category
│   ├── meta.toml                 # Category metadata
│   ├── go/                       # Template (name = "go")
│   │   ├── template.toml        # Template spec + inline segments (required)
│   │   ├── linter/              # Extension (name = "linter")
│   │   │   └── template.toml
│   │   └── vscode-ext/          # Extension (name = "vscode-ext")
│   │       └── template.toml
│   ├── python/
│   │   ├── template.toml
│   │   ├── home-seed/           # Files copied to ~ (no-clobber)
│   │   ├── uv/                  # Extension
│   │   │   └── template.toml
│   │   └── vscode-ext/
│   │       └── template.toml
│   └── java/
│       ├── template.toml
│       ├── maven/               # Extension with its own params
│       │   └── template.toml
│       └── vscode-ext/
│           └── template.toml
└── tools/                       # Another category
    ├── meta.toml
    └── claude-code/
        └── template.toml
```

**Key rules:**
- Template name = folder name (must be unique across ALL categories)
- Extensions are subdirectories of a template with their own `template.toml`
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
| `display-disc`  | string     | Short description                                        |
| `display-order` | int        | Sort order within category (lower = first)               |
| `tags`          | []string   | Searchable tags                                          |
| `auto-select`   | bool       | Extension only: auto-include when parent selected        |
| `variant`       | string     | Config: booth variant                                    |
| `port`          | string     | Config: port mapping                                     |
| `timezone`      | string     | Config: timezone                                         |
| `dind`          | bool       | Config: Docker-in-Docker                                 |
| `cmds`          | []string   | Config: default commands                                 |
| `build-args`    | []string   | Config: Docker build arguments                           |
| `run-args`      | []string   | Config: Docker run arguments (flag-value pairs deduped)  |
| `requires`      | []string   | Other template names that must also be selected          |

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

---

## Inline Segments

Boothfile and startup content is defined inline in `template.toml` under a `[segments]` table. These segments are merged into the final `.booth/Boothfile` and `.booth/startup.sh`.

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

Extensions are subdirectories of a template with their own `template.toml`:

```
go/
├── template.toml          # Includes [segments] with Boothfile content
├── linter/                # Extension
│   └── template.toml     # Must have auto-select field; includes [segments]
└── vscode-ext/            # Extension
    └── template.toml
```

**auto-select behavior:**
- `auto-select = true` — Included automatically when parent is selected (e.g., vscode-ext)
- `auto-select = false` — Must be explicitly selected with `+` syntax (e.g., `java+maven`)

Extensions share the parent's parameters and are listed as sub-items in the selection summary.

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

**`templates/languages/rust/vscode-ext/template.toml`:**
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
- [ ] Create extensions with `auto-select` for common add-ons (e.g., vscode-ext)
- [ ] Test with `codingbooth init dryrun --templates-path templates --select <name>`
- [ ] Verify param positional mapping: `codingbooth init dryrun --select "<name>:value1,value2"`

---

## Testing

**Tip:** Set `export CB_TEMPLATES_PATH=templates` to avoid repeating `--templates-path` on every command.

```bash
# Preview what a single template generates
codingbooth init dryrun --templates-path templates --select "go"

# Preview with params
codingbooth init dryrun --templates-path templates --select "java:21,corretto"

# Preview with extensions
codingbooth init dryrun --templates-path templates --select "java:25+maven+gradle"

# Preview multiple templates
codingbooth init dryrun --templates-path templates --select "go/python/claude-code"

# Generate for real
codingbooth init new ./my-project --templates-path templates --select "go/python"
```
