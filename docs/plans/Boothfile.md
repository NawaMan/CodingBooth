# Boothfile (Draft Plan)

> **Status:** Draft / Design Proposal
>
> This document describes the design and intent of **Boothfile**, a simplified, declarative configuration format for CodingBooth. It will be refined over time.

---

## 1. Motivation

CodingBooth currently uses a Dockerfile-based customization model. While powerful, this exposes users to:

- Boilerplate Dockerfile headers that must remain fixed (`ARG`, `FROM`, `SHELL`, `WORKDIR`, etc.)
- Repetitive `RUN <setup-script>` patterns
- Conditional logic that clutters Dockerfiles
- Cognitive overhead for users who only want to *declare intent*

**Boothfile** aims to:

- Hide required Dockerfile boilerplate
- Provide a concise, readable, intent-based syntax
- Compile deterministically into a standard Dockerfile
- Preserve all guarantees of CodingBooth (reproducibility, transparency, disposability)
- **Decouple user intent from container runtime** — if CodingBooth ever migrates to Podman, Buildah, or other OCI-compatible tooling, Boothfiles remain unchanged while the compiler targets a different backend

Boothfile is **not** a replacement for Dockerfile power. It is a *higher-level authoring format* that generates Dockerfiles (or potentially other build specifications in the future).

### 1.1 Relationship to BoothInit

Boothfile is designed to be the output target for `booth init`. Once Boothfile is implemented:

- `booth init` generates a **Boothfile** (not a raw Dockerfile)
- Users can read, understand, and edit the generated Boothfile easily
- The Boothfile compiles into a Dockerfile at build time

This creates a clean pipeline:

```
Templates → BoothInit → Boothfile → Dockerfile → Docker image
```

Each layer has one job. Templates describe available tools. BoothInit selects and configures them. Boothfile is the human-readable, editable configuration. The Dockerfile is the generated build artifact.

### 1.2 Scope

Boothfile covers **Dockerfile generation only**. It does not manage:

- `config.toml` (variant, port, run-args for `docker run`)
- `startup.sh`
- `home/` or `home-seed/` files

Those responsibilities belong to `booth init` and the existing `.booth/` configuration model.

Notably, **variant and version are not Boothfile concerns**. They are determined by `config.toml` and/or CLI flags (`--variant`, `--version`), and injected into the Dockerfile prologue at build time via build arguments. Boothfile focuses purely on *what to install inside the image*.

---

## 2. Design Principles

### 2.1 Concise over ceremonial

Users write *what they want* without boilerplate, but **order still matters**.

```text
# syntax=codingbooth/boothfile:1

setup python 3.13
install pip django
```

not:

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN python--setup.sh 3.13
RUN pip--install.sh django
```

Boothfile is **not declarative** — it is an ordered, imperative sequence. The order of commands matters because each line may depend on what came before it:

```text
# Correct: install Python first, then use its pip
setup python 3.13
install pip django

# Wrong: pip will fail because Python isn't installed yet
install pip django
setup python 3.13
```

What Boothfile eliminates is *ceremony*, not *sequencing*. Users still think about dependency order — they just don't have to write ARG/FROM/SHELL/WORKDIR boilerplate to do it.

### 2.2 Generated, not interpreted

- Boothfile is compiled into a Dockerfile
- The Dockerfile remains the source of truth for Docker
- No hidden runtime mutations

Users must always be able to inspect the generated Dockerfile via `--emit-dockerfile`.

### 2.3 Order-preserving

Boothfile commands are emitted to the Dockerfile in the **exact order they appear**.

This is critical because:
- Docker layer caching depends on command order
- Dependencies must be installed before dependents
- Users can reason about build behavior by reading top-to-bottom

### 2.4 All lowercase

Boothfile commands are all lowercase. Dockerfile directives become their lowercase equivalents, and Boothfile-specific commands (`setup`, `install`) use the same style:

```text
run apt-get update
env MY_VAR=value
setup python 3.12
install pip django
copy ./config /opt/config
```

No uppercase, no mixed case, no prefixes. Just simple commands.

---

## 3. Phased Implementation

Boothfile will be implemented incrementally, allowing users to adopt it immediately while features are added over time.

### Phase 1: Header Generation + Basic Commands

**Goal:** Eliminate boilerplate. Users write commands without the header ceremony.

What works:
- `# syntax=codingbooth/boothfile:1` header
- `run` — shell commands
- `copy` — file copying
- `env` — environment variables
- `workdir` — working directory
- `expose` — port declaration
- `label` — metadata
- `arg` — build arguments
- Comments
- Blank lines

