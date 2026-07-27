# CodingBooth Recipe Guide

**Purpose:** Guide for AI agents and developers to create and use recipe files for `codingbooth config`.

---

## What is a Recipe?

A recipe is a text file that defines which templates, parameters, and extensions to use when initializing a new CodingBooth project. Instead of typing a long `--select` string, you save the selection to a file and reference it with `@`.

```bash
# Instead of this:
codingbooth config --no-tui ./my-project --select "go/python:3.13+uv/java:25,temurin+maven/claude-code"

# Prefer a project recipe under .booth/recipes/ (bare @name):
#   ./my-project/.booth/recipes/my-project.recipe
codingbooth config --no-tui ./my-project --select @my-project

# Or an explicit path:
codingbooth config --no-tui ./my-project --select @./my-project.recipe
```

---

## Recipe Format

A recipe file uses the same DSL as `--select`, but with friendlier multiline formatting.

### Basic Syntax

```
# Each line is a template selection
go
python
java
claude-code
```

### With Parameters

Parameters follow the template name after a colon, comma-separated:

```
go:1.24.13
python:3.12
java:21,corretto
```

Parameters are mapped positionally based on the declaration order in the template's `template.toml`. For example, Java declares `JDK_VERSION` then `JDK_VENDOR`, so `java:21,corretto` means `JDK_VERSION=21` and `JDK_VENDOR=corretto`.

Omitted parameters use their defaults.

### With Extensions

Extensions are added with `+`, either inline or on continuation lines:

**Inline:**
```
java:25,temurin+maven+gradle
```

**Continuation lines** (indented `+` on the next line):
```
java:25,temurin
  + maven
  + gradle
```

Both produce the same result. Continuation lines are more readable for multiple extensions.

### Excluding Auto-Selected Extensions

Some templates have extensions with `auto-select = true` (e.g., `credential` extensions that mount host credentials). These are included by default. To exclude them, use `~`:

**Inline:**
```
firebase~credential
claude-code+accept-edits~credential
```

**Continuation lines:**
```
firebase
  ~ credential
```

This is useful when you don't have the credentials on the host, or don't want them mounted into the container.

### Spaces Around `+` and `~`

Spaces around `+` and `~` are allowed and ignored:

```
java:25 + maven + gradle        # Same as java:25+maven+gradle
firebase ~ credential           # Same as firebase~credential
```

### Comments

Recipe files do not support comments. Every non-blank line is parsed as a template selection.

---

## Complete Recipe Example

```
go
python:3.13
  + uv
  + vscode-ext
java:25,temurin
  + maven
claude-code
```

This selects:
- **Go** with default version, plus auto-selected extensions (vscode-ext)
- **Python 3.13** with uv and vscode-ext extensions
- **Java 25 (Temurin)** with Maven, plus auto-selected extensions (vscode-ext)
- **Claude Code** with its credential mounts (auto-selected)

---

## Using a Recipe

### From a file

```bash
codingbooth config --no-tui ./my-project --templates-path templates --select @my-project.recipe
```

The `@` prefix tells config to read the selection from the file.

### Multiple --select flags

Instead of a single slash-separated string, you can repeat `--select`:

```bash
codingbooth config --no-tui ./my-project --select go --select python --select claude-code
```

This is equivalent to `--select "go/python/claude-code"`. Each `--select` value is resolved independently, so you can mix sources:

```bash
codingbooth config --no-tui ./my-project --select "go+linter" --select "python:3.13+uv" --select claude-code
codingbooth config --no-tui ./my-project --select @langs.recipe --select @tools.recipe
codingbooth config --no-tui ./my-project --select @base.recipe --select claude-code
```

### From stdin (heredoc)

```bash
codingbooth config --no-tui ./my-project --templates-path templates --select - <<RECIPE
go
python:3.13 + uv
claude-code
RECIPE
```

The `-` tells config to read from stdin.

### Preview without generating

```bash
codingbooth config --no-tui --dryrun --templates-path templates --select @my-project.recipe
```

---

## Available Templates

Current built-in templates and their parameters:

### Languages

| Template | Parameters | Extensions |
|----------|-----------|------------|
| `go` | `GO_VERSION` (default: 1.25.7) | `vscode-ext` (auto), `linter` |
| `python` | `PYTHON_VERSION` (default: 3.13.12) | `vscode-ext` (auto), `uv`, `conda` |
| `java` | `JDK_VERSION` (default: 25), `JDK_VENDOR` (default: temurin) | `vscode-ext` (auto), `maven`, `gradle`, `jenv` |

