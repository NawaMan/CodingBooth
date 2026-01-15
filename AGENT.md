# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CodingBooth WorkSpace is a Docker-powered development environment launcher written in Go (v1.24.1) with legacy Bash components. It delivers containerized development environments with automatic host UID/GID mapping to eliminate the "root-owned files" problem.

## Build Commands

```bash
# Build all platform binaries (outputs to ./bin/)
./cli-build.sh

# Build creates:
# - bin/workspace-linux-amd64, bin/workspace-linux-arm64
# - bin/workspace-darwin-amd64, bin/workspace-darwin-arm64
# - bin/workspace-windows-amd64.exe, bin/workspace-windows-arm64.exe
# - ./workspace (local platform executable)
```

## Test Commands

```bash
# Run all automated tests
./tests/run-automate-tests.sh

# Run specific test suites
cd tests/unit && ./run-all-go-tests.sh        # All Go tests (unit + integration + docker)
cd tests/unit && ./run-go-unit-tests.sh       # Unit tests only
cd tests/basic && ./run-basic-tests.sh        # Real Docker container tests
cd tests/dryrun && ./run-dryrun-tests.sh      # Dry-run tests (no Docker execution)

# Run a single test
cd tests/basic && ./test001--command.sh       # Execute individual test script
cd tests/dryrun && ./test003--command.sh

# Quick sanity check
./sanity-test.sh [variant]
```

## Architecture

```
cli/src/
├── cmd/workspace/     # CLI entry point (main.go, run.go, help.go, version.go)
└── pkg/
    ├── appctx/        # Immutable application context & configuration (builder pattern)
    ├── workspace/     # Core orchestration (runner, variant validation, image management)
    │   └── init/      # Initialization module
    ├── docker/        # Docker CLI wrapper (BuildKit, TTY handling)
    ├── ilist/         # Immutable list utilities
    └── nillable/      # Nullable type wrappers
```

**Execution Flow**: `main.go` → `run.go` → `WorkspaceRunner.Run()` → Docker command execution

**Key Patterns**:
- AppContext is immutable (snapshot-like); use builder pattern for modifications
- One type per file organization
- Configuration precedence: CLI flags → config file → env vars → defaults

## Code Style (from CODESTYLE.md)

- **Variable naming**: Avoid single letters; use `TYPE`, `thisBuilder`, `index` instead of `T`, `l`, `i`
- **Method naming**: Spell out names; use `Length()` not `Len()`
- **Documentation**: One-liner comments for public methods; document surprises only
- **Testing**: Essential coverage only (deep copy, core functionality, edge cases)

## Configuration

- `.ws/config.toml` - Per-project launcher configuration
- `.env` - Runtime environment variables
- `template-config.toml` - Template for new projects