Example Boothfile (Phase 1):
```text
# syntax=codingbooth/boothfile:1

# Install graphviz
run apt-get update && apt-get install -y graphviz

# Setup Python and install Django
run python--setup.sh
run pip--install.sh django
```

**Value delivered:** No more copy-pasting ARG/FROM boilerplate. Immediate usability.

### Phase 2: Setup Convenience with Parameters

**Goal:** Simplify setup script invocation, including parameterized setups.

New command:
- `setup <n>` → `RUN <n>--setup.sh`
- `setup <n> <args...>` → `RUN <n>--setup.sh <args...>`

Example Boothfile (Phase 2):
```text
# syntax=codingbooth/boothfile:1

# Install graphviz
run apt-get update && apt-get install -y graphviz

# Languages and tools
setup python
setup jdk 21 temurin
run pip--install.sh django
```

Compiles to:

```dockerfile
...
RUN apt-get update && apt-get install -y graphviz
RUN python--setup.sh
RUN jdk--setup.sh 21 temurin
RUN pip--install.sh django
```

Parameters are positional and passed through directly to the setup script in the order they appear.

### Phase 3: Package Manager Convenience

**Goal:** Simplify common package installation patterns.

New command:
- `install pip <packages...>` → `RUN pip--install.sh <packages...>`
- `install npm <packages...>` → `RUN npm--install.sh <packages...>`
- `install brew <packages...>` → `RUN brew--install.sh <packages...>`

Example Boothfile (Phase 3):
```text
# syntax=codingbooth/boothfile:1

run apt-get update && apt-get install -y graphviz

setup python 3.12
setup jdk 21 temurin
install pip django djangorestframework

setup mvn 3.9.6

copy ./config /opt/config
```

### Future Phases

- BuildKit frontend image (see Section 5.2)
- Setup script validation with suggestions
- Editor tooling / syntax highlighting
- Alternative compilation targets (Podman, Buildah)

Note: Additional package managers (`gem`, `cargo`, `conda`, `yarn`, etc.) already work via the generic `install` command — any `install <tool> <packages>` generates `RUN <tool>--install.sh <packages>`.

---

## 4. Relationship to Dockerfile

Boothfile:
- Is optional
- Compiles into a Dockerfile
- Can coexist with a manually written Dockerfile

Using a Dockerfile directly with `booth` (via `--dockerfile`) continues to work as before. Boothfile does not replace this path — it adds a higher-level alternative.

### 4.1 File Selection Precedence

| Scenario                                        | Behavior                                                                                                        |
|-------------------------------------------------|-----------------------------------------------------------------------------------------------------------------|
| No flags given                                  | Look for `.booth/Boothfile` first, then `.booth/Dockerfile`. Use whichever is found. Error if neither exists.   |
| `--dockerfile <path>`                           | Use the specified Dockerfile directly. Error if it does not exist.                                              |
| `--boothfile <path>`                            | Use the specified Boothfile (compile to Dockerfile). Error if it does not exist.                                |
| `--boothfile <path>` and `--dockerfile <path>`  | Use the Boothfile. Emit a **warning** that both were given and Boothfile takes precedence.                      |

### 4.2 The `--emit-dockerfile` Flag

The `--emit-dockerfile` flag outputs the generated Dockerfile to stdout (or a specified path) without proceeding to build. This is essential for:

- **Testing:** Verify the compiler produces correct output during development
- **Debugging:** Users can inspect exactly what Docker will see
- **CI/CD:** Pipelines can generate and cache Dockerfiles
- **Migration:** Users evaluating Boothfile can compare output against their existing Dockerfile

