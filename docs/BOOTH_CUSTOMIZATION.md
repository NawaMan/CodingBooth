# Booth Customization Guide

This guide covers how to customize a CodingBooth environment — from built-in setup scripts to creating your own templates and sharing them as recipes. If you just want to run a booth, see the [CLI Usage](../README.md#cli-usage) section of the README.

---

## Table of Contents

- [Setups](#setups)
  - [What is a Setup?](#what-is-a-setup)
  - [Using Built-in Setups](#using-built-in-setups)
  - [The Three Artifacts](#the-three-artifacts)
  - [Profile Ordering](#profile-ordering)
  - [Creating a Custom Setup](#creating-a-custom-setup)
  - [Constraints and Best Practices](#constraints-and-best-practices)
- [Installs](#installs)
  - [What is an Install?](#what-is-an-install)
  - [Using Built-in Installs](#using-built-in-installs)
  - [Creating a Custom Install](#creating-a-custom-install)
- [Templates](#templates)
  - [What is a Template?](#what-is-a-template)
  - [Template Structure](#template-structure)
  - [Writing a Template](#writing-a-template)
  - [Parameters](#parameters)
  - [Segments and Ordering](#segments-and-ordering)
  - [Config Values](#config-values)
  - [Files](#files)
- [Template Extensions](#template-extensions)
  - [What is an Extension?](#what-is-an-extension)
  - [Writing an Extension](#writing-an-extension)
  - [Auto-Select vs Explicit](#auto-select-vs-explicit)
  - [Dependencies Across Templates](#dependencies-across-templates)
- [Recipes](#recipes)
  - [What is a Recipe?](#what-is-a-recipe)
  - [Recipe Syntax](#recipe-syntax)
  - [Using Recipes](#using-recipes)
  - [Creating and Sharing Recipes](#creating-and-sharing-recipes)

---

## Setups

### What is a Setup?

A **setup script** installs a language, tool, or platform into a CodingBooth image. It runs once during the Docker build (as root) and produces up to three artifacts that configure the runtime environment for the `coder` user.

**Why setups instead of raw Dockerfile commands?**

Installing a language like Python or Go inside a container involves more than `apt-get install`. You need to set `PATH`, configure environment variables for every shell session, create user-specific directories on container start, and sometimes wrap the binary with pre/post logic. A setup script bundles all of this into a single, tested, reusable command.

### Using Built-in Setups

CodingBooth ships with setup scripts for common languages and tools. Use them in your Boothfile with the `setup` command:

```text
# .booth/Boothfile
# syntax=codingbooth/boothfile:1

setup python 3.13
setup go 1.25
setup nodejs 20
setup jdk 21 temurin
setup neovim
setup claude-code
```

Or in a Dockerfile:

```dockerfile
FROM nawaman/codingbooth:base-latest
SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root
WORKDIR /opt/codingbooth/setups

RUN python--setup.sh 3.13
RUN go--setup.sh 1.25
RUN nodejs--setup.sh 20
RUN jdk--setup.sh 21 temurin
```

To see all available setup scripts, run inside a container:

```bash
ls /opt/codingbooth/setups/
```

**Argument styles vary by script.** Some accept bare positional versions, others require flags:

```text
# Positional (simple $1 capture):
setup python 3.13
setup go 1.25
setup nodejs 20
setup jdk 21 temurin
setup ruby 3.3
setup bun 1.2
setup neovim 0.11

# Flag-based (--version or similar):
setup kotlin --version 2.0.20
setup scala --scala-version 3.6.4
setup lua --lua-version 5.4
setup php --version 8.4
setup kind --kind-version 0.29.0
```

Check the script's header or usage message if unsure.

### The Three Artifacts

A setup script creates up to three files that integrate the tool into the container lifecycle:

#### 1. Startup Script

**Path:** `/usr/share/startup.d/<LEVEL>-cb-<name>--startup.sh`
**Runs:** Once per container start, as the `coder` user.
**Purpose:** One-time initialization that must happen at runtime (not build time).

Examples: creating user cache directories, generating config files if missing, first-run migrations.

```bash
#!/usr/bin/env bash
set -euo pipefail

SENTINEL="$HOME/.go-startup-done"
[[ -f "$SENTINEL" ]] && exit 0

mkdir -p "$HOME/go/bin" "$HOME/go/src" "$HOME/go/pkg"
touch "$SENTINEL"
```

Startup scripts must be **idempotent** — the container may be stopped and restarted, so the script runs again each time. Use sentinel files to guard expensive operations.

#### 2. Profile Script

**Path:** `/etc/profile.d/<LEVEL>-cb-<name>--profile.sh`
**Runs:** At the beginning of every shell session (login shells), as the `coder` user.
**Purpose:** Lightweight environment setup — PATH, exports, aliases.

```bash
# Profile: Go
case ":$PATH:" in
  *":/usr/local/go-current/bin:"*) ;;
  *) export PATH="/usr/local/go-current/bin:$PATH";;
esac
export GOPATH="$HOME/go"
```

Keep profile scripts **fast**. They run on every `bash -l` or new terminal. Avoid network calls, heavy computation, or anything that adds noticeable latency.

#### 3. Starter Wrapper

**Path:** `/usr/local/bin/<name>`
**Runs:** Every time the user invokes the command.
**Purpose:** Thin wrapper that performs pre/post logic before `exec`-ing the real binary.

```bash
#!/usr/bin/env bash
set -euo pipefail
exec /usr/local/go-current/bin/go "$@"
```

Starter wrappers are optional. Simple tools that just need to be on `PATH` don't need one — a symlink suffices.

### Profile Ordering

The `<LEVEL>` number in file names controls execution order:

| Level | Purpose | Examples |
|-------|---------|---------|
| 50-54 | Core CodingBooth base | Shell config, base utilities |
| 55-59 | OS / UI | Desktop environments, display server |
| 60-64 | Languages / platforms | Python, Java, Go, Node.js, Rust |
| 65-69 | Language extensions | venv managers, JDK tools, linters |
| 70-74 | Developer tools | IDEs, editors, notebook servers |
| 75-79 | Tool extensions | Plugins, kernels, IDE extensions |

Lower levels run first. A language setup at level 60 finishes before a tool that depends on it at level 70.

### Creating a Custom Setup

Place your script in `.booth/setups/` and reference it in your Boothfile:

```
my-project/
└── .booth/
    ├── Boothfile
    └── setups/
        └── myapp--setup.sh
```

```text
# .booth/Boothfile
# syntax=codingbooth/boothfile:1

setup python 3.13
setup myapp           # Runs .booth/setups/myapp--setup.sh
```

The Boothfile compiler automatically adds a `COPY` directive to bring your script into the image before it's executed.

**Template for custom setups:**

CodingBooth provides a template at `/opt/codingbooth/setups/template-seup.sh` inside any container. The template includes:
- Root privilege check
- `envsubst` for variable substitution into generated files
- Scaffolding for all three artifacts (startup, profile, starter)
- Warnings about performance implications

Copy it and replace `XXXXXX` with your component name and adjust `LEVEL` to the appropriate range.

### Constraints and Best Practices

- **Setup scripts run as root** during `docker build`. They install packages, create system directories, and write to `/etc/` and `/usr/`.
- **Startup and profile scripts run as the `coder` user.** They cannot write to system directories without `sudo`.
- **Startup scripts must be idempotent.** Use sentinel files for expensive operations.
- **Profile scripts must be lightweight.** No network calls, no heavy I/O.
- **Use `envsubst`** to stamp version variables into generated files.
- **File permissions:** startup and starter wrappers get `chmod 755`; profile scripts get `chmod 644`.
- **Use the `CB_*` prefix** for CodingBooth-specific environment variables (e.g., `CB_PYTHON_HOME`).

---

## Installs

### What is an Install?

An **install script** installs packages or libraries for a specific ecosystem. It's the counterpart to a setup script: while setup installs the *platform* (e.g., Python), install adds *packages* to it (e.g., Django, httpx).

**Why separate install scripts?**

Install scripts handle ecosystem-specific concerns — running `pip` as the right user, using the correct `GOPATH`, installing npm packages globally vs locally. They also integrate with the Boothfile `install` command for a clean, readable syntax.

### Using Built-in Installs

Use the `install` command in your Boothfile:

```text
# .booth/Boothfile
# syntax=codingbooth/boothfile:1

setup python 3.13
install pip django httpx                  # pip install django httpx

setup go 1.25
install go golang.org/x/tools/gopls@latest  # go install ...

setup nodejs 20
install npm express typescript            # npm install -g ...

setup rust
install cargo ripgrep fd-find             # cargo install ...
```

Each `install` command maps to a `*--install.sh` script. For example, `install pip django` compiles to `RUN pip--install.sh django`.

**Available install scripts:**

| Command | Ecosystem | What it does |
|---------|-----------|-------------|
| `install pip` | Python | `pip install` into the active venv |
| `install uv` | Python | `uv pip install` (faster alternative) |
| `install conda` | Python | `conda install` |
| `install npm` | Node.js | `npm install -g` |
| `install yarn` | Node.js | `yarn global add` |
| `install bun` | Bun | `bun install -g` |
| `install deno` | Deno | `deno install` |
| `install go` | Go | `go install` (as coder user) |
| `install cargo` | Rust | `cargo install` (as coder user) |
| `install gem` | Ruby | `gem install` |
| `install brew` | Homebrew | `brew install` |
| `install cabal` | Haskell | `cabal install` |
| `install hex` | Elixir | `mix archive.install hex` |
| `install luarocks` | Lua | `luarocks install` |
| `install pecl` | PHP | `pecl install` |
| `install conan` | C/C++ | `conan install` |

### Creating a Custom Install

Place your script in `.booth/setups/` following the naming convention `<name>--install.sh`:

```bash
#!/usr/bin/env bash
# .booth/setups/mypackages--install.sh
set -euo pipefail

for pkg in "$@"; do
    echo "Installing: $pkg"
    # Your package manager logic here
done
```

Then use it in your Boothfile:

```text
install mypackages some-package another-package
```

Install scripts should:
- Accept package names as positional arguments (`$@`).
- Run the package manager as the `coder` user when needed (using `sudo -u coder bash -lc "..."`).
- Verify the prerequisite tool is installed before proceeding.
- Exit non-zero on failure.

---

## Templates

### What is a Template?

A **template** is a reusable, composable unit of CodingBooth configuration. When you run `./booth init new ../project --select go/python`, the `go` and `python` templates are merged to produce a complete `.booth/` folder — Boothfile, config.toml, startup scripts, and any supporting files.

**Why templates?**

Writing `.booth/` configuration by hand is manageable for simple projects. But for a polyglot project with multiple languages, AI tools, credential seeding, IDE extensions, and databases, you'd need to know the correct setup script arguments, segment ordering, volume mount syntax, and various other details. Templates encode all of this, and the init compiler handles the merge logic.

### Template Structure

Templates live under `templates/` organized by category:

```
templates/
├── languages/                  # Category directory
│   ├── meta.toml               # Category metadata
│   └── go/                     # Template directory (name = "go")
│       ├── template.toml       # Template definition
│       ├── linter--extension.toml
│       └── vscode-ext--extension.toml
├── tools/
│   ├── meta.toml
│   └── claude-code/
│       ├── template.toml
│       └── accept-edits--extension.toml
└── ...
```

**Category `meta.toml`:**

```toml
display-name = "Languages"
order = 1
```

Categories are displayed in `order` sequence. They exist for organizational purposes — template names are globally unique across all categories.

### Writing a Template

A `template.toml` file defines everything about a template:

```toml
# Metadata
display-name = "Go"
display-disc = "Go language toolchain"
display-order = 10
primary = true
tags = ["go", "golang", "backend"]

# Parameters
[params.GO_VERSION]
default = "1.25.7"
suggests = ["1.25.7", "1.24.13", "1.23.12"]

# Boothfile content
[segments]
Boothfile = """
setup go ${GO_VERSION}
install go golang.org/x/tools/gopls@latest
install go github.com/go-delve/delve/cmd/dlv@latest
"""
```

When this template is selected with `--select go`, it generates:

```text
# .booth/Boothfile
# syntax=codingbooth/boothfile:1
# Generated by booth init

arg GO_VERSION=1.25.7

setup go ${GO_VERSION}
install go golang.org/x/tools/gopls@latest
install go github.com/go-delve/delve/cmd/dlv@latest
```

**Required fields:** `display-name`, plus at least one segment or config value.
**Optional fields:** `display-disc`, `display-order`, `primary`, `tags`, `requires`, `dind`, `run-args`, `build-args`, `params`, `segments`, `files`.

### Parameters

Parameters let users customize template behavior. They become `arg` directives in the generated Boothfile and can be overridden at build time.

```toml
[params.JDK_VERSION]
default = "25"
suggests = ["25", "21", "17", "11", "8"]

[params.JDK_VENDOR]
default = "temurin"
suggests = ["temurin", "corretto", "openjdk"]
```

**Positional mapping:** When users specify params via the DSL (`java:21,corretto`), they are mapped to named params in TOML declaration order. So `21` maps to `JDK_VERSION` and `corretto` maps to `JDK_VENDOR`.

**Default values:** Unspecified params use their `default` value.

### Segments and Ordering

Segments define the Boothfile and startup.sh content that a template contributes. When multiple templates are selected, all segments are merged globally and sorted by order number.

**Segment keys and their order:**

| Key                | Order | Purpose                                                    |
|--------------------|-------|------------------------------------------------------------|
| `"Boothfile--40"`  | 40    | Infrastructure (desktop environments)                      |
| `Boothfile`        | 50    | Base setups (languages, standalone tools) — default        |
| `"Boothfile--60"`  | 60    | Dependent setups (codeserver, notebook, Kotlin needs Java) |
| `"Boothfile--65"`  | 65    | Language VS Code extensions (need codeserver/vscode)       |
| `"Boothfile--70"`  | 70    | Notebook kernels (need notebook/Jupyter)                   |
| `"Boothfile--90"`  | 90    | Post-setup steps (install from requirements.txt)           |

Startup segments follow the same pattern: `"startup.sh"` (order 50), `"startup--90.sh"` (order 90), etc.

**Tiebreaking:** Same-order segments are sorted alphabetically by source template name. For example, at order 50, `go` segments appear before `python` segments.

**Example — why ordering matters:**

```toml
# kotlin/template.toml — Kotlin depends on Java (JDK must be set up first)
[segments]
"Boothfile--60" = """
setup kotlin --version ${KOTLIN_VERSION}
"""
```

If both `java` and `kotlin` are selected, Java's order-50 segment runs first, ensuring `JAVA_HOME` is available when Kotlin's order-60 segment executes.

### Config Values

Templates can contribute to the generated `config.toml`:

```toml
# Scalar values — match-or-error if multiple templates set these
dind = true

# Array values — combined and deduplicated across all templates
run-args = [
    "-v", "booth-pgdata:/var/lib/postgresql",
    "-e", "PGDATA=/var/lib/postgresql/data",
]
build-args = [
    "--build-arg", "EXTRA=true",
]
```

**Scalar merge:** If two templates both set `dind`, the values must match or init fails with a clear error. Use scalar config values sparingly.

**Array merge:** Arrays from all templates are combined. Duplicate entries are removed, with awareness of paired flags (`-v`, `-e`, `-p`, `-l` and their values are treated as two-token units).

### Files

Templates can contribute files to the generated `.booth/` directory:

```toml
# Inline file content
[files.home-seed]
".claude/settings.json" = """
{
    "permissions": {
        "allow": ["Bash", "Edit", "Write"]
    }
}
"""

[files.home]
".gitconfig" = """
[core]
    editor = nvim
"""
```

Files can target three locations:
- **`files.setups`** — Copied to `.booth/setups/`
- **`files.home`** — Copied to `.booth/home/` (overrides existing files at container start)
- **`files.home-seed`** — Copied to `.booth/home-seed/` (won't overwrite existing files)

Templates can also include file-based content by placing files in `setups/`, `home/`, or `home-seed/` subdirectories alongside `template.toml`.

---

## Template Extensions

### What is an Extension?

An **extension** is a sub-template that adds optional functionality to a parent template. Extensions live alongside their parent and cannot exist independently.

Examples:
- `go` + `linter` — adds golangci-lint
- `go` + `vscode-ext` — adds Go VS Code extension
- `python` + `uv` — adds the uv package manager
- `java` + `maven` — adds Apache Maven
- `claude-code` + `accept-edits` — auto-accepts file operations

### Writing an Extension

Extension files use the naming convention `<name>--extension.toml` and live in the parent template's directory:

```toml
# languages/go/linter--extension.toml
display-name = "Go Linter"
display-disc = "golangci-lint for Go"
display-order = 1
auto-select = false
tags = ["go", "lint", "quality"]

[segments]
Boothfile = """
install go github.com/golangci/golangci-lint/cmd/golangci-lint@latest
"""
```

Extensions can have their own parameters:

```toml
# languages/java/maven--extension.toml
display-name = "Maven"
display-disc = "Apache Maven build tool"
display-order = 10
auto-select = false
tags = ["build", "maven"]

[params.MAVEN_VERSION]
default = "3.9.12"
suggests = ["3.9.12", "4.0.0-rc-5"]

[segments]
Boothfile = """
setup mvn ${MAVEN_VERSION}
"""
```

Extensions can also define multi-order segments:

```toml
# languages/python/uv--extension.toml
display-name = "uv"
display-disc = "Fast Python package manager"
auto-select = false

[segments]
Boothfile = """
# uv is already installed by python setup.
"""
"Boothfile--90" = """
run --mount=type=bind,target=/tmp/ctx if [ -f /tmp/ctx/.booth/requirements.txt ]; then uv pip install -r /tmp/ctx/.booth/requirements.txt; fi
"""
```

And contribute files:

```toml
# ai-tools/claude-code/accept-edits--extension.toml
display-name = "Accept Edits"
auto-select = false

[files.home-seed]
".claude/settings.json" = """
{
    "permissions": {
        "allow": ["Bash", "Edit", "Write", "NotebookEdit"],
        "deny": ["Bash(git push --force*)"]
    }
}
"""
```

### Auto-Select vs Explicit

Extensions have an `auto-select` flag that controls whether they are included automatically when the parent is selected:

```toml
# Auto-selected: included unless explicitly deselected
auto-select = true    # e.g., vscode-ext for Go — most users want this

# Explicit: only included when named
auto-select = false   # e.g., linter for Go — opt-in
```

In the selection DSL:
- `go` — selects Go and all `auto-select = true` extensions (like `vscode-ext`).
- `go+linter` — selects Go, auto-selected extensions, plus the `linter` extension.

### Dependencies Across Templates

Extensions can declare dependencies on other templates using `requires`:

```toml
# languages/python/kernel--extension.toml
display-name = "Python Notebook Kernel"
requires = ["notebook"]           # Must also select the notebook template

[segments]
"Boothfile--60" = """
setup python-kernel
"""
```

If a user selects `python+kernel` without also selecting `notebook`, init produces an error:

```
Error: extension "kernel" of template "python" requires template "notebook" to be selected
```

---

## Recipes

### What is a Recipe?

A **recipe** is a file that captures a template selection for reuse. Instead of typing a long `--select` string every time, you save your selection to a `.recipe` file and reference it with `@filename`.

**Why recipes?**

- **Shareable** — commit a recipe file to your repo so teammates can init the same way.
- **Readable** — multiline format with one template per line is easier to read than a dense DSL string.
- **Composable** — recipes are just text files that feed into the same parser.

### Recipe Syntax

A recipe file uses the same DSL as `--select`, but with a more readable multiline format:

```text
# cool-project.recipe
go
python:3.13
  + uv
  + vscode-ext
java:25,temurin
  + maven
claude-code
```

**Syntax rules:**
- One template per line.
- Parameters after `:` (comma-separated, positional): `python:3.13` or `java:25,temurin`.
- Extensions with `+` on the same line: `go+linter+vscode-ext`.
- Extensions on continuation lines (indented, starting with `+`): `  + maven`.
- Blank lines and leading/trailing whitespace are ignored.
- Spaces around `+` are stripped.

The parser normalizes this multiline format into the standard DSL before parsing. Continuation lines (starting with `+`) are joined to the previous template.

### Using Recipes

```bash
# Use a recipe file
./booth init new ../my-project --select @cool-project.recipe

# Preview what a recipe would generate
./booth init dryrun --select @cool-project.recipe

# Pipe a recipe via stdin
cat cool-project.recipe | ./booth init new ../my-project --select -

# Inline heredoc
./booth init new ../my-project --select - <<RECIPE
go
python:3.13
  + uv
claude-code
RECIPE
```

### Creating and Sharing Recipes

Create a `.recipe` file in your project or examples directory:

```text
# fullstack.recipe — Full-stack web development environment
python:3.13
  + uv
  + vscode-ext
nodejs:22
  + vscode-ext
postgresql
claude-code
  + accept-edits
```

Share it by:
- Committing it to your repository.
- Hosting it at a URL and using `@@url`: `./booth init new ../project --select @@https://example.com/fullstack.recipe`.
- Including it in the `examples/recipes/` directory for team reference.

**Tips for good recipes:**
- Use explicit versions for reproducibility (`python:3.13` not just `python`).
- Include only what the project needs — templates are composable, not cumulative.
- Name the file descriptively: `data-science.recipe`, `go-microservice.recipe`.
- Add context in the filename or a companion README — recipe files don't support comments.
