# Boothfile (Draft Plan)

> **Status:** Draft / Design Proposal
>
> This document describes the initial design and intent of **Boothfile**, a simplified, declarative configuration format for CodingBooth. It is intentionally incomplete and will be refined over time.

---

## 1. Motivation

CodingBooth currently uses a Dockerfile-based customization model. While powerful, this exposes users to:

- Boilerplate Dockerfile headers that must remain fixed
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

---

## 2. Design Principles

### 2.1 Declarative over imperative

Users describe *what they want*, not *how to install it*.

```text
setup python
install pip django
```

not:

```dockerfile
RUN python--setup.sh
RUN pip--install.sh django
```

### 2.2 Generated, not interpreted

- Boothfile is compiled into a Dockerfile
- The Dockerfile remains the source of truth
- No hidden runtime mutations

Users must always be able to inspect the generated Dockerfile.

### 2.3 Order-preserving

Boothfile commands are emitted to the Dockerfile in the **exact order they appear**.

This is critical because:
- Docker layer caching depends on command order
- Dependencies must be installed before dependents
- Users can reason about build behavior by reading top-to-bottom

### 2.4 Case convention

Boothfile uses a clear case convention to distinguish between convenience commands and raw passthrough:

| Case        | Meaning                          | Examples                        |
|-------------|----------------------------------|---------------------------------|
| `lowercase` | Boothfile convenience (magic)    | `setup`, `pip install`, `copy`  |
| `UPPERCASE` | Raw passthrough (no magic)       | `DOCKER`, `BASH`                |

This makes it immediately obvious when you're using Boothfile abstractions vs. dropping down to raw commands.

---

## 3. Phased Implementation

Boothfile will be implemented incrementally, allowing users to adopt it immediately while features are added over time.

### Phase 1: Header Generation + Raw Passthrough

**Goal:** Eliminate boilerplate. Users write familiar Dockerfile commands.

What works:
- `variant` / `version` directives
- `DOCKER` passthrough (raw Dockerfile commands)
- `BASH` passthrough (raw shell commands)
- Comments

Example Boothfile (Phase 1):
```text
variant notebook
version latest

# Install graphviz
DOCKER RUN apt-get update && apt-get install -y graphviz

# Setup Python and install Django
DOCKER RUN python--setup.sh
DOCKER RUN pip--install.sh django
```

**Value delivered:** No more copy-pasting ARG/FROM boilerplate. Immediate usability.

### Phase 2: Setup Convenience

**Goal:** Simplify setup script invocation.

New command:
- `setup <name>` --> `RUN <name>--setup.sh`

Example Boothfile (Phase 2):
```text
variant notebook
version latest

DOCKER RUN apt-get update && apt-get install -y graphviz

setup python
DOCKER RUN pip--install.sh django
```

### Phase 3: Package Manager Conveniences

**Goal:** Simplify common package installation patterns.

New commands:
- `install pip <packages>` --> `RUN pip--install.sh <packages>`
- `install npm <packages>` --> `RUN npm--install.sh <packages>`
- `install brew <packages>` --> `RUN brew--install.sh <packages>`
- `copy <src> <dest>` --> `COPY <src> <dest>`

Example Boothfile (Phase 3):
```text
variant notebook
version latest

BASH apt-get update && apt-get install -y graphviz

setup python
install pip django djangorestframework

copy ./config /opt/config
```

### Future Phases

- Setup script validation with suggestions
- Additional package managers (`gem install`, `cargo install`, etc.)
- Editor tooling / syntax highlighting
- Alternative compilation targets (Podman, Buildah)

---

## 4. Relationship to Dockerfile

Boothfile:
- Is optional
- Compiles into a Dockerfile
- Can coexist with a manually written Dockerfile (advanced usage)

Proposed behavior:

- If `Boothfile` exists --> generate Dockerfile
- If `.booth/Dockerfile` exists and no Boothfile --> use as-is
- Flag: `booth build --emit-dockerfile` to output generated Dockerfile

---

## 5. Fixed Dockerfile Prologue (Hidden)

Certain Dockerfile lines are required for CodingBooth to function correctly.

These include (conceptually):

- `FROM nawaman/codingbooth:<variant>-<version>`
- Required `SHELL` configuration
- Standard `ARG` definitions
- Required environment variables

These lines:
- Are generated automatically
- Are not user-editable in Boothfile
- May evolve over time without breaking Boothfiles

---

## 6. Boothfile Structure

Boothfile is a **line-oriented DSL** with simple commands.

Example (using Phase 3 syntax):

```text
# Development environment for my Django project
variant notebook
version latest

setup python
install pip django

setup java-jjava-nb-kernel
```

### 6.1 Global directives

| Directive             | Description                           | Default                |
|-----------------------|---------------------------------------|------------------------|
| `variant <name>`      | Select CodingBooth variant            | `base`                 |
| `version <tag>`       | Select image version                  | `latest`               |
| `namespace <name>`    | Image namespace *(future)*            | `nawaman/codingbooth`  |

These map directly to image selection in CodingBooth.

All directives are **optional**. A minimal Boothfile can omit them entirely:

```text
# Uses base:latest by default
BASH echo "Hello from CodingBooth"
```

---

## 7. Comments

Boothfile supports comments for documentation and readability.

### 7.1 Full-line comments

Lines starting with `#` are ignored.

```text
# This is a comment
setup python
```

### 7.2 Inline comments

Comments may appear at the end of a line after `#`.

```text
setup python       # Required for Django
pip install django # Web framework
```

### 7.3 Compilation behavior

Comments are **stripped** during compilation and do not appear in the generated Dockerfile.

