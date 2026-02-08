# init Feature Plan

This document outlines the design and implementation plan for the `./booth init` command, which provides guided configuration setup for CodingBooth.

## Table of Contents

- [Overview](#overview)
- [CLI Commands](#cli-commands)
- [Template Structure](#template-structure)
- [File Generation](#file-generation)
- [Implementation Approach](#implementation-approach)
- [Implementation Phases](#implementation-phases)
- [Appendix](#appendix)

## Overview

`./booth init` is a wizard-style tool that helps users create `.booth/` configuration files. It runs **on the host** as part of the `codingbooth` binary, downloading templates from GitHub releases.

The future generate may introduce template repository to make this more expandable.

**Why on the host (not in container)?**
- No Docker required for init — works before Docker is installed
- Solves chicken-egg: `.booth/` config created before image pull
- Can init, then run `./booth` to pull image
- Simpler execution model

The feature is visioned to have three interfaces:

| Interface   | Purpose                           | Invocation                                   |
|-------------|-----------------------------------|----------------------------------------------|
| **CLI**     | Scriptable, testing               | `./booth init on ../new-project --select go` |
| **Quick**   | Fast setup with sensible defaults | `./booth init`                               |
| **Advance** | Full control via template browser | `./booth init --advance`                     |

That means it is designed to implement all three but we may not actually do it.

**Important Note:**
Reminded that `booth` is a wrapper to `codingbooth` binary which will be download using `booth install`.
So to have `booth` running, you will have to be in a project folder that has ALREADY BEEN initialize.
Therefore, the `booth init ...` command aims to initialize ANOTHER project folder and not this one.
That is why the target location (the `on ...`) must not be this folder.

---

## CLI Commands

The CLI interface serves both as a testing interface for backend logic and as a scriptable alternative to the interactive modes.

### List Templates

```bash
./booth init list
```

Output:
```
Languages
  python                Python                     [python, scripting]
  go                    Go                         [golang, backend]
  java                  Java                       [java, jvm]
  nodejs                Node.js                    [node, javascript]
  rust                  Rust                       [rust, systems]

Frameworks
  spring                Spring Boot                [java, web, backend]
  django                Django                     [python, web, backend]

Tools
  claude-code           Claude Code                [ai, assistant, anthropic]
  neovim                Neovim                     [editor, vim]

Credentials
  ssh-credentials       SSH Keys                   [git, authentication]
  claude-credentials    Claude Code Credentials    [ai, anthropic]
```

### Search Templates

```bash
./booth init search "go"
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
./booth init on ../new-project --default variant=codeserver --default port=12345 --select go/claude-code

# Short
./booth init on ../new-project --select go/claude-code

# Option 1
./booth init on ../new-project --select go:1.24/java:21,corretto

# Option 2
./booth init on ../new-project --select - <<SELECT
  go:1.24
  java:21,corretto
SELECT

# Option 3
./booth init on ../new-project --select @file

# Option 4
./booth init on ../new-project --select @@url

# Dry run to preview
./booth init dryrun --select python+django
```

The selection DSL is:
`<name>:<param1>,<param2>+<extension1>+<extension2>/<name2>:<param2-1>,<param2-2>+<extension2-1>+<extension2-2>`

**Operator precedence:** Split `/` first, then `+`, then `:` and `,` last.
For heredoc and stdin input, whitespace is normalized before parsing.

Note: If `@file` or `@@url` is used, it consumes the entire value — no `/` parsing is applied.

> **Design note:** The `--select` DSL is intentionally simple — it cannot support every possible scenario. It aims to cover the common init cases. Users with more complex needs should modify the generated configs by hand after init. Multiple input methods (inline, heredoc, `@file`, `@@url`) are provided so users can work around platform-specific escaping or delimiter issues.

**How parameters work:** Parameters are translated to `ARG` directives in the generated Boothfile. For example, a `GO_VERSION` parameter becomes `arg GO_VERSION=1.24` and can be referenced in setup commands as `${GO_VERSION}`. Extension setup and startup scripts can also reference these variables.

### Sub Commands

| Sub Command      | Description                                                   |
|------------------|---------------------------------------------------------------|
| `list`           | List all templates by category                                |
| `search <term>`  | Search templates (prefix match of name, display-name and tag) |
| `on <path>`      | Generate a new project on the given location                  |
| `dryrun`         | Print what would be generated without writing files           |

> **Note:** `dryrun` is a subcommand (not a `--dryrun` flag) because it does not require a target location. In contrast, `on` requires a target path.

**Target location safety:** The `on` subcommand will only initialize a **new** project. "New" means the target folder either does not exist, or exists but does not contain a `.booth/` directory. Init will never overwrite an existing `.booth/` configuration. This prevents accidental loss of manual customizations made after a previous init.

### CLI Flags Reference

| Flag               | Description                                                                         |
|--------------------|-------------------------------------------------------------------------------------|
| `--select <names>` | Slash-separated template names to select – the name must fully match. Error if not. |
| `--variant <name>` | Set variant (codeserver, notebook, desktop-xfce, etc.)                              |
| `--port <value>`   | Set port (number, NEXT, RANDOM)                                                     |
| ...                | Other Booth single setting ...                                                      |

---


## Template Structure

### Directory Layout

```
/templates/
├── quick-mode.toml                    # Quick mode mappings (future)
├── languages/
│   ├── meta.toml                      # Category metadata
│   ├── python/                        # template -- the name of the dir become the name of the template
│   │   ├── spec.toml                  # Template spec
│   │   ├── Boothfile                  # Boothfile
│   │   └── startup.sh                 # Startup file.   -- only one and can be any where
│   ├── go/
│   │   ├── spec.toml
│   │   ├── Boothfile                  # Boothfile
│   │   ├── startup--30.sh             # Startup file segment with order 30
│   │   ├── startup--60.sh             # Startup file segment with order 60
│   │   ├── spec.toml
│   │   ├── proxy/                     # Extension
│   │   │   └── spec.toml
│   │   └── linter/
│   │       └── spec.toml
│   └── nodejs/
│       └── spec.toml
├── frameworks/
│   ├── meta.toml
│   ├── django/
│   │   ├── Boothfile                  # Boothfile
│   │   ├── spec.toml
│   │   ├── setups/
│   │   │   └── django--setup.sh       # Additional setup
│   └── fastapi/
│       └── spec.toml
└── tools/
    ├── meta.toml
    ├── claude-code/
│   │   ├── Boothfile--30              # Boothfile segment with order 30
│   │   ├── Boothfile--80              # Boothfile segment with order 80
    │   ├── credential/
    │   │   └── spec.toml
    │   └── spec.toml
    └── neovim/
        ├── home/
        │   └── .nvim.lua              # File in home (similar with home-seed)
        └── spec.toml
```

<category>  >  <template>  > <extension>

**Template naming:** The template name is the folder name, and it serves as the **unique identifier** across all categories. Categories are for organizational purposes only. This means `languages/go` and `tools/go` cannot both exist — use distinct, descriptive names (e.g., `go` and `go-tools`). Long, descriptive names are preferred over short ambiguous ones. Symlinks should not be used inside template directories.

For each template or extension:
  > spec.toml
      -> metadata
      -> config.toml items
  > Boothfile segment files
  > Startup.sh segment files
  > Other files

### Category meta.toml

```toml
display-name = "Languages"
order = 1
```

Categories are displayed in `order` sequence. Keyboard shortcuts (^1, ^2, etc.) assigned by order.

### Template spec.toml

```toml
display-name = "Go"
display-disc = "GoLang ToolChain"
display-order = 30                      # Display order within category
tags = ["golang", "backend", "compiled"]

# ** extension only
# auto-select = true    means when the parent is selected the extension is automatically selected
# auto-select = false   means when the parent is selected the extension is not selected
# In Quick mode, auto-select also applies. In Advanced mode, users can deselect auto-selected extensions.
auto-select = true


# Setting value - required -- ERROR if not match 
dind = true
build-args = [
]
run-args = [
  "-e", "GOPROXY=https://proxy.golang.org,direct",
  "-v", "/mnt/data:/data"
]

# Dependencies - required-selected when this template is selected (may ask user to confirm)
# Note: Dependencies can create cycles or explosion — this must be validated at template publication time.
requires = []    # e.g., ["languages/java"] for Spring -- Use to send out error if the requires is not included.

# Parameter of the template
# Note: Param variable names can collide across templates. Use explicit, prefixed names
# (e.g., GO_VERSION, PYTHON_VERSION) to avoid conflicts.

params.GO_VERSION.default = "2.24"
params.GO_VERSION.suggests = ["2.21", "2.22", "2.23", "2.24", "2.25"]

params.GO_WHATEVER.default = "thing"
```

### Template Extensions

Extensions are subfolders with their own `spec.toml`. They are:
- Dependent on the parent
- Got the same parameters as parent
- Displayed as sub-items (e.g., `2-1`, `2-2`) when parent is selected
- Independent selection (selecting parent doesn't auto-select children)

---

## File Generation

### Merge Resolution

When multiple templates are selected, their outputs are merged according to three resolution strategies:

1. **Concatenation** (Boothfile, startup.sh) — Segments are concatenated together using ordering, with ties broken by template name alphabetically.
2. **Match-or-error** (config.toml scalar values like `variant`, `port`, `dind`) — If multiple templates define the same setting, the values must match or init produces an error. Use these settings sparingly in templates.
3. **Combine-and-dedup** (array values like `run-args`, `build-args`) — Arrays are combined from all templates and deduplicated. Special care is taken for `-e` and `-v` flags that have associated values.

### Output Structure

```
.booth/
├── config.toml       # Variant, port, timezone, dind, run-args
├── Dockerfile        # Header + setups ordered by setup.order
├── startup.sh        # Startup scripts ordered by order (if any)by order (if any)
├── setups/           # Setup files
├── home/             # Files with target="home"
└── home-seed/        # Files with target="home-seed"
```

### config.toml Generation

```toml
# Each of these much match when multiple templates -- so use sparingly
variant = "codeserver"
port = "NEXT"
timezone = "America/Toronto"
dind = true
cmds = [ "start-notebook" ]

# Combine from multiple template
run-args = [
    # Aggregated from all selected templates
    "-e", "GOPROXY=https://proxy.golang.org,direct",
    "-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro"
]
```

### Dockerfile Generation

Combined from Dockerfile of each template in alphabetical order of the template name
OR `Dockerfile--<order>` order by `order` and tibreak by template name.

```dockerfile
# syntax=codingbooth/boothfile:1
setup python  3.12
setup go      1.24
setup jdk     21 temurin
setup mvn     3.9.6
setup go-code-extension 
```

### startup.sh Generation (if any startup-scripts)

Combined from startup.sh of each template in alphabetical order of the template name
OR `startup--<order>` order by `order` and tibreak by template name.

```bash
#!/bin/bash
# Auto-generated by init

... content combine from place follow the rule.
```

---

## Implementation Approach

### Execution Model

The `./booth init` command runs **on the host** via the `codingbooth` binary:

```
./booth init --select go
    │
    └─► codingbooth init --select go
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

**Cache Central location:** Separated by the version
```
~/.cache/codingbooth/
└── <version>/
    ├── templates.zip      # chmod 400
    └── templates.zip.sha256
```

**Zip security:** Even though the zip is downloaded from the official CodingBooth GitHub release, it is still validated during extraction to ensure it does not contain `../` path entries or symbolic links (Zip Slip protection). This defense-in-depth approach protects against compromised releases or supply-chain attacks.

**Cache Local location:**
./.booth/templates folder on the pwd path.
The template of the same name found in the local location will be used over the one in the central location. Local templates are the user's own responsibility — the user defines them and bears the consequences. Booth does not validate trust boundaries for local overrides since the user has full control over their own local files.

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
- **Version aligned** — template version matches `codingbooth` binary version

### Language: Go

The init logic is part of the `codingbooth` binary, so it must be implemented in Go.

### File Locations

| File            | Location                                       |
|-----------------|------------------------------------------------|
| Init logic      | `coding-booth` binary (on host)                |
| Template cache  | `~/.cache/codingbooth/<version>/templates.zip` |
| Temp extraction | `/tmp/cb-init-<random>/`                       |
| Output          | `./.booth/`                                    |

**Development override:** Use `--templates-path` to load templates from a local directory (skips download/extraction).

### Package Structure

The init feature lives under `pkg/boothinit/` (not `pkg/init/` to avoid collision with Go's `init` keyword and the existing `booth/init` package which handles app context initialization).

```
cmd/
└── codingbooth/
    ├── main.go
    └── init.go

pkg/
└── boothinit/
    ├── output/                    # Phase 1 — Output model and serialization
    │   ├── model.go               # BoothOutput, ConfigToml, BoothfileContent, StartupContent, FileContent
    │   ├── config.go              # config.toml serialization (SerializeConfigToml)
    │   ├── boothfile.go           # Boothfile generation (SerializeBoothfile)
    │   ├── startup.go             # startup.sh generation (SerializeStartup)
    │   ├── files.go               # File copy logic (CopyFiles)
    │   └── writer.go              # Orchestrator (WriteOutput) — writes all files to .booth/
    ├── cache/
    │   ├── download.go            # Download templates.zip from GitHub
    │   ├── verify.go              # SHA256 verification
    │   └── extract.go             # Extract to temp dir
    ├── template/
    │   ├── model.go               # Template data structures
    │   ├── loader.go              # TOML parsing and registry
    │   └── resolve.go             # Template → Output conversion
    ├── cli/
    │   ├── list.go                # list command
    │   ├── search.go              # search command
    │   └── select.go              # select --non-interactive command
    ├── quick/
    │   └── quick.go               # Quick mode UI  (future)
    └── tui/
        └── app.go                 # Advanced mode TUI (using bubbletea)  (future)
```

#### Output Model Design Notes (Phase 1)

The output data model uses a flat `BoothOutput` struct that holds all generated content:

- **`ConfigToml`** — Scalar fields (`Variant`, `Port`, `Timezone`, `Dind`) and array fields (`Cmds`, `RunArgs`, `BuildArgs`). Only non-empty/non-zero fields are serialized to TOML. `Dind=false` is omitted.
- **`BoothfileContent`** — Pre-merged content string. The serializer prepends the `# syntax=codingbooth/boothfile:1` header.
- **`StartupContent`** — Pre-merged content string. The serializer prepends `#!/bin/bash` and `set -e`.
- **`FileContent`** — A `SourcePath`/`RelPath` pair for file copy operations. Used for `Setups`, `Home`, and `HomeSeed` slices.

`WriteOutput` enforces that `.booth/` must not already exist (safety check per the plan's "new project" constraint). Files are only written when their content is non-empty/non-nil.

---

## Implementation Phases

### Phase 1: Booth configuration ✓
Prompt: Define data model of the output (Booth configurations) and the code to serialize them
Suggest steps
- [x] Define Go structs for output:
  - `BoothOutput` (top-level container)
  - `ConfigToml` (variant, port, timezone, dind, cmds, run-args, build-args)
  - `BoothfileContent` (pre-merged content string)
  - `StartupContent` (pre-merged content string)
  - `FileContent` (source/relpath pair for setups, home, home-seed)
- [x] Implement serialization to file if exists:
  - Write `.booth/config.toml` — `SerializeConfigToml`
  - Write `.booth/Boothfile` — `SerializeBoothfile` (with syntax header)
  - Write `.booth/startup.sh` — `SerializeStartup` (with shebang + `set -e`)
  - Copy files to `.booth/setups/`, `.booth/home/`, `.booth/home-seed/` — `CopyFiles`
  - `WriteOutput` orchestrates all writes and enforces `.booth/` must not exist
- [x] Test with hardcoded data (36 unit tests covering all serializers, file copy, and writer orchestration)

### Phase 2: Template
Prompt: Define data model of the templates and the code to deserialize them
Suggest steps
- [ ] Define Go structs for templates:
  - `Category` (from meta.toml)
  - `Template` (from spec.toml)
  - `Param`
  - `BoothfileSegments`
  - `StartupSegments`
  - `SetupFile`
  - `File`
  - `RunArg`
- [ ] Create a set of templates based the model and ask to be verified manually.
- [ ] Include ./templates/ for the local template location (priority)
- [ ] Test with local defined template (define a few for testing)

### Phase 3: Selection
Prompt: Define data model of the selection and the code construct the data from the CLI
Suggest steps
- [ ] Define selection state:
  - `SelectionState` (selected, auto-selected via dependency)
  - `ParamValues` (user-specified or default)
- [ ] Add code to parse parameters/in
- [ ] Test but hooking it to the CLI but print out the selection

### Phase 4: Template + Selection → Output Conversion
Prompt: Implement the function to create output model from template defintion and input section to the output mode. 
Suggest steps
- [ ] Implementing the logic (template_compiler.go)
- [ ] hooking it to the CLI -- Add --debug to out the selection and the final output data model as well as the ordering/tiebreaking and template override decision.

### Phase 5: Other CLI Commands
Prompt: Implement the rest of the CLI sub items
Suggest steps
- [ ] `./booth init --list`
  - List all templates by category
  - Show: name, display-name, tags
- [ ] `./booth init --search "term"`
  - Prefix match on name, display-name, tags
  - Show matching templates
- [ ] Common flags:
  - `--dryrun` — print what would be generated
- [ ] The logic to load the template (by version) and save to a central location

### Phase 6: Template Cache & Download
Prompt: Implement the publication, download and cache. Ensure zip does not contain ../ entry OR symbolic link
Suggest steps
- [ ] Implement template publication in the GitHub workflow
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

### Phase 7: Quick Mode UI
Prompt: Future -- Don't implement
- [ ] Simple numbered menu for project type
- [ ] Simple numbered menu for variant
- [ ] Confirmation prompt
- [ ] Map quick selections to template names (hardcoded or quick-mode.toml)
- [ ] Generate files using same backend

### Phase 8: Advanced Mode TUI
Prompt: Future -- Don't implement
- [ ] TUI framework setup
- [ ] Category tabs navigation
- [ ] Item list with selection toggle (`[ ]`, `[#]`, `[*]`)
- [ ] Sub-item display and toggle
- [ ] Params editing (choice dropdown, text input)
- [ ] Seetting screen (^S) for variant, port, timezone, dind
- [ ] Find screen (^F) with prefix matching
- [ ] Review and generate (^D)

---


# Appendix
- We will need a program to validate the template and run with GitHub action to release. So that we avoid problems like typos, circular dependencies, or missing dependencies.
- As opinion present, we need to have logging printed out when --verbose.
- The run-args `-v` and `-e` should be deduplicated. Note that deduplication for these flags is non-trivial since they carry associated values (e.g., `-e KEY=VAL`, `-v src:dst`). Care must be taken to handle these correctly.
- Tie breaker for same ordering is alphabetical order of the name.
- Ordering rules for segments require a strict parser with validation.
- `--select`, stdin, `@file`, and `@@url` input should all share one normalization pipeline for consistent parsing.

---

> For future Quick Mode and Advanced Mode TUI designs, see [BoothInit-FutureUI.md](BoothInit-FutureUI.md).
