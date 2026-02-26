# booth init

> One command. A fully configured development environment.

`booth init` creates a complete `.booth/` configuration — Boothfile, config, startup scripts — from templates. No manual Dockerfile writing required.

```bash
./booth init new --select go+linter/python:3.13+uv/claude-code
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Subcommands](#subcommands)
- [Selection DSL](#selection-dsl)
- [Selection Sources](#selection-sources)
- [Flags](#flags)
- [Browsing Templates](#browsing-templates)
- [What Gets Generated](#what-gets-generated)
- [Common Workflows](#common-workflows)

---

## Overview

Setting up a CodingBooth environment means creating a `.booth/` folder with a Boothfile, config.toml, and possibly startup scripts. For a simple single-language project this is straightforward, but for a polyglot project with multiple languages, AI tools, and IDE extensions, writing it all by hand is tedious.

`booth init` solves this with template-driven scaffolding. You select what you need — languages, tools, extensions — and init compiles everything into a ready-to-use `.booth/` configuration. Templates encode best practices (correct ordering, proper arguments, volume persistence) so you get a working environment without needing to understand every detail.

For more information on how setup scripts are generated and structured, see the **[Booth Setup Guide](BOOTH_SETUP.md)**.

---

## Subcommands

### `init new`

Create a new booth configuration.

```bash
# In the current directory
./booth init new --select python+uv

# In a target directory
./booth init new ../my-project --select go+linter/python:3.13+uv

# Empty booth (no templates, just CLI overrides)
./booth init new --variant codeserver --port 10080
```

If generated files already exist, init prompts for confirmation before overwriting.

### `init adjust`

Re-generate an existing booth configuration. Equivalent to `init new --overwrite` — overwrites files without prompting.

```bash
./booth init adjust --select python+uv+django
```

### `init dryrun`

Preview what would be generated without writing any files.

```bash
./booth init dryrun --select go+linter/python:3.13
```

---

## Selection DSL

The `--select` flag accepts a mini-language for specifying templates, versions, extensions, and exclusions.

### Templates

Separate multiple templates with `/`:

```
go/python/claude-code
```

### Version parameters

Append `:` to set a template's version parameter:

```
python:3.13
go:1.25
java:21
```

Multiple parameters use commas: `java:21,temurin`

### Extensions

Append `+` to add extensions:

```
python+uv+pip+kernel
go+linter+vscode-ext
java+maven+lombok
```

### Excluding auto-selected extensions

Use `~` to exclude extensions that would otherwise be auto-selected:

```
firebase~credential
```

### Putting it together

```
go:1.25+linter+vscode-ext/python:3.13+uv+kernel/notebook/claude-code
```

This selects:
- Go 1.25 with linter and VS Code extension
- Python 3.13 with uv, and Jupyter kernel
- Notebook variant
- Claude Code AI assistant

### Whitespace rules

For readability in files and heredocs:
- Spaces around `+` and `~` are allowed: `java + maven` works
- Lines starting with `+` or `~` continue the previous template
- Remaining whitespace becomes `/` separators

---

## Selection Sources

| Source | Syntax | Example |
|--------|--------|---------|
| Inline | Direct string | `--select go+linter/python:3.13` |
| Multiple flags | Repeated | `--select go+linter --select python:3.13` |
| File | `@path` | `--select @my-project.recipe` |
| URL | `@@url` | `--select @@https://example.com/recipe.txt` |
| Stdin | `-` | `--select -` (type or pipe) |

Recipe files are plain text with the same DSL syntax — one template per line.

---

## Flags

| Flag | Description |
|------|-------------|
| `--select <dsl>` | Template selection (repeatable) |
| `--variant <name>` | Set variant (base, notebook, codeserver, xfce, kde) |
| `--port <port>` | Set port in generated config.toml (number, NEXT, RANDOM) |
| `--cmd <command>` | Set the default start command (repeatable) |
| `--set <key=value>` | Set a config.toml value (repeatable; bare key = boolean true) |
| `--version <ver>` | Use templates from a specific release version |
| `--templates-path <dir>` | Use local templates directory |
| `--overwrite` | Overwrite existing files without prompting |
| `--start` | Launch the booth immediately after init |
| `--debug` | Print resolved selection and compiled output as JSON |

---

## Browsing Templates

Use `booth template` to explore what's available before running init.

```bash
# List all primary templates
./booth template list

# Search by name, description, or tag
./booth template search python

# Show detailed info (parameters, extensions, tags)
./booth template show go

# Show extension details
./booth template show python+uv

# Show file and segment contents
./booth template show go --detail

# Show raw template code
./booth template cat go
```

Use `--full` with `list` or `search` to include secondary (non-primary) templates.

There are **58+ templates** across 7 categories: languages, ai-tools, tools, IDEs, desktops, databases, and browsers.

---

## What Gets Generated

`booth init` creates a `.booth/` directory with the following structure:

```
.booth/
├── config.toml      # Runtime configuration (variant, port, run-args, etc.)
├── Boothfile        # Build instructions (compiled from templates)
├── startup.sh       # Startup script (if any templates contribute startup segments)
├── .gitignore       # Protects .booth.password and .env-local
├── setups/          # Custom setup scripts from templates
├── home/            # Home directory team files
└── home-seed/       # Home directory defaults
```

Generated files include a header comment showing the exact command used and an `adjust` command for easy re-generation:

```bash
# Generated by: booth init new --select go/python
# Adjust with : booth init adjust --select go/python
```

---

## Common Workflows

### Quick single-language project

```bash
./booth init new --select python+uv
./booth
```

### Polyglot project with IDE

```bash
./booth init new --select go+linter/python:3.13+uv --variant codeserver
./booth
```

### Data science environment

```bash
./booth init new --select python:3.13+uv+kernel/notebook/postgresql
./booth
```

### Full desktop with AI tools

```bash
./booth init new --select java:21+maven/claude-code --variant desktop-xfce
./booth
```

### Using a recipe file

Create a `my-project.recipe`:

```
go:1.25
  + linter
  + vscode-ext

python:3.13
  + uv
  + kernel

notebook
claude-code
```

Then:

```bash
./booth init new --select @my-project.recipe
```

### Re-generate after adding a template

```bash
./booth init adjust --select go+linter/python:3.13+uv/postgresql
```
