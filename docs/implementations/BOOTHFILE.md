# Boothfile Implementation

A simplified, declarative configuration format that compiles to Dockerfile.

Boothfile provides a higher-level authoring format for CodingBooth image customization. 
Instead of writing verbose Dockerfile boilerplate, users write concise, 
  intent-based commands that compile deterministically into a standard Dockerfile.

This document describes the technical implementation of Boothfile parsing, compilation, 
  and integration with CodingBooth.

---

## Design Goals

- **Eliminate boilerplate** — Hide ARG/FROM/SHELL ceremony
- **Preserve transparency** — Generated Dockerfile is always inspectable
- **Order-preserving**      — Commands emit in exact order they appear
- **Extensible**            — Custom setup/install scripts via `.booth/setups/`
- **Future-proof**          — `# syntax=` convention enables BuildKit frontend migration

---

## High-Level Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│                              User writes                                  │
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  .booth/Boothfile                                                   │  │
│  │                                                                     │  │
│  │  # syntax=codingbooth/boothfile:1                                   │  │
│  │                                                                     │  │
│  │  # Languages                                                        │  │
│  │  setup python 3.12                                                  │  │
│  │  setup nodejs 20                                                    │  │
│  │                                                                     │  │
│  │  # Packages                                                         │  │
│  │  install pip django requests                                        │  │
│  │                                                                     │  │
│  │  env APP_ENV=production                                             │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│                           ┌────────────────┐                              │
│                           │     Parser     │                              │
│                           │                │                              │
│                           │  Tokenizes     │                              │
│                           │  Validates     │                              │
│                           │  Builds AST    │                              │
│                           └───────┬────────┘                              │
│                                   │                                       │
│                                   ▼                                       │
│                           ┌────────────────┐                              │
│                           │    Compiler    │                              │
│                           │                │                              │
│                           │  Generates     │                              │
│                           │  Dockerfile    │                              │
│                           └───────┬────────┘                              │
│                                   │                                       │
│                                   ▼                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │  .booth/.Dockerfile.generated                                       │  │
│  │                                                                     │  │
│  │  # syntax=docker/dockerfile:1.7                                     │  │
│  │  ARG BOOTH_VARIANT_TAG=base                                         │  │
│  │  ARG BOOTH_VERSION_TAG=latest                                       │  │
│  │  FROM nawaman/codingbooth:${BOOTH_VARIANT_TAG}-${BOOTH_VERSION_TAG} │  │
│  │                                                                     │  │
│  │  # Languages                                                        │  │
│  │  RUN python--setup.sh 3.12                                          │  │
│  │  RUN nodejs--setup.sh 20                                            │  │
│  │                                                                     │  │
│  │  # Packages                                                         │  │
│  │  RUN pip--install.sh django requests                                │  │
│  │                                                                     │  │
│  │  ENV APP_ENV=production                                             │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                      │
│                                    ▼                                      │
│                           ┌────────────────┐                              │
│                           │  Docker Build  │                              │
│                           └────────────────┘                              │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## Architecture

### Processing Pipeline

```
Boothfile → Parser → ParseResult → Compiler → CompileResult → Dockerfile
                         │                          │
                         ▼                          ▼
                    []Command                   string
                    []ParseError               []ParseError
                    []Warning                  []Warning
```

### Component Relationships

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           CLI Entry Points                               │
│                                                                         │
│  ┌─────────────────────┐         ┌─────────────────────────────────┐   │
│  │  codingbooth run    │         │  codingbooth emit-dockerfile    │   │
│  │                     │         │                                 │   │
│  │  (builds & runs)    │         │  (prints Dockerfile to stdout)  │   │
│  └──────────┬──────────┘         └───────────────┬─────────────────┘   │
│             │                                    │                      │
│             └────────────────┬───────────────────┘                      │
│                              ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    ensure_docker_image.go                         │  │
│  │                                                                   │  │
│  │  normalizeDockerFile() → compileBoothfile()                       │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                              │                                          │
│                              ▼                                          │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                    boothfile package                              │  │
│  │                                                                   │  │
│  │  ┌─────────────┐    ┌──────────────┐    ┌──────────────────────┐  │  │
│  │  │  parser.go  │───▶│ compiler.go  │───▶│ CompileResult        │  │  │
│  │  │             │    │              │    │   .Dockerfile        │  │  │
│  │  │  Parser     │    │  Compiler    │    │   .Errors            │  │  │
│  │  │  Command    │    │  Options     │    │   .Warnings          │  │  │
│  │  └─────────────┘    └──────────────┘    └──────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Parser

The parser (`parser.go`) converts Boothfile text into a sequence of `Command` structs.

### Command Types

