# Changelog

This file contains a list of changes for each released version.

## v0.11.0
- Core engine rewritten in GO for portability and maintainability.
- Repository history cleaned to remove legacy implementation artifacts.
- Port List and List Builder to GO.
- Port Docker function to GO.

## v0.10.0
- Bring in the wrapper

## v0.9.0
- Simplify conditional setups with WS_HAS_NOTEBOOK, WS_HAS_VSCODE and WS_HAS_DESKTOP
- Simplify the basic Dockfile structure to use ARG instead of ENV -- as it will be there anyway.
- Release to latest only when not RC
- NEXT port by default
- Print image pull/build to stderr to give the user some insight for long running commands

## v0.8.0
- Not chown in workspace-user-setup

## v0.7.0
- Default variant
- Variant alias
- Compatibilities
- Tests
- Make it work on Mac
- Verbose mode in workspace-user-setup

## v0.6.0
- Sign the image
- Change the ws-version display
- Fix ARM build problem
- Allow separate build for pushing

## v0.5.0
- Fix the path problem when running on Windows.
- Append variant and version to the image tag so it is cached locally.
- Adjust for the wrapper.

## v0.4.0
- Fix the version to each docker
- keep-alive
- Rename variants

## v0.3.0
- Rename all `*-setup.sh` to `*--setup.sh`.

## v0.2.0

### Major Updates
- Local image builds now work properly.
- Introduced a unified build script (`build.sh`).
  - Added the `--no-cache` option.
- Refactored `workspace`:
  - Modularized into clear functions and procedures.
  - First experimental implementation of **Docker-in-Docker (DinD)** via a sidecar container (attempted to isolate from the host — ultimately not fully successful).
  - Simplified configuration structure.
  - Prefixed all workspace-related environment variables with `WS_`.
  - Added `--unit-test` flag to skip running `Main()` for easier testing.
  - Added support for random or next-available port selection (`RANDOM` / `NEXT`).
- Reorganized setup scripts into **startup**, **profile**, and **starter** stages.
- Removed PowerShell support (maintenance overhead too high).
- Added multiple example configurations:
  - `dind`
  - `go`
  - `java`
  - `jetbrain`
  - `nodejs`
  - `python`
  - `server`

### Supported Variants
- **Base**
- **Notebook**
- **CodeServer**
- **Desktop**
  - XFCE
  - KDE

### Supported Setups
- `brew`
- `chromium-browser`
- `codeserver`
- `dind`
- `docker-buildx`
- `docker-compose`
- `eclipse`
- `firefox`
- `google-chrome`
- `go`
- `gradle`
- `idea`
- `jdk`
- `jenv`
- `jetbrains`
- `kde`
- `lxqt`
- `mvn`
- `nodejs`
- `notebook`
- `pycharm`
- `python`
- `template`
- `variant`
- `vscode`
- `xfce`

### Supported Notebook Kernels
- `bash-nb-kernel`
- `java-nb-kernel`

### Supported Code Extensions
- `bash-code-extension`
- `go-code-extension`
- `java-code-extension`
- `jupyter-code-extension`
- `python-code-extension`
- `react-code-extension`

### Supported Notebook Plugins
- `jetbrains-plugin`
- `lombok-eclipse`
