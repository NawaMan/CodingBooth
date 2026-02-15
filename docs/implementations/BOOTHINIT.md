# Booth Init Implementation

> **One command. A fully configured development environment.**
> `./booth init new ../my-project --select go+linter/python:3.13+uv/claude-code` creates a complete `.booth/` configuration — Boothfile, config, startup scripts — ready to launch.

Setting up a CodingBooth environment means creating a `.booth/` folder with the right Dockerfile (or Boothfile), config.toml, and possibly startup scripts, setup scripts, and home directory files. For a simple single-language project, this is straightforward. But for a polyglot project with multiple languages, AI tools, credential seeding, and IDE extensions, writing all of that by hand is tedious and error-prone.

`booth init` solves this by providing a template-driven project scaffolding system. You select what you need — languages, tools, extensions — and init compiles everything into a ready-to-use `.booth/` configuration. Templates encode best practices (correct segment ordering, proper setup script arguments, volume persistence) so you get a working environment without needing to understand every detail.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Execution Model](#execution-model)
- [Pipeline Stages](#pipeline-stages)
  - [1. Input Reading](#1-input-reading)
  - [2. DSL Parsing](#2-dsl-parsing)
  - [3. Template Resolution](#3-template-resolution)
  - [4. Compilation](#4-compilation)
  - [5. File Writing](#5-file-writing)
- [Template System](#template-system)
  - [Registry Structure](#registry-structure)
  - [Template Model](#template-model)
  - [Extensions](#extensions)
  - [Segments and Ordering](#segments-and-ordering)
- [Merge Strategies](#merge-strategies)
- [Template Cache and Download](#template-cache-and-download)
- [CLI Commands](#cli-commands)
- [Security Considerations](#security-considerations)
- [Package Structure](#package-structure)

---

## Architecture Overview

The init system follows a five-stage pipeline architecture:

```
Input Reading  ──►  DSL Parsing  ──►  Template Resolution  ──►  Compilation  ──►  File Writing
   (stdin,           (operator         (registry lookup,        (merge            (.booth/ dir
    file,             precedence,       param mapping,           segments,          creation)
    inline)           normalization)    auto-select)             resolve
                                                                 conflicts)
```

Each stage has a clear input/output contract and is independently testable. The pipeline is implemented across four packages under `pkg/boothinit/` plus the CLI entry point.

---

## Execution Model

`booth init` runs **on the host** via the `codingbooth` binary — no Docker required. This is intentional:

- **No chicken-egg problem** — `.booth/` configuration is created before any image is pulled.
- **Works before Docker is installed** — useful for CI provisioning or initial project setup.
- **Simpler execution** — no container overhead for a file-generation task.

```
./booth init new ../my-project --select go
    │
    └─► codingbooth init new ../my-project --select go
            │
            ├─► Resolve templates (local --templates-path or download from GitHub)
            ├─► Parse selection DSL
            ├─► Resolve against template registry
            ├─► Compile to output model
            └─► Write .booth/ files to ../my-project/
```

**Important:** `booth init` always initializes a **different** project folder, not the current one. The current folder must already have a `.booth/` (that's how `booth` itself runs). The target folder's `.booth/` directory may already exist — init will prompt for confirmation if any generated files would overwrite existing ones (use `--overwrite` or the `adjust` subcommand to skip the prompt).

---

## Pipeline Stages

### 1. Input Reading

The selection input can come from multiple sources, all normalized to a single DSL string:

| Source | Syntax | Example |
|--------|--------|---------|
| Inline | Direct string | `--select go+linter/python:3.13` |
| Multiple | Repeated flag | `--select go+linter --select python:3.13` |
| Stdin | `-` | `--select -` (then type or pipe) |
| File | `@path` | `--select @cool-project.recipe` |
| URL | `@@url` | `--select @@https://example.com/recipe.txt` |

Each `--select` value is resolved independently through `ReadSelectInput()` (handling `@file`, `@@url`, `-`, or plain DSL), then results are joined with `/`. This means `--select @langs.recipe --select @tools.recipe` works correctly — each file is read separately before combining.

### 2. DSL Parsing

The parser (`ParseSelectDSL`) applies strict operator precedence to transform the raw DSL string into a structured `ParsedSelection`:

**Operator precedence (split order):** `/` first, then `~`, then `+`, then `:` and `,` last.

```
go:1.25+linter+vscode-ext/firebase~credential/claude-code
│                         │                    │
├─ go                     ├─ firebase          └─ claude-code
│  params: [1.25]         │  excludes:
│  exts: [linter,         │    [credential]
│         vscode-ext]     │
```

The `~` operator excludes auto-selected extensions. For example, `firebase~credential` selects the `firebase` template but excludes the `credential` extension that would otherwise be auto-selected.

**Input normalization** (for heredoc and file compatibility):
- Spaces around `+` and `~` are stripped: `java + maven` becomes `java+maven`, `firebase ~ credential` becomes `firebase~credential`
- Lines starting with `+` or `~` join to the previous template (continuation lines)
- Remaining whitespace (newlines, tabs) becomes `/` separators

### 3. Template Resolution

The resolver (`Resolve`) validates the parsed selection against the template registry:

1. **Template lookup** — Each name must exist in the registry (error if not found).
2. **Duplicate detection** — Selecting the same template twice is an error.
3. **Positional param mapping** — CLI params (`python:3.13`) are mapped to named params (`PYTHON_VERSION=3.13`) using the template's TOML declaration order.
4. **Auto-select extensions** — Extensions with `auto-select = true` are included automatically.
5. **Exclude filtering** — Extensions listed with `~` are removed from auto-selected results. Excluding an unknown extension name is an error. Including (`+`) and excluding (`~`) the same extension is also an error.
6. **Explicit extension validation** — Named extensions must exist on the parent template.
7. **Dependency checking** — Templates with `requires = [...]` verify their dependencies are selected.

The output is a `ResolvedSelection` containing fully qualified `SelectedTemplate` entries with resolved parameter values and extension lists.

### 4. Compilation

The compiler (`Compile`) converts a `ResolvedSelection` into a `BoothOutput` using a collector pattern:

1. **Iterate** over each selected template and its extensions.
2. **Collect** segments, params, config values, and files into a central `collector` struct.
3. **Apply merge strategies** (see [Merge Strategies](#merge-strategies)) to resolve multi-template contributions.
4. **Emit** the final output model.

Key compilation steps:
- **Params** are emitted as `arg NAME=value` directives in the Boothfile, sorted alphabetically, before all segments.
- **Segments** are sorted by order number, with alphabetical tiebreak by source name.
- **Extension source names** use `"parent+ext"` format (e.g., `"java+maven"`) for tiebreaking and error messages.

### 5. File Writing

The writer (`WriteOutput`) creates the `.booth/` directory and writes all generated files:

```
.booth/
├── config.toml          # Runtime configuration (variant, port, run-args, etc.)
├── Boothfile            # Build instructions (setup/install commands)
├── startup.sh           # Startup script (if any templates contribute startup segments)
├── .gitignore           # Protects .booth.password from accidental commits
├── setups/              # Custom setup scripts from templates
├── home/                # Home directory overrides from templates
└── home-seed/           # Home directory defaults from templates
```

Safety enforced:
- If generated files already exist, init prompts for confirmation (unless `--overwrite` or `adjust`).
- Files are only written when their content is non-empty.
- `startup.sh` gets `chmod 755`; other files get `0644`.
- File copying supports both source-path-based (copy from template directory) and inline-content-based (defined in TOML) modes.

Generated files include a two-line comment header:
```
# Generated by: booth init new --version 0.21.0 --select go/python
# Adjust with : booth init adjust --version 0.21.0 --select go/python
```
The "Generated by" line preserves the exact command. The "Adjust with" line reformats it with `--select` last for easy copy-paste editing.

---

## Template System

### Registry Structure

Templates are organized in a two-level hierarchy: **categories** contain **templates**, and templates may contain **extensions**.

```
templates/
├── languages/              # Category
│   ├── meta.toml           # Category metadata (display-name, order)
│   ├── go/                 # Template (folder name = template name)
│   │   ├── template.toml   # Template definition
│   │   ├── linter--extension.toml      # Extension
│   │   └── vscode-ext--extension.toml  # Extension
│   └── python/
│       ├── template.toml
│       ├── uv--extension.toml
│       ├── pip--extension.toml
│       └── kernel--extension.toml
├── tools/
│   ├── meta.toml
│   └── claude-code/
│       ├── template.toml
│       └── accept-edits--extension.toml
└── ai-tools/
    └── ...
```

**Template names are globally unique** across all categories. Categories are organizational only — `languages/go` is referenced simply as `go` in the selection DSL. The loader (`LoadRegistry`) enforces uniqueness and rejects duplicates.

### Template Model

Each `template.toml` defines:

```toml
display-name = "Go"
display-disc = "Go language toolchain"
display-order = 10
primary = true
tags = ["go", "golang", "backend"]

# Config values (match-or-error if multiple templates set these)
dind = true                    # Optional: require Docker-in-Docker
run-args = ["-e", "GOPROXY=https://proxy.golang.org,direct"]
build-args = ["--build-arg", "FOO=bar"]

# Dependencies
requires = []                  # Templates that must also be selected

# Parameters with defaults and suggestions
[params.GO_VERSION]
default = "1.25.7"
suggests = ["1.25.7", "1.24.13", "1.23.12"]

# Boothfile and startup segments (inline)
[segments]
Boothfile = """
setup go ${GO_VERSION}
install go golang.org/x/tools/gopls@latest
"""
```

Alternatively, segments can be defined as separate files: `Boothfile`, `Boothfile--60`, `startup.sh`, `startup--90.sh`. The numeric suffix controls ordering (default is 50).

### Extensions

Extensions are sub-templates defined alongside their parent. They:
- Inherit the parent's parameters.
- Can define their own additional parameters.
- Are selected either explicitly (`go+linter`) or automatically (`auto-select = true`).
- Can declare `requires` for cross-template dependencies (e.g., a kernel extension requires `notebook`).

```toml
# go/linter--extension.toml
display-name = "Go Linter"
auto-select = false
tags = ["go", "lint"]

[segments]
Boothfile = """
install go github.com/golangci/golangci-lint/cmd/golangci-lint@latest
"""
```

### Segments and Ordering

Segments are the building blocks of the generated Boothfile and startup.sh. When multiple templates are selected, all their segments are merged globally and sorted:

| Order | Purpose                    | Examples                                                          |
|-------|----------------------------|-------------------------------------------------------------------|
| 40    | Infrastructure (desktops)  | `setup xfce`, `setup kde`                                        |
| 50    | Base setups (default)      | `setup go`, `setup python`, `setup jdk`                          |
| 60    | Dependent setups           | `setup kotlin` (needs Java), `setup codeserver`, `setup notebook` |
| 65    | Language VS Code extensions | `setup go-code-extension` (needs codeserver/vscode)              |
| 70    | Notebook kernels           | `setup go-nb-kernel` (needs notebook)                            |
| 90    | Post-setup steps           | `pip install -r requirements.txt`                                |

**Tiebreaking:** When two segments share the same order, they are sorted alphabetically by source template name (e.g., `go` before `python` at order 50).

---

## Merge Strategies

When multiple templates contribute to the same output, three merge strategies are applied:

### 1. Concatenation (Boothfile, startup.sh)

Segments from all templates are concatenated in order. This is the primary strategy for build and startup instructions.

### 2. Match-or-Error (config scalars)

For `variant`, `port`, `timezone`, `dind`, and `cmds`: if multiple templates define the same field, the values **must match**. If they conflict, init produces an error with source tracking:

```
Error: conflicting "variant" values: "codeserver" (from go) vs "notebook" (from python)
```

This encourages templates to set these values sparingly.

### 3. Combine-and-Dedup (config arrays)

For `run-args` and `build-args`: arrays from all templates are concatenated and deduplicated. Deduplication is aware of paired flags — `-v foo:/bar` and `-e KEY=VAL` are treated as two-token units, so `-v foo:/bar` from one template won't collide with `-v baz:/qux` from another.

---

## Template Cache and Download

Templates are distributed as `templates.zip` alongside each CodingBooth release.

**Cache location:**
```
~/.cache/codingbooth/versions/<version>/templates.zip
```

Respects `XDG_CACHE_HOME` if set.

**Download URL:**
```
https://github.com/NawaMan/CodingBooth/releases/download/<version>/templates.zip
```

**Extraction:** Every run extracts to a fresh temp directory (`/tmp/cb-init-<random>/`) and cleans up on completion. This prevents tampering with cached extractions — since templates generate files that end up in `.booth/` (including setup scripts and startup commands), integrity is critical.

**Development override:** Use `--templates-path <dir>` or set `CB_TEMPLATES_PATH` to load templates from a local directory, skipping download entirely.

---

## CLI Commands

### List Templates

```bash
./booth init list          # Primary templates only
./booth init list --full   # All templates including secondary
```

### Search Templates

```bash
./booth init search "python"   # Prefix match on name, display-name, and tags
```

### Create New Project

```bash
./booth init new --select go+linter/python:3.13+uv/claude-code
./booth init new ../my-project --select go+linter/python:3.13+uv/claude-code
```

The path defaults to the current directory if omitted.

### Re-generate (Adjust)

```bash
./booth init adjust --select go+linter/python:3.13+uv/claude-code+django
```

The `adjust` subcommand is equivalent to `new --overwrite` — it overwrites existing files without prompting.

### Preview Without Writing

```bash
./booth init dryrun --select go+linter/python:3.13
```

### Flags

| Flag | Description |
|------|-------------|
| `--select <dsl>` | Template selection (repeatable; inline, `-` for stdin, `@file`, `@@url`) |
| `--templates-path <dir>` | Local templates directory |
| `--version <ver>` | Use templates from a specific release version |
| `--start` | Launch `codingbooth run --code <path>` after init |
| `--overwrite` | Overwrite existing files without prompting |
| `--debug` | Print resolved selection and compiled output as JSON |
| `--full` | Show all templates in list (including non-primary) |

---

## Security Considerations

- **Zip Slip protection** — Extraction rejects entries containing `../` path traversal or symbolic links, and verifies all resolved paths stay within the destination directory.
- **Fresh extraction** — Templates are extracted from the verified zip every time, not from a cached directory that could be tampered with.
- **Target safety** — `new` prompts for confirmation before overwriting existing files (use `--overwrite` or `adjust` to skip).
- **Gitignore generation** — Automatically creates `.booth/.gitignore` to protect `.booth.password` from accidental commits.
- **HTTP timeout** — URL fetching (`@@url`) uses a 30-second timeout.

---

## Package Structure

```
cli/src/
├── cmd/codingbooth/
│   └── init.go                  # CLI entry point, subcommand routing
│
└── pkg/boothinit/
    ├── output/                  # Output model and serialization
    │   ├── model.go             # BoothOutput, ConfigToml, BoothfileContent, etc.
    │   ├── header.go            # Generated file header (Generated by / Adjust with)
    │   ├── config.go            # config.toml TOML serialization
    │   ├── boothfile.go         # Boothfile generation (syntax header)
    │   ├── startup.go           # startup.sh generation (shebang + set -e)
    │   ├── files.go             # File copy logic (source-path and inline)
    │   └── writer.go            # WriteOutput orchestrator
    │
    ├── template/                # Template model and loading
    │   ├── model.go             # TemplateRegistry, Category, Template, Param, Segment
    │   ├── loader.go            # LoadRegistry — reads directory tree, TOML parsing
    │   ├── search.go            # Prefix search on name/display-name/tags
    │   └── display.go           # Formatted template listing
    │
    ├── selection/               # Selection parsing and resolution
    │   ├── model.go             # ParsedSelection, ResolvedSelection, SelectMode
    │   ├── parser.go            # DSL parsing, input normalization, @file/@@url
    │   └── resolver.go          # Registry lookup, param mapping, auto-select
    │
    ├── compiler/                # Template + selection --> output
    │   └── compiler.go          # Compile() with collector pattern
    │
    └── cache/                   # Template download and caching
        └── cache.go             # GitHub release download, zip extraction
```

### Template Library

The template library lives at the repository root under `templates/` and is packaged into `templates.zip` for each release:

```
templates/
├── README.md              # Authoring guidelines
├── languages/             # 19 language templates (go, python, java, rust, ...)
├── ai-tools/              # 5 AI tool templates (claude-code, codex, ...)
├── tools/                 # 11 tool templates (notebook, neovim, dind, ...)
├── ides/                  # 11 IDE templates (idea, pycharm, codeserver, ...)
├── desktops/              # 6 desktop templates (xfce, kde, ...)
├── databases/             # 3 database templates (postgresql, mysql, sqlite)
└── browsers/              # 3 browser templates (chromium, firefox, chrome)
```

Total: **58 templates** and **36 extensions** across **7 categories**.