```bash
booth build --emit-dockerfile            # Print to stdout
booth build --emit-dockerfile > out.Dockerfile  # Save to file
booth build --dryrun                     # Show what would be built without building
```

---

## 5. The `# syntax` Directive

Every Boothfile begins with:

```text
# syntax=codingbooth/boothfile:1
```

This line serves two purposes:

### 5.1 File Identification (Now)

Since `#` is a comment in Boothfile, the syntax directive is stripped during compilation like any other comment. But it immediately tells humans, editors, and tooling:

- **What this file is** — not a shell script, not a Dockerfile, but a Boothfile
- **Which syntax version** — enabling future evolution without breaking existing files
- **How to process it** — tools can detect and handle Boothfiles automatically

The `booth` compiler uses this line to validate that a file is a Boothfile. If the first non-blank line is not `# syntax=codingbooth/boothfile:1`, the compiler emits a warning (or error in `--strict` mode).

### 5.2 BuildKit Frontend (Future)

The `# syntax=` line follows the exact convention Docker uses for custom build frontends. If a `codingbooth/boothfile:1` image is published to Docker Hub containing the Boothfile compiler, then BuildKit can process Boothfiles directly:

```bash
docker build -f Boothfile .
```

Docker would see `# syntax=codingbooth/boothfile:1`, pull the frontend image, and use it to compile the Boothfile into build instructions — no `booth` CLI needed. The Boothfile *becomes* the Dockerfile.

This is a future goal, not an initial requirement. For now, the `booth` binary handles compilation. But designing with this convention from day one ensures forward compatibility.

### 5.3 Version Semantics

The `:1` tag indicates major version 1 of the Boothfile syntax. All phases (1, 2, 3) are additive and backward-compatible within version 1:

- A Phase 1 Boothfile is valid under a Phase 3 compiler
- New commands added in later phases don't break earlier files
- Breaking syntax changes would require `# syntax=codingbooth/boothfile:2`

---

## 6. Fixed Dockerfile Prologue (Hidden)

Every Boothfile compiles with a fixed prologue that is required for CodingBooth to function. The prologue is **always the same** regardless of Boothfile content:

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
```

Key points:

- The Boothfile's `# syntax=codingbooth/boothfile:1` is replaced by `# syntax=docker/dockerfile:1.7` in the generated Dockerfile
- `SHELL`, `USER root`, and `WORKDIR` are already set in the base image, so they don't need to be repeated
- `BOOTH_VARIANT_TAG` and `BOOTH_VERSION_TAG` default to `base` and `latest` but are overridden at build time by `config.toml` / CLI flags — **Boothfile never specifies these**
- These lines are generated automatically and are not user-editable in Boothfile
- The prologue may evolve over time without breaking Boothfiles

---

## 7. Boothfile Structure

Boothfile is a **line-oriented DSL** with simple, all-lowercase commands.

Example (using Phase 3 syntax):

```text
# syntax=codingbooth/boothfile:1

# Development environment for my Django project
setup python 3.12
install pip django

setup java-jjava-nb-kernel
```

A Boothfile requires the `# syntax` line. Beyond that, an empty file (or a file with only comments) is valid and produces only the prologue.

### 7.1 Minimal Boothfile

```text
# syntax=codingbooth/boothfile:1
```

This is valid. It produces only the prologue — useful as a starting point or when the base image already has everything you need.

---

## 8. Comments

Boothfile supports comments for documentation and readability.

### 8.1 Full-line comments

Lines starting with `#` are ignored (including the `# syntax` line).

```text
# This is a comment
setup python
```

### 8.2 Inline comments

Comments may appear at the end of a line after `#`.

```text
setup python       # Required for Django
install pip django # Web framework
```

### 8.3 Blank lines

Blank lines are ignored and can be used freely for readability.

### 8.4 Compilation behavior

Comments are **preserved** in the generated Dockerfile for readability. This makes it easier to understand the structure of the generated output.

The only exception is the `# syntax=codingbooth/boothfile:1` directive, which is transformed into `# syntax=docker/dockerfile:1.7` in the prologue.