```go
const (
    CommandUnknown     // Unrecognized command (error)
    CommandComment     // # comment
    CommandBlank       // Empty line
    CommandRun         // run <command>
    CommandRunHeredoc  // run <<END ... END
    CommandCopy        // copy <src> <dest>
    CommandEnv         // env KEY=value
    CommandWorkdir     // workdir /path
    CommandExpose      // expose 8080
    CommandLabel       // label key=value
    CommandArg         // arg NAME=default
    CommandSetup       // setup <tool> [args...]
    CommandInstall     // install <manager> <packages...>
    CommandDocker      // DOCKER <raw instruction>
)
```

### Command Structure

```go
type Command struct {
    Type            CommandType
    Args            []string        // Parsed arguments
    Raw             string          // Original line text
    LineNumber      int
    HeredocMode     HeredocMode     // For heredoc commands
    HeredocDelimiter string         // e.g., "END"
    HeredocContent  []string        // Lines within heredoc
}
```

### Heredoc Modes

| Syntax        | Mode      | Behavior                         |
|---------------|-----------|----------------------------------|
| `run <<END`   | Verbatim  | Pass through to Docker heredoc   |
| `run &&<<END` | And-join  | Join lines with `&&`             |
| `run ;<<END`  | Semi-join | Join lines with `;`              |

### Parse Flow

```
Input Line
    │
    ▼
┌───────────────────┐
│ Is blank?         │──Yes──▶ CommandBlank
└─────────┬─────────┘
          │ No
          ▼
┌───────────────────┐
│ Starts with #?    │──Yes──▶ CommandComment (or validate syntax directive)
└─────────┬─────────┘
          │ No
          ▼
┌───────────────────┐
│ Heredoc start?    │──Yes──▶ Parse heredoc block → CommandRunHeredoc
└─────────┬─────────┘
          │ No
          ▼
┌───────────────────┐
│ Parse command     │
│ keyword + args    │
└─────────┬─────────┘
          │
          ▼
    Map to CommandType
```

---

## Compiler

The compiler (`compiler.go`) transforms `ParseResult` into a Dockerfile string.

### Compilation Flow

```
ParseResult
    │
    ▼
┌───────────────────────────────────────────┐
│ Write Prologue                            │
│                                           │
│   # syntax=docker/dockerfile:1.7          │
│   ARG BOOTH_VARIANT_TAG=base              │
│   ARG BOOTH_VERSION_TAG=latest            │
│   FROM nawaman/codingbooth:${...}         │
│                                           │
│   (+ custom setups COPY/ENV if present)   │
└─────────────────────┬─────────────────────┘
                      │
                      ▼
┌───────────────────────────────────────────┐
│ For each Command:                         │
│                                           │
│   CommandBlank   → emit blank line        │
│   CommandComment → emit # comment         │
│   CommandRun     → RUN <args>             │
│   CommandSetup   → RUN <tool>--setup.sh   │
│   CommandInstall → RUN <mgr>--install.sh  │
│   CommandCopy    → COPY <src> <dest>      │
│   CommandEnv     → ENV KEY=value          │
│   CommandDocker  → <raw instruction>      │
│   ...                                     │
└─────────────────────┬─────────────────────┘
                      │
                      ▼
               CompileResult
```

### Command Compilation

| Boothfile                  | Generated Dockerfile           |
|----------------------------|--------------------------------|
| `run apt-get update`       | `RUN apt-get update`           |
| `setup python 3.12`        | `RUN python--setup.sh 3.12`    |
| `install pip django`       | `RUN pip--install.sh django`   |
| `copy ./src /app`          | `COPY ./src /app`              |
| `env FOO=bar`              | `ENV FOO=bar`                  |
| `DOCKER HEALTHCHECK ...`   | `HEALTHCHECK ...`              |

### Heredoc Processing

**Verbatim mode** (`run <<END`):
```dockerfile
RUN <<END
set -e
apt-get update
END
```

**And-join mode** (`run &&<<END`):
```dockerfile
RUN apt-get update \
    && apt-get install -y curl \
    && rm -rf /var/lib/apt/lists/*
```

---

## Custom Setup Scripts

Users can provide custom setup/install scripts in `.booth/setups/`.

### Detection and Handling

```
┌────────────────────────────────────────────────────────┐
│  .booth/                                               │
│  ├── Boothfile                                         │
│  └── setups/                                           │
│      ├── myapp--setup.sh      ← Custom setup script    │
│      └── custom--install.sh   ← Custom install script  │
└────────────────────────────────────────────────────────┘
                              │
                              ▼
                    Compiler detects directory
                              │
                              ▼
┌────────────────────────────────────────────────────────┐
│  Generated Dockerfile Prologue:                        │
│                                                        │
│  COPY .booth/setups/ /home/coder/.booth/setups/        │
│  ENV PATH=/home/coder/.booth/setups:$PATH              │
└────────────────────────────────────────────────────────┘
                              │
                              ▼
          Scripts found via PATH (custom takes precedence)
```

### Script Resolution Order

1. `/home/coder/.booth/setups/` (project custom scripts)
2. `/opt/codingbooth/setups/` (base image scripts)

