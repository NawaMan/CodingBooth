# CodingBooth Examples System

This document describes the implementation of the `booth example` command and the release workflow for distributing examples.

## Overview

The examples system allows users to:
1. List available CodingBooth examples
2. Download and try examples in a new directory

Examples are packaged and distributed via GitHub releases, making them version-matched with the binary.

## Commands

### `booth example list`

Lists all available examples from the current version's release.

```bash
booth example list
```

Output:
```
Available examples (29):

  all-java        aws             bun             conda
  demo            deno            dind            elixir
  empty           firebase        gcloud          go
  ...
```

Options:
- `--version <tag>` - Fetch examples from a specific release (default: current binary version)

```bash
booth example list --version 0.16.0
```

**Implementation details:**
- Fetches `example-list.txt` from GitHub releases
- Caches the list in `~/.cache/codingbooth/versions/<version>/example-list.txt`
- Strips `-example` suffix for cleaner display
- Displays in 4-column format, sorted alphabetically

### `booth example try`

Downloads and extracts an example to a specified directory.

```bash
booth example try <name> <path> [--version <tag>]
```

Examples:
```bash
# Try the python example
booth example try python ./my-python-project

# Try a specific version's example
booth example try go ./my-go-project --version 0.16.0
```

**Validation:**
- Target path must not already exist
- Target path must be **outside** the current booth folder (prevents nesting)

**Process:**
1. Downloads `<name>-example.zip` from GitHub releases (or `demo.zip` for demo)
2. Extracts to target path, stripping the top-level folder
3. Displays instructions for getting started

Output:
```
Downloading python example...
Extracting to /tmp/my-python-project...

Example 'python' ready at: /tmp/my-python-project

To get started:
  cd /tmp/my-python-project
  ./booth install
  ./booth
```

## Release Workflow

The `.github/workflows/release-examples.yaml` workflow packages and releases examples.

### Trigger

Manual dispatch with a release tag:
```yaml
on:
  workflow_dispatch:
    inputs:
      release_tag:
        description: 'Release tag (e.g., examples-v1.0.0)'
        required: true
        default: 'examples-latest'
```

### Steps

1. **Build codingbooth binary** - Ensures fresh binary for booth wrappers
2. **Update booth wrappers** - Runs `examples/update-booth.sh` to sync booth wrapper to all examples
3. **Create example-list.txt** - Generates index of all examples
4. **Package workspace examples** - Creates `<name>-example.zip` for each example in `examples/workspaces/`
5. **Package demo** - Creates `demo.zip` from `examples/demo/`
6. **Create GitHub Release** - Publishes all artifacts

### Release Artifacts

Each release contains:
- `example-list.txt` - Index of all available examples
- `<name>-example.zip` - Individual example packages (e.g., `python-example.zip`, `go-example.zip`)
- `demo.zip` - Demo workspace

## File Locations

### Source Code

- `cli/src/cmd/codingbooth/example.go` - Command implementation
- `.github/workflows/release-examples.yaml` - Release workflow

### Cache

Example lists are cached at:
- Linux: `~/.cache/codingbooth/versions/<version>/example-list.txt`
- macOS: `~/Library/Caches/codingbooth/versions/<version>/example-list.txt`
- Windows: `%LOCALAPPDATA%\codingbooth\versions\<version>\example-list.txt`

## Version Matching

The `booth example` commands default to the binary's version:
- If running `booth` version `0.16.0`, it fetches from the `0.16.0` release
- This ensures examples are compatible with the installed version
- Users can override with `--version` flag if needed

## Example Sources

Examples are maintained in:
- `examples/workspaces/*-example/` - Language/tool-specific examples
- `examples/demo/` - Demo workspace

Each example contains:
- `booth` wrapper script
- `.booth/config.toml` configuration
- `.booth/Dockerfile` (optional) for custom images
- Example code and documentation