Future consideration: A flag like `--preserve-comments` could emit comments as Dockerfile `# ...` lines for traceability.

---

## 8. Raw Passthrough Commands

Uppercase commands pass through to the generated Dockerfile with minimal transformation. These are available from **Phase 1**.

### 8.1 `DOCKER` — Raw Dockerfile directives

Passes any Dockerfile instruction directly to the output.

```text
DOCKER RUN apt-get update && apt-get install -y graphviz
DOCKER COPY . /opt/data
DOCKER ENV MY_VAR=value
DOCKER WORKDIR /app
```

Compiles to:

```dockerfile
RUN apt-get update && apt-get install -y graphviz
COPY . /opt/data
ENV MY_VAR=value
WORKDIR /app
```

### 8.2 `BASH` — Raw shell commands

A convenience shorthand for `DOCKER RUN`.

```text
BASH apt-get update && apt-get install -y graphviz
```

Compiles to:

```dockerfile
RUN apt-get update && apt-get install -y graphviz
```

### 8.3 Multi-line commands

Complex commands spanning multiple lines use heredoc-style syntax:

```text
BASH <<END
  apt-get update
  apt-get install -y \
    unzip \
    curl \
    jq
  rm -rf /var/lib/apt/lists/*
END
```

Compiles to:

```dockerfile
RUN apt-get update \
    && apt-get install -y \
    unzip \
    curl \
    jq \
    && rm -rf /var/lib/apt/lists/*
```

Delimiter rules:
- The delimiter word (e.g., `END`) can be any uppercase identifier
- The closing delimiter must appear alone on its own line
- Leading whitespace inside the block is preserved (for readability) but normalized during compilation

---

## 9. Convenience Commands (Lowercase)

These commands provide Boothfile "magic" — simpler syntax that compiles to more verbose Dockerfile instructions.

### 9.1 `setup` (Phase 2+)

Declares a CodingBooth setup script dependency.

```text
setup python
setup nodejs
```

Compiles to:

```dockerfile
RUN python--setup.sh
RUN nodejs--setup.sh
```

#### Idempotent expectation

Setup scripts **must**:
- Be safe to run even if prerequisites are missing
- Exit successfully if the feature is not applicable

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

### 9.2 `install` (Phase 3+)

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
- `setup python` --> `RUN python--setup.sh`
- `install pip django` --> `RUN pip--install.sh django`

#### Raw tool access

If you need flags or behavior not supported by the wrapper scripts, use `BASH`:

```text
BASH pip install django -U
BASH npm install express -g
```

### 9.3 `copy` (Phase 3+)

Copying files into the image.

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

---

## 10. Transparency Guarantees

Boothfile must preserve CodingBooth philosophy:

- Containers are disposable
- All persistence comes from Dockerfile layers
- Generated Dockerfile is inspectable

Recommended tooling:

```bash
booth build --emit-dockerfile   # Output generated Dockerfile to stdout
booth build --dryrun            # Show what would be built without building
booth build --strict            # Treat warnings as errors
```

---

## 11. Error Handling & Diagnostics

### 11.1 Compilation errors

The compiler should provide clear, actionable error messages:

```text
Boothfile:7: Unknown directive 'instal'. Did you mean 'install'?
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

- Conditionals (`if`, `when`, `else`)
- Loops
- Variables
- Templating

These can be reconsidered later if needed.

---

## 13. Migration Path

### From existing Dockerfile to Boothfile

Users can migrate incrementally:

1. **Start with Phase 1 syntax**: Wrap existing RUN commands with `DOCKER`
   ```text
   variant base
   version latest
   
   DOCKER RUN python--setup.sh
   DOCKER RUN pip--install.sh django
   ```

2. **Adopt conveniences as available**:
   - Phase 2: Replace `DOCKER RUN python--setup.sh` with `setup python`
   - Phase 3: Replace `DOCKER RUN pip--install.sh django` with `install pip django`

3. **Keep raw commands for edge cases**: `BASH` and `DOCKER` always remain available

### Coexistence

During transition, projects may have both:
- `.booth/Dockerfile` (legacy, manually written)
- `Boothfile` (new, compiled)

Proposed precedence:
- If `Boothfile` exists, use it (generates Dockerfile)
- Otherwise, fall back to `.booth/Dockerfile`

---

## 14. Summary

Boothfile is:

- A convenience layer
- A compiler targeting Dockerfile
- Opinionated but escapable
- Focused on clarity and reproducibility
- **Incrementally adoptable** — useful from Phase 1

The Dockerfile remains the foundation.
Boothfile makes it pleasant to write.

---

## 15. Quick Reference

| Boothfile                              | Generated Dockerfile                          | Phase |
|----------------------------------------|-----------------------------------------------|-------|
| `variant notebook`                     | (affects FROM line)                           | 1     |
| `version latest`                       | (affects FROM line)                           | 1     |
| `# comment`                            | (stripped)                                    | 1     |
| `DOCKER RUN apt-get install -y foo`    | `RUN apt-get install -y foo`                  | 1     |
| `DOCKER ENV FOO=bar`                   | `ENV FOO=bar`                                 | 1     |
| `BASH apt-get update`                  | `RUN apt-get update`                          | 1     |
| `BASH <<END ... END`                   | `RUN ...` (multi-line)                        | 1     |
| `setup python`                         | `RUN python--setup.sh`                        | 2     |
| `install pip django`                   | `RUN pip--install.sh django`                  | 3     |
| `install brew gcc`                     | `RUN brew--install.sh gcc`                    | 3     |
| `copy ./src /app`                      | `COPY ./src /app`                             | 3     |

---

> **Design mantra:**
> *Make the easy things easy, the hard things possible, and the hidden things visible when needed.*