---

## File Detection Precedence

When determining which file to use for image building:

```
┌────────────────────────────────────────────────────────────────────────┐
│                        CLI Flag Check                                  │
│                                                                        │
│  --image set?  ────Yes────▶  Use specified image (no build)            │
│       │                                                                │
│       No                                                               │
│       ▼                                                                │
│  --dockerfile set?  ──Yes──▶  Use specified Dockerfile                 │
│       │                                                                │
│       No                                                               │
│       ▼                                                                │
│  --boothfile set?  ───Yes──▶  Compile specified Boothfile              │
│       │                                                                │
│       No                                                               │
│       ▼                                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                    Auto-Detection                               │   │
│  │                                                                 │   │
│  │  .booth/Boothfile exists?  ──Yes──▶  Compile Boothfile          │   │
│  │       │                                                         │   │
│  │       No                                                        │   │
│  │       ▼                                                         │   │
│  │  .booth/Dockerfile exists?  ─Yes──▶  Use Dockerfile             │   │
│  │       │                                                         │   │
│  │       No                                                        │   │
│  │       ▼                                                         │   │
│  │  Use prebuilt image (nawaman/codingbooth:variant-version)       │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Error Handling

### Parse Errors

| Error                      | Cause                                                  |
|----------------------------|--------------------------------------------------------|
| Missing syntax directive   | First line is not `# syntax=codingbooth/boothfile:1`   |
| Unknown command            | Command keyword not recognized                         |
| Unclosed heredoc           | EOF before heredoc delimiter                           |

### Compile Errors

| Error                          | Cause                                  |
|--------------------------------|----------------------------------------|
| `run` without args             | Empty run command                      |
| `copy` without destination     | Missing destination path               |
| `setup` without tool           | Missing tool name                      |
| `install` without packages     | Only tool name, no packages            |
| Empty heredoc after processing | Heredoc contains only comments/blanks  |

### Warnings

| Warning                | Cause                                        |
|------------------------|----------------------------------------------|
| Unknown setup script   | `setup foo` where `foo--setup.sh` not found  |

### Strict Mode

With `--strict`, warnings become errors:

```bash
codingbooth emit-dockerfile --strict
```

---

## CLI Integration

### Subcommand: `emit-dockerfile`

Compiles Boothfile and prints to stdout without building:

```bash
codingbooth emit-dockerfile [--code <path>] [--boothfile <path>] [--strict]
```

### Run Integration

During normal `codingbooth run`:

1. `normalizeDockerFile()` checks for Boothfile
2. If found, `compileBoothfile()` generates `.booth/.Dockerfile.generated`
3. Docker build uses the generated file

---

## Implementation Files

| File                                                                                           | Purpose                      |
|------------------------------------------------------------------------------------------------|------------------------------|
| [`cli/src/pkg/boothfile/parser.go`](../../cli/src/pkg/boothfile/parser.go)                     | Tokenizer and parser         |
| [`cli/src/pkg/boothfile/compiler.go`](../../cli/src/pkg/boothfile/compiler.go)                 | Dockerfile generator         |
| [`cli/src/pkg/booth/ensure_docker_image.go`](../../cli/src/pkg/booth/ensure_docker_image.go)   | Build integration            |
| [`cli/src/cmd/codingbooth/emit.go`](../../cli/src/cmd/codingbooth/emit.go)                     | `emit-dockerfile` subcommand |

### Key Functions

| Function               | Location               | Purpose                    |
|------------------------|------------------------|----------------------------|
| `Parser.ParseString()` | parser.go              | Parse Boothfile content    |
| `Compiler.Compile()`   | compiler.go            | Generate Dockerfile        |
| `compileBoothfile()`   | ensure_docker_image.go | Integration entry point    |
| `emitDockerfile()`     | emit.go                | CLI subcommand handler     |

---

## Test Coverage

| Test Type          | Location                            | Count                   |
|--------------------|-------------------------------------|-------------------------|
| Go unit tests      | `cli/src/pkg/boothfile/*_test.go`   | Parser + compiler tests |
| Shell unit tests   | `tests/boothfile/`                  | 30 tests                |
| Integration tests  | `tests/complex/test-boothfile-*/`   | 5 tests                 |
| Dryrun tests       | `tests/dryrun/test014-015`          | 2 tests                 |

---

## Related Documentation

- [Boothfile Design Plan](../plans/Boothfile.md) — Original design document
- [Variants](VARIANTS.md) — Base image variants

---

## Summary

Boothfile provides:

- **Concise syntax** — Write intent, not boilerplate
- **Transparent compilation** — Always inspect with `emit-dockerfile`
- **Extensibility** — Custom scripts via `.booth/setups/`
- **Full compatibility** — Generates standard Dockerfile
- **Order preservation** — What you write is what you get

The implementation consists of a parser (lexer + AST builder) and compiler (code generator), integrated into the CodingBooth CLI for seamless image building.