### Tools

| Template | Parameters | Extensions |
|----------|-----------|------------|
| `claude-code` | (none) | `credential` (auto) |
| `firebase` | (none) | `credential` (auto) |
| `gcloud` | (none) | `credential` (auto) |
| `codex` | (none) | `credential` (auto) |

**Auto-selected extensions** (like `vscode-ext` and `credential`) are included automatically. You only need to explicitly add non-auto extensions like `maven`, `linter`, `uv`, etc. To exclude an auto-selected extension, use `~` (e.g., `firebase~credential`).

---

## Common Recipes

### Go + Claude Code

```
go
claude-code
```

### Python Data Science

```
python:3.12
  + uv
  + conda
```

### Java Backend

```
java:21,temurin
  + maven
```

### Full Stack

```
go
python:3.13
  + uv
java:25,temurin
  + maven
claude-code
```

### Minimal Python

```
python
```

Uses all defaults: latest Python version, auto-selected vscode-ext.

### Firebase Without Credentials

```
firebase
  ~ credential
```

Selects Firebase CLI tools but excludes the auto-selected credential mount (useful in CI or when credentials aren't available on the host).

### Zsh as Default Shell

```
zsh
  + default
```

The `zsh` template is a namespace — `+default` sets `USER_SHELL=/bin/zsh` so the booth uses zsh.

**Customizing zsh in the booth:** Don't seed your host `~/.zshrc` directly — it likely references paths and plugins that don't exist in the container. Instead, create a booth-specific config:

- **`.booth/home-seed/.zshrc`** — Place a booth-tailored `.zshrc` here. It gets copied (no-clobber) on first container start, and CodingBooth appends its profile block automatically.
- **`.booth/startups/zsh-config--startup.sh`** — Append a zsh config segment at startup:
  ```bash
  #!/usr/bin/env bash
  # Append booth-specific zsh config
  cat "$HOME/code/.booth/zshrc-booth" >> ~/.zshrc
  ```

The same approach works for `.bashrc` customization.

---

## Output

When you run `config --no-tui` with a recipe, you'll see a summary:

```
  - Go (GO_VERSION=1.25.7)
    + Go VS Code Extension (auto)
  - Python (PYTHON_VERSION=3.13)
    + Python VS Code Extension (auto)
    + uv
  - Java (JDK_VERSION=25, JDK_VENDOR=temurin)
    + Java VS Code Extension (auto)
    + Maven
  - Claude Code

Initialized .booth/ in ./my-project

To start:  cd ./my-project && codingbooth
```

Generated files include a two-line comment header for easy re-generation:
```
# Generated by: booth config --no-tui ./my-project --select @my-project.recipe
# Adjust with : booth config --no-tui --overwrite --select @my-project.recipe
```
Copy the "Adjust with" line, add or remove templates from `--select`, and run it to update your configuration.

Add `--start` to immediately start the booth after config:

```bash
codingbooth config --no-tui ./my-project --select @recipe.txt --start
```

---

## Recipe File Conventions

- File extension: `.recipe` (auto-appended for bare `@name` when missing)
- **Default location:** `<project>/.booth/recipes/<name>.recipe` — use `@name`
- Explicit paths: `@./file.recipe`, `@/abs/path.recipe`, `@~/…`
- URLs: `@@https://…` or `@@host/path` (HTTPS assumed without a scheme)
- One template per line for readability
- Use continuation lines (`+ extension`) for multiple extensions
- Recipes can select project-local templates from `.booth/templates/`
- Recipes can be version-controlled and shared across teams

---

## Checklist for Creating a Recipe

- [ ] List the languages/tools needed for the project
- [ ] Check available templates: `codingbooth config --no-tui --dryrun --select <name>`
- [ ] Specify version parameters where defaults won't do
- [ ] Add extensions explicitly (auto-selected ones are included automatically)
- [ ] Save under `.booth/recipes/<name>.recipe`
- [ ] Preview with `codingbooth config --no-tui ./my-project --dryrun --select @name`
- [ ] Verify the generated Boothfile and config.toml look correct
- [ ] Commit `.booth/recipes/` (and `.booth/templates/` if used) with the project
