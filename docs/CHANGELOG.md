# Changelog

This file contains a list of changes for each released version.

## 0.39.0

- `booth--expose` — expose container ports to the host at runtime without restarting
  - `booth--expose 8080` opens host:8080 forwarding to container:8080 via `docker exec` + `socat`
  - Works in all variants: base, terminal, codeserver, notebook, desktop
  - Supports explicit port (`8080 18080`), relative port (`8080 +8080`), and default (same port)
  - `--permanent` flag persists tunnel config to `.booth/config.toml`
  - Host-side watcher auto-detects tunnel requests via `.booth/.tmp/tcp-tunnels/` control files
- `booth--restart` — restart the booth from within the container
  - Re-reads `config.toml`, `Boothfile`, rebuilds image if needed, then launches a fresh container
  - CLI arguments from the original invocation are preserved
  - `booth--restart --yes` skips confirmation prompt
  - Works in foreground and command modes (not daemon)
  - VS Code / code-server extension: "CodingBooth: Restart" command palette entry
  - Desktop variants (XFCE, KDE) support restart via desktop actions
  - Web UI reconnects automatically after restart
- `.booth/.tmp/` ephemeral directory lifecycle
  - Wiped and recreated on every booth start, cleaned on exit
  - `booth-startup.txt` with session metadata written on each start
  - `--leave-tmp-on-exit` preserves contents for post-mortem debugging
  - `--keep-tmp-on-start` preserves leftover files from a previous session
- `--log-time` flag — prefix progress messages with timestamps (`HH:MM:SS` format)
  - Useful for debugging startup timing and tracking operation duration
  - Also settable via `CB_LOG_TIME=true` environment variable or `log-time = true` in `config.toml`
- `booth config` improvements
  - `--env`, `--expose`, and `--mount` flags for setting environment variables, port exposures, and volume mounts
  - Renamed from `booth init` — all tests and help text updated
  - First-line output and header formatting improvements
- New templates — cloud tools, databases, languages, dev tools, and AI assistants:
  - **Cloud & Infrastructure:** AWS CDK, AWS SAM CLI (with credential and DinD extensions), Azure CLI (with credential extension), Helm, kubectl (with credential extension), Terraform, Pulumi
  - **Databases:** MongoDB, Redis
  - **Languages:** .NET (replaces single dotnet template), Julia
  - **Build tools:** CMake, Gradle, SBT
  - **Dev tools:** Ansible, Conda, LazyDocker, LazyGit
  - **AI tools:** Aider, GitHub Copilot, Ollama
- Fix arm64 QEMU cross-build by deferring code-server extension installs to first launch
- `socat` added to base image for runtime port tunneling
- `install.sh` — standalone install script for easy bootstrapping
- Recipe example added to documentation
- Variant documentation improvements

## 0.37.0

- `booth config` — interactive TUI for configuring booth environments
  - Browse templates by category, select/deselect with keyboard navigation
  - Multi-tab layout: templates, config fields (variant, port, name), and preview
  - Pre-populate with `--select` flags, then fine-tune interactively
  - Edit existing `.booth/` configurations — reads Boothfile and pre-populates the TUI
  - `--no-tui` flag for headless/CI usage
- `booth shell` / `booth exec` — connect to running booths without SSH or extra ports
  - `booth shell <name>` opens a new interactive shell in a running container
  - `booth exec <name> -- <command>` runs a one-off command and returns the result
- New templates: PlantUML, Mermaid, Freeplane, Obsidian (with autostart and expose extensions)
- `no-sudo` template — revoke passwordless sudo for security hardening
- C# and F# language templates replace the single `dotnet` template
- CodeServer extensions: base, bash, and shutdown extensions now included in the notebook variant
- Test runner overhaul (`run-automate-tests.sh`)
  - Live status graph with per-suite pass/fail counts and real-time log snippets
  - `--only`, `--skip`, `--rerun-failed` flags for targeted test runs
  - Manual tests now discoverable via `run-manual-tests.sh`

## 0.36.0

- Fine-grained home copy with `.mount-this` — booth-entry now uses `smart_copy` for all four home directory seeding stages
  - Directories with `.mount-this` are copied as a unit; without it, only individual files are copied
  - Backward compatible: existing setups without `.mount-this` behave identically
  - Matches the `.booth/cache/` mount logic for consistency
- `cache-dirs` template field — create directories with `.mount-this` markers in `.booth/cache/`
  - Complementary to existing `cache-files` (which creates individual empty files)
  - Entire directory is mounted as a single bind mount into the container
- Claude Code settings cache — persist `~/.claude/` (settings, projects, memory) across sessions
  - New `settings-cache` extension (auto-selected) creates `.booth/cache/home/coder/.claude/`
  - Credential extension now mounts only `.credentials.json` via override path for fresh host credentials
  - Startup script simplified: credential seeding handled by booth-entry's `smart_copy`

