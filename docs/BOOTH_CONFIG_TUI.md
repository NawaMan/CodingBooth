# booth config — Interactive Configuration

> Browse templates, select what you need, and generate your booth — all from a single TUI.

`booth config` provides an interactive terminal interface for configuring a CodingBooth environment. Instead of memorizing template names and DSL syntax, you can visually browse all available templates, select what you need, and generate the `.booth/` configuration in one step.

Back to [README](../README.md) | See also: [booth config reference](BOOTH_CONFIG.md)

---

## Table of Contents

- [Quick Start](#quick-start)
- [How It Works](#how-it-works)
- [TUI Layout](#tui-layout)
- [Keybindings](#keybindings)
- [Pre-populating with Flags](#pre-populating-with-flags)
- [Selection Behavior](#selection-behavior)
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

## Keybindings

### Search

| Key | Action |
|-----|--------|
| `Tab` | Focus the search bar (from content) |
| Type | Filter templates/extensions by name or description |
| `Tab` / `Enter` / `↓` | Return to content (keep search text) |
| `Esc` | Clear search and return to content |

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
| `Esc` (when editing) | Finish editing |
| `←` / `→` | Switch tab |
| `Tab` | Focus search bar |

### Global

| Key | Action |
|-----|--------|
| `Ctrl+S` | Save selection and run init |
| `Ctrl+Q` / `Ctrl+C` | Quit (asks for confirmation) |
| `Enter` (when quitting) | Confirm quit |
| `Esc` (when quitting) | Cancel quit |

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
| `--overwrite` | Overwrite existing files without prompting (`--no-tui` only) |
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
