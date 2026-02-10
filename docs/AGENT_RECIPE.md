# CodingBooth Recipe Guide

**Purpose:** Guide for AI agents and developers to create and use recipe files for `codingbooth init`.

---

## What is a Recipe?

A recipe is a text file that defines which templates, parameters, and extensions to use when initializing a new CodingBooth project. Instead of typing a long `--select` string, you save the selection to a file and reference it with `@`.

```bash
# Instead of this:
codingbooth init new ./my-project --select "go/python:3.13+uv/java:25,temurin+maven/claude-code"

# Write a recipe file and use this:
codingbooth init new ./my-project --select @my-project.recipe
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

### Spaces Around `+`

Spaces around `+` are allowed and ignored:

```
java:25 + maven + gradle        # Same as java:25+maven+gradle
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
- **Claude Code** with its credential mounts

---

## Using a Recipe

### From a file

```bash
codingbooth init new ./my-project --templates-path templates --select @my-project.recipe
```

The `@` prefix tells init to read the selection from the file.

### From stdin (heredoc)

```bash
codingbooth init new ./my-project --templates-path templates --select - <<RECIPE
go
python:3.13 + uv
claude-code
RECIPE
```

The `-` tells init to read from stdin.

### Preview without generating

```bash
codingbooth init dryrun --templates-path templates --select @my-project.recipe
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
| `claude-code` | (none) | (none) |

**Auto-selected extensions** (like `vscode-ext`) are included automatically. You only need to explicitly add non-auto extensions like `maven`, `linter`, `uv`, etc.

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

---

## Output

When you run `init new` with a recipe, you'll see a summary:

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

Add `--start` to immediately start the booth after init:

```bash
codingbooth init new ./my-project --select @recipe.txt --start
```

---

## Recipe File Conventions

- File extension: `.recipe` (recommended, but any extension works)
- Location: alongside the project, or in a shared `examples/recipes/` directory
- One template per line for readability
- Use continuation lines (`+ extension`) for multiple extensions
- Recipes can be version-controlled and shared across teams

---

## Checklist for Creating a Recipe

- [ ] List the languages/tools needed for the project
- [ ] Check available templates: `codingbooth init dryrun --select <name>`
- [ ] Specify version parameters where defaults won't do
- [ ] Add extensions explicitly (auto-selected ones are included automatically)
- [ ] Preview with `codingbooth init dryrun --select @recipe.txt`
- [ ] Verify the generated Boothfile and config.toml look correct
- [ ] Save the recipe alongside the project for team use