## 0.35.0

- `booth build` command — build booth images and optionally push to a container registry
  - `--push <registry>` to build and push using `docker build` + `docker push`
  - `--name <name>` and `--tag <tag>` to customize the image reference
  - Content-based tagging: default tag is a 24-char SHA-256 hash of Boothfile + build-args + variant + version
  - Same configuration always produces the same tag for caching and reproducibility
  - Helpful error messages with `docker login` hints on authentication failures

## 0.32.0

- Modular startup scripts — `booth init` now generates individual files in `.booth/startups/` (e.g., `65-excalidraw-autostart--startup.sh`) instead of a single merged `startup.sh`
  - User-added `*--startup.sh` files in `startups/` survive `booth init adjust`
  - Files without a `NN-` prefix default to order 50
  - Container entrypoint sorts all startup scripts by order prefix
  - Legacy `.booth/startup.sh` still supported for backward compatibility
- `--env <KEY=VALUE>` flag — pass environment variables to the container via run-args (repeatable)
- `--mount <host:container>` flag — mount volumes into the container via run-args (repeatable)
- Excalidraw template — port parameterization with `+expose` and `+autostart` extensions

## 0.31.0

- OpenSSH template — client (`openssh`) and server (`openssh+server`) with expose and credential extensions

## 0.30.0

- Fix noVNC URL in desktop variants (XFCE, KDE, LXQT) to show the actual host port instead of hardcoded container port
- Port banner now displays when a non-default port is used, not just for auto-generated ports
- Package manager templates — variadic extensions for installing global packages via `booth init`:
  npm, yarn, pip, uv, conda, cargo, go, gem, cabal, hex, luarocks, pecl, bun, brew
  (e.g., `--select nodejs+npm-pkg:express,typescript`)
- Dependency pre-installation templates — pre-install project dependencies into the Docker image at build time:
  npm-install, yarn-install, pnpm-install, bun-install, bundle-install, cargo-build, go-mod,
  mix-deps, composer-install, mvn-install, gradle-deps
  (e.g., `--select nodejs+npm-install` reads `package.json` during build, restores `node_modules` at startup)
- New example workspaces: pip-deps-example, npm-deps-example, mvn-deps-example
- New init tests for package manager templates (test30–test39)
- New init tests for OpenSSH template (test40–test44)
- Documentation: Package Management Templates section in BOOTH_INIT.md

## 0.29.0

- Booth shutdown — gracefully stop the container from within
  - `booth--shutdown` command (sends SIGTERM to all user processes)
  - VS Code / code-server extension: "CodingBooth: Shut Down" command palette entry and status-bar button
  - Shutdown button in split-view ttyd web UI with confirmation dialog
  - Desktop variants (XFCE, KDE, LXQT) detect desktop logout and shut down cleanly
- `booth template list` now shows auto-select extensions with `*` marker instead of `(auto)` suffix
- Documentation overhaul — new standalone pages: How It Works, Lifecycle, Run, Init, Examples, Home, Setup, Variants, Sandbox implementation
- Simplified README with links to new doc pages
- Documentation images

## 0.28.0

- New templates: DBeaver, CloudBeaver (with autostart and expose extensions), PostgreSQL, Remotion
- `booth template cat <name>` — show the raw code/content of a template
- `booth install` stays put if already installed at the requested version
- Variant showcase in README — side-by-side screenshots of Base, Notebook, Code Server, XFCE, KDE, and Bash
- Sales Explorer demo — full-stack demo with PostgreSQL, Node.js server, and Jupyter notebook
- Fix Elixir setup script
- Improved `booth` wrapper script

## 0.27.0
- More templates
- `booth template cat <name>` — show the raw code/content of a template

## 0.26.0 (unreleased)

- `booth template` command — new top-level command replacing `init list` and `init search`
  - `booth template list` — compact listing with descriptions (hides auto-select extensions)
  - `booth template search <term>` — search by name, description, or tag
  - `booth template show <name>` — detailed view with parameters, extensions, requires, tags, and file changes
  - `booth template show <name>+<ext>` — show extension details (e.g. `python+uv`)
  - `booth template show <name> --detail` — show file and segment contents
  - `--full` flag to include non-primary templates in list/search
- `booth init --set <key=value>` — set arbitrary config.toml values from the CLI (bare key = boolean true)
- `booth init new` without `--select` — create an empty booth with only CLI overrides
- `--port` flag for `init new`/`dryrun` — set port directly in generated config.toml
- TLS support — self-signed certificate generation for HTTPS access
- Split-view ttyd — terminal split view mode
- Excalidraw template — collaborative whiteboard with autostart and expose extensions
- `.env` file support — load environment variables from `.booth/.env` at startup
- Template descriptions improved — all templates and extensions have better short and long descriptions
- Removed egress/network-whitelist configuration (simplified networking)

