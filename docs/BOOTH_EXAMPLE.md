# booth example

> Download pre-built example workspaces and start developing in seconds.

`booth example` lets you browse and try ready-made CodingBooth configurations for different languages, tools, and workflows.

```bash
./booth example list
./booth example try python ./my-python-project
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Commands](#commands)
- [Getting Started](#getting-started)
- [Available Examples](#available-examples)
- [Version Matching](#version-matching)

---

## Overview

Examples are complete, working CodingBooth configurations — each with a `booth` wrapper, `.booth/config.toml`, and sample code. They are a quick way to see CodingBooth in action or to bootstrap a new project from a known-good starting point.

Examples are distributed as zip archives alongside each CodingBooth release, so they are always compatible with the version you have installed.

---

## Commands

### `example list`

Show all available examples.

```bash
./booth example list
```

Output:

```
Available examples (30):

  all-java        aws             bun             conda
  demo            deno            dind            elixir
  empty           firebase        gcloud          go
  ...
```

### `example try`

Download and extract an example to a new directory.

```bash
./booth example try <name> <path>
```

- `<name>` — the example to download (from `example list`)
- `<path>` — the target directory (must not already exist)

Example:

```bash
./booth example try python ./my-python-project
```

Output:

```
Downloading python example...
Extracting to ./my-python-project...

Example 'python' ready at: ./my-python-project

To get started:
  cd ./my-python-project
  ./booth install
  ./booth
```

### Flags

| Flag | Description |
|------|-------------|
| `--version <tag>` | Use examples from a specific release (default: current version) |

---

## Getting Started

A typical workflow with examples:

```bash
# 1. Install CodingBooth
curl -fsSL https://github.com/NawaMan/CodingBooth/releases/download/latest/booth | bash
./booth install

# 2. Browse available examples
./booth example list

# 3. Download one
./booth example try go ./my-go-project

# 4. Enter the project and launch
cd ./my-go-project
./booth install
./booth
```

Once running, you can inspect the `.booth/` directory to understand how the example is configured and customize it for your needs.

---

## Available Examples

Examples span a wide range of languages, tools, and configurations:

| Category | Examples |
|----------|----------|
| Languages | go, python, java, all-java, kotlin, rust, nodejs, bun, deno, elixir, haskell, php, ruby, rlang, zig, octave |
| Cloud & CI | aws, gcloud, firebase, dind, kind, kind-app |
| Tools | homebrew, neovim, server, jetbrain |
| Package managers | pip, npm, conda |
| Security | sandbox-allowlist-extra, sandbox-envoy, firewall |
| Getting started | empty, demo |

The `empty` example provides a minimal starting point — just the booth wrapper and a bare config. The `demo` example is a full showcase with multiple notebooks and a sample application.

---

## Version Matching

By default, `booth example` downloads examples from the same release as your installed CodingBooth version. This ensures compatibility between the example configuration and the binary.

To use examples from a different version:

```bash
./booth example list --version 0.25.0
./booth example try python ./my-project --version 0.25.0
```