---

## 9. Commands

All Boothfile commands are lowercase. They fall into two categories:

- **Direct mappings** — lowercase equivalents of Dockerfile directives (`run`, `copy`, `env`, etc.)
- **Boothfile-specific** — higher-level commands that expand into Dockerfile instructions (`setup`, `install`)

### 9.1 `run` (Phase 1+)

Runs a shell command.

**Syntax:** `run <command>`

```text
run apt-get update && apt-get install -y graphviz
```

Compiles to:

```dockerfile
RUN apt-get update && apt-get install -y graphviz
```

#### Multi-line commands

Complex commands spanning multiple lines use heredoc-style syntax with explicit mode selection:

| Syntax        | Behavior                | Use case                                            |
|---------------|-------------------------|-----------------------------------------------------|
| `run <<END`   | Verbatim Docker heredoc | Full control, multi-line scripts                    |
| `run &&<<END` | Join lines with `&&`    | Fail-fast sequences (typical apt/package installs)  |
| `run ;<<END`  | Join lines with `;`     | Commands that can fail independently                |

##### Verbatim mode (`run <<END`)

Passes content directly to Docker's native heredoc support:

```text
run <<END
set -e
apt-get update
apt-get install -y unzip curl jq
rm -rf /var/lib/apt/lists/*
END
```

Compiles to:

```dockerfile
RUN <<END
set -e
apt-get update
apt-get install -y unzip curl jq
rm -rf /var/lib/apt/lists/*
END
```

Use this when you need full control over shell behavior (e.g., `set -e`, conditionals, loops).

##### And-join mode (`run &&<<END`)

Joins lines with `&&` for fail-fast behavior:

```text
run &&<<END
apt-get update
apt-get install -y unzip curl jq
rm -rf /var/lib/apt/lists/*
END
```

Compiles to:

```dockerfile
RUN apt-get update \
    && apt-get install -y unzip curl jq \
    && rm -rf /var/lib/apt/lists/*
```

This is the most common pattern for package installation sequences.

##### Semicolon-join mode (`run ;<<END`)

Joins lines with `;` when commands can fail independently:

```text
run ;<<END
rm -f /tmp/optional-file
echo "Continuing regardless"
END
```

Compiles to:

```dockerfile
RUN rm -f /tmp/optional-file; echo "Continuing regardless"
```

##### Processing rules for `&&` and `;` modes

1. Lines ending with `\` are collapsed first (continuations preserved)
2. Blank lines are skipped
3. Comment lines (starting with `#`) are skipped
4. Remaining logical lines are joined with the chosen operator

Example with continuations:

```text
run &&<<END
apt-get update
apt-get install -y \
    unzip \
    curl \
    jq
# Clean up apt cache
rm -rf /var/lib/apt/lists/*
END
```

Compiles to:

```dockerfile
RUN apt-get update \
    && apt-get install -y unzip curl jq \
    && rm -rf /var/lib/apt/lists/*
```

##### Delimiter rules

- The delimiter word (e.g., `END`) can be any uppercase identifier
- The closing delimiter must appear alone on its own line

### 9.2 `copy` (Phase 1+)

Copies files into the image.

```text
copy ./config /opt/config
copy requirements.txt /tmp/requirements.txt
```

Compiles to:

```dockerfile
COPY ./config /opt/config
COPY requirements.txt /tmp/requirements.txt
```

- Source paths are relative to the build context
- Destination paths are absolute paths in the container

### 9.3 `env` (Phase 1+)

Sets environment variables.

```text
env MY_VAR=value
env APP_ENV=production
```

Compiles to:

```dockerfile
ENV MY_VAR=value
ENV APP_ENV=production
```

### 9.4 `workdir` (Phase 1+)

Sets the working directory for subsequent Dockerfile commands.

```text
workdir /app
```

Compiles to:

```dockerfile
WORKDIR /app
```

**Important:** The `workdir` command only affects subsequent Boothfile and Dockerfile commands *during the build process*. It does **not** affect the user's working directory when they log into the booth.