## 0.25.0

- Deno template with `pkg` extension for third-party module installation
- Fix `booth install` hang problem (#12)
- Fix Haskell and Deno template issues
- Fix for Windows compatibility
- Improved init security — resolver validates template dependencies
- Release version protection
- Refine templates, examples, and documentation

## 0.22.0

### Added
- `init adjust` subcommand — re-generate booth configuration (equivalent to `init new --overwrite`)
- `--version` flag for `init new`/`adjust`/`dryrun` — use templates from a specific release version
- `--overwrite` flag for `init new` — overwrite existing files without prompting
- Two-line generated file header: "Generated by" (exact command) and "Adjust with" (reformatted for easy editing with `--select` last)
- `init new` path is now optional (defaults to current directory)
- `init new` allows `.booth/` to already exist; prompts for confirmation only when individual files would be overwritten

### Changed
- `booth install` downloads only the current platform's binary (not all platforms)

## 0.21.0
- Booth init, run snake and CC auto accept.

## 0.20.0
- Init templates

## 0.19.0

### Added
- `codingbooth init` command for guided project initialization
  - `init new <path>` — generate `.booth/` configuration at a target path
  - `init dryrun` — preview generated output without writing files
  - `--select` DSL for template selection (inline, heredoc `-`, file `@recipe`, URL `@@url`)
  - `--start` flag to immediately start the booth after init
  - `--debug` flag to inspect resolved selection and compiled output
  - `--templates-path` for local template development
  - Selection summary printed after init (templates, extensions, parameters)
  - Recipe file support for reusable selection definitions
  - Whitespace-tolerant DSL: spaces around `+` and `+` continuation lines
- Init templates: go, python, java, claude-code
  - Go extensions: vscode-ext (auto), linter
  - Python extensions: vscode-ext (auto), uv, conda
  - Java extensions: vscode-ext (auto), maven, gradle, jenv
- `uv--install.sh` — install Python packages via uv
- Example recipes in `examples/recipes/`

### Notes
- Document that `--sandboxed` with `--dind` is **not supported** due to firewall bypass risk in the shared network namespace.

## v0.16.0
- Rename binary from `coding-booth` to `codingbooth`
- Booth example.

## v0.15.0

### Added
- Non-root package installation support -- previously only root was allowed to install packages.
    - Homebrew setup script (`homebrew--setup.sh`) for non-root package installation inside containers
    - Pip install helper script (`pip--install.sh`) for installing Python packages during image build
    - NPM install helper script (`npm--install.sh`) for installing Node.js packages during image build
    - Cargo install helper script (`cargo--install.sh`) for installing Rust packages during image build
    - Bun install helper script (`bun--install.sh`) for installing Bun packages during image build
    - RubyGems install helper script (`gem--install.sh`) for installing Ruby packages during image build
    - Deno install helper script (`deno--install.sh`) for installing Deno packages during image build

### Changed
- booth wrapper script now cache the binary per user
- booth is now location-based, meaning it operates relative to the script's own location (not the current directory) 
- booth will suggest booth function (shell-config command) that will searc upward from the current DIR until ./booth is found.

## v0.13.0
- Mess happens so don't have a coherent items, sorry :-p

## v0.12.0
- Rebrand fully to "CodingBooth"!!! Yeah!
- Command mode now silently forwards exit codes (no error message when commands fail)
- Add /etc/cb-home and /etc/cb-home-seed feature
- Add .booth/home and ~/.booth/home-seed feature
- Added `network-whitelist` setup for restricting container internet access to whitelisted domains

## v0.11.0
- Core engine rewritten in Go for portability (cross-platform: Linux, macOS, Windows)
- Repository restructured: `workspace/` → `variants/`, `ws` → `workspace`, CLI moved to `cli/`
- Home directory seeding via `/tmp/ws-home-seed/` for credentials
- Environment variable expansion in config.toml (`~`, `$VAR`, `${VAR}`)
- New examples: Neovim, AWS (with Jupyter notebook)
- Fixed: DinD support
- Windows compatibility, Python kernel in code-server, VNC issues
- Removed LXQT desktop variant

## v0.10.0
- Introduced the WorkSpace Wrapper (`ws`) - a stable bootstrapper script that:
  - Provides a stable entry point for using workspace
  - Automatically downloads, verifies, and launches the workspace tool
  - Handles SHA1 checksum verification for integrity
  - Supports version management and updates
- Improved build.sh - disabled signing, stopped creating bare latest/version tags
- Updated README introduction
- Reorganized release workflow

## v0.9.0
- Simplify conditional setups with CB_HAS_NOTEBOOK, CB_HAS_VSCODE and CB_HAS_DESKTOP
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
  - Prefixed all workspace-related environment variables with `CB_`.
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
