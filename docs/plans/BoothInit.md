# init Feature Plan

This document outlines the design and implementation plan for the `./booth init` command, which provides guided configuration setup for CodingBooth.

## Table of Contents

- [Overview](#overview)
- [CLI Commands](#cli-commands)
- [Quick Mode](#quick-mode)
- [Advanced Mode](#advance-mode)
- [Template Structure](#template-structure)
- [File Generation](#file-generation)
- [Implementation Approach](#implementation-approach)
- [Implementation Phases](#implementation-phases)
- [Open Items](#open-items)
- [Example Templates](#example-templates)

## Overview

`./booth init` is a wizard-style tool that helps users create `.booth/` configuration files. It runs **on the host** as part of the `coding-booth` binary, downloading templates from GitHub releases.

**Why on the host (not in container)?**
- No Docker required for init — works before Docker is installed
- Solves chicken-egg: `.booth/` config created before image pull
- Can init, then run `./booth` to pull image
- Simpler execution model

The feature has three interfaces:

| Interface | Purpose | Invocation |
|-----------|---------|------------|
| **CLI** | Scriptable, testing | `./booth init --select go --non-interactive` |
| **Quick** | Fast setup with sensible defaults | `./booth init` (default) |
| **Advance** | Full control via template browser | `./booth init --advance` |

---

## CLI Commands

The CLI interface serves both as a testing interface for backend logic and as a scriptable alternative to the interactive modes.

### List Templates

```bash
./booth init --list
```

Output:
```
Languages
  python          Python                     [python, scripting]
  go              Go                         [golang, backend]
  java            Java                       [java, jvm]
  nodejs          Node.js                    [node, javascript]
  rust            Rust                       [rust, systems]

Frameworks
  spring          Spring Boot                [java, web, backend]
  django          Django                     [python, web, backend]

Tools
  claude-code     Claude Code                [ai, assistant, anthropic]
  neovim          Neovim                     [editor, vim]

Credentials
  ssh             SSH Keys                   [git, authentication]
  claude          Claude Code Credentials    [ai, anthropic]
```

### Search Templates

```bash
./booth init --search "go"
```

Output:
```
Languages
  go              Go                         [golang, backend]

Frameworks  
  golang-migrate  Golang Migrate             [go, database, migration]
```

### Select and Generate

```bash
# Basic selection with defaults
./booth init --select go,claude-code --variant codeserver --non-interactive

# With param overrides (format: template.setup.param=value)
./booth init --select go,java \
  --param "go.go--setup.version=1.24" \
  --param "java.jdk--setup.version=21" \
  --param "java.jdk--setup.vendor=corretto" \
  --variant desktop-xfce --non-interactive

# Shorthand when setup name matches template (common case)
./booth init --select python --param "python.version=3.11" --non-interactive

# Dry run to preview
./booth init --select python,django --variant codeserver --dryrun

# Force overwrite existing .booth/
./booth init --select nodejs --variant codeserver --non-interactive
```

**Param format:** `template.setup.param=value` or `template.param=value` (shorthand when unambiguous)
**Implementation note:** Let not implement the shorthand for now, let see how things go first.

### CLI Flags Reference

| Flag | Description |
|------|-------------|
| `--list` | List all templates by category |
| `--search <term>` | Search templates (prefix match of name, display-name and tag) |
| `--select <names>` | Comma-separated template names to select – the name must fully match. Error if not. |
| `--param <name.param=value>` | Override a template's setup param |
| `--variant <name>` | Set variant (codeserver, notebook, desktop-xfce, etc.) |
| `--port <value>` | Set port (number, NEXT, RANDOM) |
| `--non-interactive` | Generate files immediately (no interactive mode) |
| `--dryrun` | Print what would be generated without writing files |
| `--templates-path <path>` | Override templates location (for development) |
| `--advance` | Enter Advanced mode TUI |

---

## Quick Mode

### Flow

```
Page 1: Project Type  →  Page 2: Variant  →  Final: Generate
```

### Page 1: Project Type

```
Select project type:
  1) Python
  2) Node.js
  3) Go
  4) Java
  5) Rust
  6) Empty
  7) AI Agent
  8) Advanced mode
  9) Feeling lucky (Random)
Enter choice [1-9]:
```

### Page 2: Variant

```
Select environment:
  1) VS Code in browser (codeserver)
  2) Jupyter Notebook
  3) Full desktop (XFCE)
  4) Full desktop (KDE)
  5) Terminal only (base)
Enter choice [1-5]:
```

### Final: Generate

```
Configuring your booth...

Project:  Go
Variant:  codeserver
Port:     NEXT

Will create:
  .booth/config.toml
  .booth/Dockerfile

Dockerfile will install:
  ✓ Go (latest)
  ✓ VS Code Go extension

Proceed? [Y/n]
```

### Quick Mode Mapping

Quick mode selections map to hardcoded template combinations. Each includes `required` and `recommended` items from templates. **Parameters use their default values in Quick mode.**

```toml
# Suggested location: /templates/quick-mode.toml

[python]
templates = ["python", "python-code-extension"]
variant = "codeserver"

[nodejs]
templates = ["nodejs", "nodejs-code-extension"]
variant = "codeserver"

[go]
templates = ["go", "go-code-extension"]
variant = "codeserver"

[java]
templates = ["java", "java-code-extension"]
variant = "codeserver"

[rust]
templates = ["rust", "rust-code-extension"]
variant = "codeserver"

[empty]
templates = []
variant = "base"

[ai-agent]
templates = ["claude-code", "claude-credentials"]
variant = "base"
```

---

## Advanced Mode

### UI Layout

```
═══════════════════════════════════════════════════════════════════
 Advanced Booth Configuration
═══════════════════════════════════════════════════════════════════
 [Find ^F]  [Setting ^S]  [Done ^D]

 [Languages ^1]  [Frameworks ^2]  [Tools ^3]  [Credentials ^4]
───────────────────────────────────────────────────────────────────

 Languages
 [ ] 1  Python
 [#] 2  Go
        [#] 2-1  VS Code extension
        [ ] 2-2  linter
 [#] 3  Node.js
 [ ] 4  Java
 [ ] 5  Rust

───────────────────────────────────────────────────────────────────
 Toggle [1-5, 2-1, 2-2]
```

### Selection Display

**Multi-select (categories like Languages, Tools, Credentials):**

| Display | Meaning |
|---------|---------|
| `[#]` | Selected |
| `[ ]` | Not selected |
| `[#] 2-1` | Sub-item selected |
| `[ ] 2-1` | Sub-item not selected |
| `[*]` | Auto-selected (dependency of another selection) |

**Single-select (Variant in Config screen):**

| Display | Meaning |
|---------|---------|
| `(#)` | Selected |
| `( )` | Not selected |

### Dependency Behavior

When a template with `requires` is selected, dependencies are auto-selected:

```
 Frameworks
 [#] 1  Spring Boot              ← user selected

 Languages
 [*] 4  Java                     ← auto-selected (required by Spring Boot)
```

- `[*]` indicates auto-selected via dependency
- User cannot deselect `[*]` while the dependent template is selected
- Deselecting Spring Boot releases Java (becomes `[ ]` unless selected directly)

### Parameters

When a template's setup has `params`, they appear below the template (before sub-templates):

```
 Languages
 [ ] 1  Python
 [#] 2  Go
        Version: [latest    ▼]        ← param from go--setup.sh
        [#] 2-1  VS Code extension    ← sub-template (subfolder)
        [ ] 2-2  linter               ← sub-template (subfolder)
 [ ] 3  Node.js
 [#] 4  Java
        JDK Version: [21      ▼]      ← params from jdk--setup.sh
        Vendor:      [temurin ▼]
        [#] 4-1  VS Code extension
        [ ] 4-2  Maven
               Version: [3.9.6   ▼]   ← param from mvn--setup.sh (in sub-template)
```

**Parameter types:**

| Type | Display | Example |
|------|---------|---------|
| `choice` | Dropdown `[value ▼]` | Version: `[latest ▼]` with options |
| `text` | Text input `[value___]` | Custom path: `[/opt/go__]` |

**Interaction:**
- Press Enter on parameter line to edit
- For `choice`: cycle through options or show menu
- For `text`: enter edit mode, type value, press Enter to confirm

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `^F` | Open find |
| `^S` | Open setting screen |
| `^D` | Done, generate files |
| `^1` - `^N` | Switch category tabs |
| `1-9` | Toggle item |
| `N-M` | Toggle sub-item (e.g., `2-1`) |

### Config Screen (^C)

```
═══════════════════════════════════════════════════════════════════
 Container Configuration
═══════════════════════════════════════════════════════════════════
 [Back ^B]  [Done ^D]

───────────────────────────────────────────────────────────────────

 Variant
 ( ) 1  VS Code in browser (codeserver)
 (#) 2  Jupyter Notebook
 ( ) 3  Full desktop (XFCE)
 ( ) 4  Full desktop (KDE)
 ( ) 5  Terminal only (base)

 Port:      [NEXT___________]
 Timezone:  [America/Toronto]
 DinD:      [ ] Enable Docker-in-Docker

───────────────────────────────────────────────────────────────────
```

### Search Screen (^S)

```
═══════════════════════════════════════════════════════════════════
 Search
═══════════════════════════════════════════════════════════════════
 [Back ^B]

───────────────────────────────────────────────────────────────────

 Languages
 [#] L2    Go
     [#] L2-1  VS Code extension
     [ ] L2-2  linter

 Frameworks
 [ ] F3    golang-migrate

───────────────────────────────────────────────────────────────────
 > go█
```

**Match behavior:** Prefix match on any word in name, display-name, or tags.

Examples:
- `go` matches "go", "golang-migrate"
- `code` matches "claude-code", "codeserver"
- `py` matches "python", "pycharm"

---

## Template Structure

### Directory Layout

```
/templates/
├── quick-mode.toml                    # Quick mode mappings
├── languages/
│   ├── meta.toml                      # Category metadata
│   ├── python/
│   │   ├── spec.toml                  # Template spec
│   │   ├── extension/                 # Sub-template
│   │   │   └── spec.toml
│   │   └── extras--setup.sh           # Custom setup script (optional)
│   ├── go/
│   │   ├── spec.toml
│   │   ├── extension/
│   │   │   └── spec.toml
│   │   └── linter/
│   │       └── spec.toml
│   └── nodejs/
│       └── spec.toml
├── frameworks/
│   ├── meta.toml
│   ├── django/
│   │   └── spec.toml
│   └── fastapi/
│       └── spec.toml
├── tools/
│   ├── meta.toml
│   ├── claude-code/
│   │   └── spec.toml
│   └── neovim/
│       └── spec.toml
└── credentials/
    ├── meta.toml
    ├── ssh/
    │   └── spec.toml
    └── claude/
        └── spec.toml
```

### Category meta.toml

```toml
display-name = "Languages"
order = 1
```

Categories are displayed in `order` sequence. Keyboard shortcuts (^1, ^2, etc.) assigned by order.

### Template spec.toml

```toml
display-name = "Go"
display-order = 30                      # Display order within category
tags = ["golang", "backend", "compiled"]

# Dependencies - auto-selected when this template is selected
requires = []                           # e.g., ["languages/java"] for Spring

# Setups to add to Dockerfile
[[setups]]
name = "go--setup.sh"                   # Looks in built-in first, then template folder
order = 60                              # RUN order in Dockerfile (maps to 50-79 ranges)
preference = "required"                 # required | recommended | optional

  # Parameters for this setup
  [[setups.params]]
  name = "version"
  display-name = "Go Version"
  type = "choice"                       # choice | text
  default = "latest"
  choices = ["latest", "1.24", "1.23", "1.22"]

[[setups]]
name = "go-tools--setup.sh"
order = 65
preference = "optional"

# Files to copy to .booth/home or .booth/home-seed
[[files]]
name = ".golangci.yml"                  # Looks in built-in first, then template folder
target = "home-seed"                    # home | home-seed
order = 50
preference = "optional"

# Scripts to add to .booth/startup.sh
[[startup-scripts]]
name = "go-env-setup.sh"
order = 60
preference = "recommended"

# Extra arguments for docker run
[[run-args]]
values = ["-e", "GOPROXY=https://proxy.golang.org,direct"]
preference = "optional"

[[run-args]]
values = ["-v", "/mnt/data:/data"]
preference = "optional"
```

### Preference Behavior

| Preference | Quick Mode | Advanced Mode |
|------------|------------|--------------|
| `required` | Auto-included | Auto-selected, cannot deselect |
| `recommended` | Auto-included | Pre-selected, can deselect |
| `optional` | Excluded | Not selected, can select |

### Sub-templates

Sub-templates are subfolders with their own `spec.toml`. They are:
- Standalone (no inheritance from parent)
- Displayed as sub-items (e.g., `2-1`, `2-2`) when parent is selected
- Independent selection (selecting parent doesn't auto-select children)

---

## File Generation

### Output Structure

```
.booth/
├── config.toml       # Variant, port, timezone, dind, run-args
├── Dockerfile        # Header + setups ordered by setup.order
├── startup.sh        # Startup scripts ordered by order (if any)
├── home/             # Files with target="home"
└── home-seed/        # Files with target="home-seed"
```

### config.toml Generation

```toml
variant = "codeserver"
port = "NEXT"
timezone = "America/Toronto"
# dind = true  (if enabled)

run-args = [
    # Aggregated from all selected templates
    "-e", "GOPROXY=https://proxy.golang.org,direct",
    "-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro"
]
```

### Dockerfile Generation

```dockerfile
# syntax=docker/dockerfile:1.7
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest
FROM nawaman/codingbooth:${CB_VARIANT_TAG}-${CB_VERSION_TAG}

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ARG CB_SETUPS=/opt/codingbooth/setups
ARG CB_VARIANT_TAG=codeserver
ARG CB_VERSION_TAG=latest

WORKDIR /opt/codingbooth/setups

# Setups ordered by order field
# Args generated from setup's params in definition order
RUN ./python--setup.sh 3.12             # order=60, params: version=3.12
RUN ./go--setup.sh 1.24                 # order=60, params: version=1.24
RUN ./jdk--setup.sh 21 temurin          # order=60, params: version=21, vendor=temurin
RUN ./mvn--setup.sh 3.9.6               # order=65, params: version=3.9.6
RUN ./go-code-extension--setup.sh       # order=75, no params
```

### startup.sh Generation (if any startup-scripts)

```bash
#!/bin/bash
# Auto-generated by init

# go-env-setup.sh (order=60)
<contents of go-env-setup.sh>

# another-startup.sh (order=70)
<contents of another-startup.sh>
```

---

## Implementation Approach

### Execution Model

The `./booth init` command runs **on the host** via the `coding-booth` binary:

```
./booth init --select go
    │
    └─► coding-booth init --select go
            │
            ├─► Check ~/.cache/codingbooth/<version>/templates.zip
            │       │
            │       ├─► If missing: download from GitHub releases
            │       │   https://github.com/NawaMan/CodingBooth/releases/download/<version>/templates.zip
            │       │   Verify hash, save with chmod 400
            │       │
            │       └─► If exists: verify hash
            │
            ├─► Extract to /tmp/cb-init-<random>/
            │   (fresh extraction every time for security -- might explor setting dir to 700 and files to 400 as cache later)
            │
            ├─► Read templates, process selection
            │
            ├─► Generate .booth/ files
            │
            └─► Clean up /tmp/cb-init-<random>/
```

**Why extract every time?**
Templates end up in `.booth/` (e.g., Dockerfile, startup scripts). A compromised cached extraction could be exploited for credential theft or code injection. Fresh extraction from the verified zip ensures integrity.

### Template Download & Cache

**Download URL:**
```
https://github.com/NawaMan/CodingBooth/releases/download/<version>/templates.zip
```

**Cache location:**
```
~/.cache/codingbooth/
└── <version>/
    ├── templates.zip      # chmod 400
    └── templates.zip.sha256
```

**Cache behavior:**
1. Check if `~/.cache/codingbooth/<version>/templates.zip` exists
2. If exists, verify SHA256 hash
3. If missing or hash mismatch, download fresh
4. Set permissions to `400` (read-only, owner only)

**Extraction:**
```
/tmp/cb-init-<random-uuid>/
├── languages/
├── frameworks/
├── tools/
├── credentials/
└── quick-mode.toml
```

Extracted directory is deleted after init completes (or on error).

### Benefits of This Approach

- **No Docker needed for init** — works before Docker is installed
- **Solves chicken-egg** — `.booth/` config created before image pull
- **Secure** — fresh extraction prevents tampering
- **Offline capable** — works if templates already cached
- **Version aligned** — template version matches `coding-booth` binary version

### Language: Go

The init logic is part of the `coding-booth` binary, so it must be implemented in Go.

### File Locations

| File | Location |
|------|----------|
| Init logic | `coding-booth` binary (on host) |
| Template cache | `~/.cache/codingbooth/<version>/templates.zip` |
| Temp extraction | `/tmp/cb-init-<random>/` |
| Output | `./.booth/` |

**Development override:** Use `--templates-path` to load templates from a local directory (skips download/extraction).

### Suggested Package Structure

```
cmd/
└── coding-booth/
    └── main.go

internal/
└── init/
    ├── cache/
    │   ├── download.go       # Download templates.zip from GitHub
    │   ├── verify.go         # SHA256 verification
    │   └── extract.go        # Extract to temp dir
    ├── output/
    │   ├── model.go          # Output data structures
    │   ├── config.go         # config.toml serialization
    │   ├── dockerfile.go     # Dockerfile generation
    │   └── writer.go         # File writing orchestration
    ├── template/
    │   ├── model.go          # Template data structures
    │   ├── loader.go         # TOML parsing and registry
    │   └── resolve.go        # Template → Output conversion
    ├── cli/
    │   ├── list.go           # --list command
    │   ├── search.go         # --search command
    │   └── select.go         # --select --non-interactive command
    ├── quick/
    │   └── quick.go          # Quick mode UI
    └── tui/
        └── app.go            # Advanced mode TUI (using bubbletea)
```

---

## Implementation Phases

### Phase 1: Output Data Model & Serialization
- [ ] Define Go structs for output:
  - `BoothConfig` (config.toml content)
  - `Dockerfile` (header + setups list)
  - `StartupScript` (startup.sh content)
  - `HomeFiles` (files to copy to home)
  - `HomeSeedFiles` (files to copy to home-seed)
- [ ] Implement serialization to files:
  - Write `.booth/config.toml`
  - Write `.booth/Dockerfile`
  - Write `.booth/startup.sh` (if any)
  - Copy files to `.booth/home/` and `.booth/home-seed/`
  - startup script will be a bash script with shebang and -e flag to terminate on error and call to script specified by the template.
- [ ] Test with hardcoded data

### Phase 2: Template Data Model
- [ ] Define Go structs for templates:
  - `Category` (from meta.toml)
  - `Template` (from spec.toml)
  - `Setup` (with nested Params)
  - `Param` (choice/text)
  - `RunArg`, `File`, `StartupScript`
- [ ] Define selection state:
  - `SelectionState` (selected, auto-selected via dependency)
  - `ParamValues` (user-specified or default)

### Phase 3: Template → Output Conversion
- [ ] Implement merge logic:
  - Collect all setups from selected templates
  - Sort by order field
  - Expand params into setup args
  - Aggregate run-args (dedupe?)
  - Collect files and startup scripts
- [ ] Implement dependency resolution:
  - Auto-select `requires` templates
  - Detect circular dependencies
- [ ] Implement preference filtering:
  - `required` always included
  - `recommended` included by default (configurable)
  - `optional` excluded by default
- [ ] Test with hardcoded template + selection

### Phase 4: Template Loading
- [ ] Implement TOML parsing for spec.toml, meta.toml
- [ ] Build template registry from extracted temp directory
- [ ] Validate template structure
- [ ] Integrate with cache/download from Phase 0

### Phase 5: CLI Commands (Backend Testing Interface)
- [ ] `./booth init --list`
  - List all templates by category
  - Show: name, display-name, tags
- [ ] `./booth init --search "term"`
  - Prefix match on name, display-name, tags
  - Show matching templates
- [ ] `./booth init --select name1,name2 --non-interactive`
  - Select templates by name
  - Error if name not found
  - Use default params, generate files immediately
- [ ] `./booth init --select name1,name2 --param "name1.version=1.24" --non-interactive`
  - Override specific param values
- [ ] `./booth init --select name1 --variant codeserver --non-interactive`
  - Specify variant via CLI
- [ ] Common flags:
  - `--dryrun` — print what would be generated
  - `--templates-path` — override templates location

### Phase 6: Quick Mode UI
- [ ] Simple numbered menu for project type
- [ ] Simple numbered menu for variant
- [ ] Confirmation prompt
- [ ] Map quick selections to template names (hardcoded or quick-mode.toml)
- [ ] Generate files using same backend

### Phase 7: Advanced Mode TUI
- [ ] TUI framework setup
- [ ] Category tabs navigation
- [ ] Item list with selection toggle (`[ ]`, `[#]`, `[*]`)
- [ ] Sub-item display and toggle
- [ ] Params editing (choice dropdown, text input)
- [ ] Seetting screen (^S) for variant, port, timezone, dind
- [ ] Find screen (^F) with prefix matching
- [ ] Review and generate (^D)

### Phase 8: Template Cache & Download
- [ ] Implement template download from GitHub releases:
  - URL: `https://github.com/NawaMan/CodingBooth/releases/download/<version>/templates.zip`
  - Download with progress indicator
- [ ] Implement cache management:
  - Cache location: `~/.cache/codingbooth/<version>/templates.zip`
  - Download SHA256 hash file
  - Verify hash on download and on use
  - Set permissions to `400`
- [ ] Implement extraction to temp directory:
  - Extract to `/tmp/cb-init-<random-uuid>/`
  - Clean up on completion or error
- [ ] Support `--templates-path` for local development

---

## Open Items

1. **Rust setup script** — needs to be created (`rust--setup.sh`)
2. **AI Agent templates** — which tools to include (Claude Code confirmed, others TBD)
3. **Conflict resolution** — if multiple templates specify same run-arg, last wins? dedupe?
5. **Circular dependencies** — validate that `requires` doesn't create cycles
6. **Rename existing init** — current `./booth init` command needs new name (e.g., `./booth setup`? `./booth bootstrap`?)
7. **Template versioning** — should template version match `coding-booth` binary version exactly, or allow compatibility ranges?
8. **Offline mode** — what happens if download fails and no cache exists? Clear error message needed.
9. **Hash file format** — `templates.zip.sha256` format (just hash, or `hash filename`?)

---

## Example Templates to Create

### languages/go/spec.toml
```toml
display-name = "Go"
display-order = 30
tags = ["golang", "backend"]

[[setups]]
name = "go--setup.sh"
order = 60
preference = "required"

  [[setups.params]]
  name = "version"
  display-name = "Version"
  type = "choice"
  default = "latest"
  choices = ["latest", "1.24", "1.23", "1.22"]
```

### languages/python/spec.toml
```toml
display-name = "Python"
display-order = 10
tags = ["python", "scripting"]

[[setups]]
name = "python--setup.sh"
order = 60
preference = "required"

  [[setups.params]]
  name = "version"
  display-name = "Version"
  type = "choice"
  default = "latest"
  choices = ["latest", "3.12", "3.11", "3.10"]
```

### languages/java/spec.toml
```toml
display-name = "Java"
display-order = 40
tags = ["java", "jvm"]

[[setups]]
name = "jdk--setup.sh"
order = 60
preference = "required"

  [[setups.params]]
  name = "version"
  display-name = "JDK Version"
  type = "choice"
  default = "21"
  choices = ["24", "21", "17", "11"]

  [[setups.params]]
  name = "vendor"
  display-name = "Vendor"
  type = "choice"
  default = "temurin"
  choices = ["temurin", "corretto", "zulu", "oracle"]
```

### languages/go/extension/spec.toml
```toml
display-name = "VS Code Extension"
display-order = 10
tags = ["vscode", "ide"]

[[setups]]
name = "go-code-extension--setup.sh"
order = 75
preference = "recommended"
```

### languages/java/maven/spec.toml
```toml
display-name = "Maven"
display-order = 20
tags = ["build", "java"]

[[setups]]
name = "mvn--setup.sh"
order = 65
preference = "recommended"

  [[setups.params]]
  name = "version"
  display-name = "Version"
  type = "choice"
  default = "3.9.6"
  choices = ["3.9.6", "3.9.5", "3.8.8"]
```

### credentials/ssh/spec.toml
```toml
display-name = "SSH Keys"
display-order = 10
tags = ["git", "authentication"]

[[run-args]]
values = ["-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro"]
preference = "required"
```

### tools/claude-code/spec.toml
```toml
display-name = "Claude Code"
display-order = 10
tags = ["ai", "assistant", "anthropic"]

[[setups]]
name = "claude-code--setup.sh"
order = 70
preference = "required"

[[run-args]]
values = ["-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro"]
preference = "recommended"

[[run-args]]
values = ["-v", "~/.claude:/etc/cb-home-seed/.claude:ro"]
preference = "recommended"
```

### frameworks/spring/spec.toml
```toml
display-name = "Spring Boot"
display-order = 10
tags = ["java", "web", "backend"]

# Auto-selects Java when Spring is selected
requires = ["languages/java"]

[[setups]]
name = "spring-boot--setup.sh"
order = 65
preference = "required"
```

### frameworks/django/spec.toml
```toml
display-name = "Django"
display-order = 20
tags = ["python", "web", "backend"]

# Auto-selects Python when Django is selected
requires = ["languages/python"]

[[setups]]
name = "django--setup.sh"
order = 65
preference = "required"
```
# Appendix
- We will need a program to validate the template and run with GitHub action to release. So that we avoid problem like typo and circular or missing dependency.
- As opinion present, we need to have logging printed out when --verbose.
- The run-args  `-v` and `-e` should be duduplicated.
- Tie breaker for same ordering is alphabetical order of the name.
- Expand `~` in the binding  — handle that expansion.