The user's login working directory is controlled by `variants/<variant>/booth_entry` (e.g., `/home/coder/code` for the base variant). This is intentional — build-time concerns are separate from runtime user experience.

Example:
```text
workdir /tmp/build
run make install       # This runs in /tmp/build
```

When the user logs in, they will still be in `/home/coder/code` (or whatever the variant's entry script sets), not `/tmp/build`.

### 9.5 `expose` (Phase 1+)

Declares a port.

```text
expose 8080
```

Compiles to:

```dockerfile
EXPOSE 8080
```

### 9.6 `label` (Phase 1+)

Adds metadata.

```text
label maintainer="team@example.com"
```

Compiles to:

```dockerfile
LABEL maintainer="team@example.com"
```

### 9.7 `arg` (Phase 1+)

Defines a build argument.

```text
arg NODE_VERSION=20
```

Compiles to:

```dockerfile
ARG NODE_VERSION=20
```

#### Using variables

Variables defined with `arg` can be used anywhere with `${name}` syntax:

```text
arg NODE_VERSION=20
arg PYTHON_VERSION=3.12

setup nodejs ${NODE_VERSION}
setup python ${PYTHON_VERSION}
```

Compiles to:

```dockerfile
ARG NODE_VERSION=20
ARG PYTHON_VERSION=3.12
RUN nodejs--setup.sh ${NODE_VERSION}
RUN python--setup.sh ${PYTHON_VERSION}
```

Docker expands the variables at build time. Override defaults with:

```bash
booth build --build-arg NODE_VERSION=22
```

#### Naming conventions

Variable names can be any valid identifier. Uppercase is conventional (e.g., `NODE_VERSION`) but not required:

```text
arg node_version=20      # works fine
arg NODE_VERSION=20      # conventional
```

Boothfile does not enforce a naming convention — use whatever fits your project's style.

### 9.8 Dependency Contract

Setup scripts (run as root) and install scripts (run as user) **must not silently install their own dependencies**. If a required dependency is missing, the script must **error at build time** with a clear message.

For example:
- `pip--install.sh` requires Python to already be installed. If Python is missing, it must fail — not quietly install a default Python version.
- `mvn--setup.sh` requires a JDK to already be installed. If no JDK is found, it must fail.

This prevents subtle bugs where the wrong version of a dependency gets installed:

```text
# Without this contract, this could silently install default Python (3.12)
# then install Python 3.13 on top — leaving django on 3.12's pip
install pip django
setup python 3.13
```

With the contract, the above fails immediately at `install pip django` because Python isn't installed yet. The user gets a clear build error and fixes the order.

**Rule:** Setup scripts set up tools. Install scripts use tools. Neither guesses.

### 9.9 `setup` (Phase 2+)

Declares a CodingBooth setup script dependency, optionally with parameters.

**Syntax:** `setup <n> [<args...>]`

```text
setup python
setup python 3.12
setup jdk 21 temurin
setup nodejs
```

Compiles to:

```dockerfile
RUN python--setup.sh
RUN python--setup.sh 3.12
RUN jdk--setup.sh 21 temurin
RUN nodejs--setup.sh
```

#### Parameters

Parameters are **positional** — they are passed to the setup script in the order they appear on the line.

The meaning of each parameter is defined by the setup script itself (e.g., `jdk--setup.sh` expects `<version>` then `<vendor>`). Boothfile does not interpret or validate parameter values; it passes them through.

This design:
- Keeps Boothfile simple (no named parameter syntax to parse)
- Matches how shell scripts naturally receive arguments
- Aligns with how `booth init` templates define parameters (ordered `[[setups.params]]`)

#### Idempotent expectation

Setup scripts **must**:
- Be safe to run multiple times (idempotent)
- **Fail with a clear error** if required dependencies are missing (see Section 9.8)

#### Setup script validation (Future)

The compiler **validates** setup script names against the list of known scripts.

Behavior:
- **Known script**: Compiles normally
- **Unknown script**: Emits a **warning** (not an error by default)

```text
setup pytohn
```

Output:
```
Warning: Unknown setup script 'pytohn'. Did you mean 'python'?
```

Optional strict mode: `booth build --strict` treats warnings as errors.

#### Custom setup scripts (`.booth/setups/`)

Users can provide their own setup scripts by placing them in `.booth/setups/`. The compiler handles this automatically:

1. When it encounters `setup foo`, it checks if `.booth/setups/foo--setup.sh` exists
2. If found, the compiler automatically emits a `COPY` to bring it into the image before the `RUN`
3. If not found, it falls back to the built-in scripts at `/opt/codingbooth/setups/`

For example, given `.booth/setups/myapp--setup.sh`:

```text
setup myapp
```

Compiles to:

```dockerfile
COPY .booth/setups/myapp--setup.sh /opt/codingbooth/setups/myapp--setup.sh
RUN myapp--setup.sh
```

The same resolution applies to `install` — a custom `.booth/setups/pip--install.sh` would override the built-in one.

The user never thinks about the `COPY`. They just write `setup myapp` and it works.

### 9.10 `install` (Phase 3+)

Installs packages using a specified package manager.

**Syntax:** `install <tool> <packages...>`

```text
install pip django
install pip django djangorestframework
install brew gcc
install npm express
```

Compiles to:

```dockerfile
RUN pip--install.sh django
RUN pip--install.sh django djangorestframework
RUN brew--install.sh gcc
RUN npm--install.sh express
```

This mirrors the `setup` pattern:
- `setup python` → `RUN python--setup.sh`
- `install pip django` → `RUN pip--install.sh django`

#### Raw tool access

If you need flags or behavior not supported by the wrapper scripts, use `run`:

```text
run pip install django -U
run npm install express -g
```

### 9.11 `DOCKER` (Escape Hatch)

If a Dockerfile directive is not yet supported as a lowercase command, `DOCKER` passes it through verbatim with the prefix stripped.

```text
DOCKER HEALTHCHECK CMD curl -f http://localhost/ || exit 1
```

Compiles to:

```dockerfile
HEALTHCHECK CMD curl -f http://localhost/ || exit 1
```

This exists as a fallback. Prefer the lowercase commands whenever possible.

---

## 10. Transparency Guarantees

Boothfile must preserve CodingBooth philosophy:

- Containers are disposable
- All persistence comes from Dockerfile layers
- Generated Dockerfile is inspectable via `--emit-dockerfile`

Tooling:

```bash
booth build --emit-dockerfile   # Output generated Dockerfile to stdout
booth build --dryrun            # Show what would be built without building
booth build --strict            # Treat warnings as errors
```

---

## 11. Error Handling & Diagnostics

### 11.1 Compilation errors

The compiler should provide clear, actionable error messages with line numbers:

```text
Boothfile:1: Missing or invalid syntax directive. Expected: # syntax=codingbooth/boothfile:1
Boothfile:7: Unknown command 'instal'. Did you mean 'install'?
Boothfile:12: Unclosed heredoc block started at line 10
```

### 11.2 Warnings

Warnings are emitted for:
- Unknown setup script names (with suggestions)
- Deprecated syntax (future)

Warnings do not stop compilation unless `--strict` is used.

---

## 12. Non-Goals (Initial Version)

Boothfile **will not** initially support:

- Variant or version selection (handled by `config.toml` / CLI)
- Conditionals (`if`, `when`, `else`)
- Loops
- Variables or templating
- Named parameters (e.g., `setup jdk version=21 vendor=temurin`)
- Managing `config.toml`, `startup.sh`, or home directory files

These can be reconsidered later if needed.

---

## 13. Migration Path

### From existing Dockerfile to Boothfile

Users can migrate incrementally:

1. **Start with Phase 1 syntax**: Add the syntax line, convert directives to lowercase, remove the header
   ```text
   # syntax=codingbooth/boothfile:1

   run python--setup.sh
   run pip--install.sh django
   env APP_ENV=production
   ```

2. **Adopt conveniences as available**:
   - Phase 2: Replace `run python--setup.sh` with `setup python`
   - Phase 2: Replace `run jdk--setup.sh 21 temurin` with `setup jdk 21 temurin`
   - Phase 3: Replace `run pip--install.sh django` with `install pip django`

3. **Keep `run` for edge cases**: `run` always remains available for arbitrary shell commands

### Coexistence

During transition, projects may have both:
- `.booth/Dockerfile` (legacy, manually written)
- `.booth/Boothfile` (new, compiled)

Default precedence (no flags): Boothfile wins. See Section 4.1 for full rules.

Users can force a specific file with `--dockerfile` or `--boothfile` flags.

---

## 14. Complete Example

A realistic Boothfile for a Java/Python data engineering project:

```text
# syntax=codingbooth/boothfile:1

# Data engineering booth

# System dependencies
run apt-get update && apt-get install -y graphviz libpq-dev

# Languages
setup python 3.12
setup jdk 21 temurin

# Build tools
setup mvn 3.9.6

# Python packages
install pip django djangorestframework psycopg2-binary

# Project config
copy ./config /opt/config
copy requirements.txt /tmp/requirements.txt

# Environment
env APP_ENV=production
```

Compiles to (via `booth build --emit-dockerfile`):

```dockerfile
# syntax=docker/dockerfile:1.7
ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest
FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG}

ARG BOOTH_VARIANT_TAG=base
ARG BOOTH_VERSION_TAG=latest

RUN apt-get update && apt-get install -y graphviz libpq-dev
RUN python--setup.sh 3.12
RUN jdk--setup.sh 21 temurin
RUN mvn--setup.sh 3.9.6
RUN pip--install.sh django djangorestframework psycopg2-binary
COPY ./config /opt/config
COPY requirements.txt /tmp/requirements.txt
ENV APP_ENV=production
```

The variant and version (`base`/`latest` here) are defaults — overridden at build time by whatever `config.toml` or `--variant`/`--version` specifies.

---

## 15. Summary

Boothfile is:

- A convenience layer over Dockerfile authoring
- A compiler targeting Dockerfile
- Identified by `# syntax=codingbooth/boothfile:1` — a convention that doubles as a future BuildKit frontend hook
- **All lowercase** — Dockerfile directives as lowercase equivalents, plus Boothfile-specific commands
- Focused on clarity and reproducibility
- **Incrementally adoptable** — useful from Phase 1
- **The intended output format for `booth init`**
- **Unconcerned with variant/version** — those are runtime decisions, not build declarations

The Dockerfile remains the foundation.
Boothfile makes it pleasant to write.
`booth init` makes it pleasant to start.

---

## 16. Quick Reference

| Boothfile                              | Generated Dockerfile                          | Phase |
|----------------------------------------|-----------------------------------------------|-------|
| `# syntax=codingbooth/boothfile:1`     | `# syntax=docker/dockerfile:1.7` + prologue   | 1     |
| `# comment`                            | (stripped)                                    | 1     |
| `run apt-get install -y foo`           | `RUN apt-get install -y foo`                  | 1     |
| `run <<END ... END`                    | `RUN ...` (multi-line)                        | 1     |
| `copy ./src /app`                      | `COPY ./src /app`                             | 1     |
| `env FOO=bar`                          | `ENV FOO=bar`                                 | 1     |
| `workdir /app`                         | `WORKDIR /app`                                | 1     |
| `expose 8080`                          | `EXPOSE 8080`                                 | 1     |
| `label maintainer="me"`               | `LABEL maintainer="me"`                       | 1     |
| `arg NODE_VERSION=20`                  | `ARG NODE_VERSION=20`                         | 1     |
| `setup python`                         | `RUN python--setup.sh`                        | 2     |
| `setup python 3.12`                    | `RUN python--setup.sh 3.12`                   | 2     |
| `setup jdk 21 temurin`                 | `RUN jdk--setup.sh 21 temurin`                | 2     |
| `install pip django`                   | `RUN pip--install.sh django`                  | 3     |
| `install brew gcc`                     | `RUN brew--install.sh gcc`                    | 3     |

---

> **Design mantra:**
> *Make the easy things easy, the hard things possible, and the hidden things visible when needed.*
