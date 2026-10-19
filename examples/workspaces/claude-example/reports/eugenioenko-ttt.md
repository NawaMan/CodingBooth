# Vetting report: https://github.com/eugenioenko/ttt

Commit `d5a20b701d0cc7a20ef534133e4d8b9e0af87e5d`, vetted 2026-10-18.

## What it is
ttt is a terminal text editor written in Go (`github.com/eugenioenko/ttt`, `go.mod:1`). It renders with tcell and adds an integrated terminal, git and GitHub panels, LSP support, TextMate syntax highlighting, and a Lua plugin system. The code matches what the project says it is.

## How to build and run it
- From source: `make build` builds `bin/ttt` (`Makefile:12-13`, `README.md:81-85`). `make run` builds and then runs it (`Makefile:18-19`).
- Other install routes in the README: `go install github.com/eugenioenko/ttt/cmd/ttt@latest` (`README.md:68`), `nix run github:eugenioenko/ttt` (`README.md:46`), brew tap (`README.md:18-20`), and `curl … install.sh | sh` (`README.md:25`).
- Tests: `make test` runs `go test ./...` (`Makefile:15-16`). The JS test suites use `pnpm test` in `tests/functional` and `tests/integration`, and their scripts only call `vitest` (`tests/functional/package.json:6`, `tests/integration/package.json:6-8`).

## What runs automatically
- **Makefile default:** `all: build` (`Makefile:5`) only runs `go build`. `VERSION` runs `git describe` (`Makefile:7`).
- **npm/pnpm hooks:** none. No package.json has `preinstall`, `postinstall` or `prepare` (`tests/functional/package.json`, `tests/integration/package.json`, `docs-web/package.json`).
- **Go:** there is no `build.rs`/cgo-style hook. `go:generate` in `internal/fileicons/fileicons.go:5` only runs when you invoke it by hand. The `init()` functions are harmless: setting a profiler flag (`cmd/ttt/profiler.go:12`, only with `-tags profiler`), seeding an RNG (`internal/image/image.go:39`), and style registration (`internal/plugin/styles.go:67`).
- **Git hooks:** none in the repo (no `.githooks`, `.husky`, `.envrc`, `.vscode` or `.devcontainer`).
- **CI (runs on GitHub only, not on your machine):**
  - `ci.yml` runs vet, lint, tests, race tests, functional, integration and LSP tests, and a docs build. It also runs benchmarks and posts the results as a PR comment using `github.token` (`.github/workflows/ci.yml:216-229`). Its default permissions are `contents: read` (`:10-11`).
  - `release.yml` cross-compiles binaries and attaches them to a GitHub release (`.github/workflows/release.yml:29-48`).
  - `auto-update-Flake-hash.yml` recomputes the Nix `vendorHash` and opens a PR (`.github/workflows/auto-update-Flake-hash.yml:23-50`).
- **Optional scripts you would have to run yourself:**
  - `scripts/install-prerequisites.sh` installs ripgrep with sudo through your package manager (`:14-26`).
  - `tests/integration/lsp/*/install.sh` install language servers globally, e.g. `npm install -g` (`tests/integration/lsp/typescript/install.sh:5`), `sudo apt-get install clangd` (`tests/integration/lsp/c/install.sh:3`), and `go install gopls@latest` (`tests/integration/lsp/go/install.sh:3`).
  - `docs-web/demo/setup.sh` runs `rm -rf` on its target directories, which default to `/tmp/ttt-demo` and `/tmp/ttt-demo-cfg` (`:8-16`).

## Network and secrets
- **Outbound hosts:**
  - `api.github.com` and `github.com/.../releases` in the installer (`install.sh:32,40`).
  - The community plugin registry at `raw.githubusercontent.com/eugenioenko/ttt/main/community-plugins.json` (`internal/plugin/registry_remote.go:11,35`).
  - Plugin READMEs from `raw.githubusercontent.com` (`internal/app/plugin_detail.go:230-231`).
  - `gh` CLI calls for pull requests (`internal/github/github.go:52-136`).
  - Plugin installs clone with `git` (`internal/plugin/manager.go:328`).
- **Plugin network API:** Lua plugins can make HTTP GET and POST requests (`internal/app/plugin_api.go:571,598`). Private IP ranges are blocked (`:526-529`), and access is gated by the plugin permission model.
- **Local listener:** `--listen` binds a script-execution HTTP server to `127.0.0.1:4242`, or to `TTT_LISTEN_PORT`, and only when you pass the flag (`internal/app/listen.go:17-28,96-104`). Anything on localhost can drive the editor while it is running, so use it only when you need it.
- **Env vars read:**
  - `TTT_CONFIG_DIR` (`cmd/ttt/main.go:201`), `XDG_CONFIG_HOME` (`internal/workspace/places.go:137`), `RUNEWIDTH_EASTASIAN` (`internal/textwidth/textwidth.go:21`).
  - `SHELL` and `COMSPEC` to choose the terminal shell (`internal/terminal/terminal.go:116-121`).
  - `DISPLAY` and `WAYLAND_DISPLAY` for the clipboard (`internal/core/clipboard/clipboard.go:76-101`).
  - Plugins can read any env var through `Env` (`internal/app/plugin_api.go:509-511`), subject to plugin permissions.
- **Credentials:** no code reads `~/.ssh`, `~/.aws`, browser data or crypto wallets (a grep for these paths and keywords found only test fixtures). The only `core.sshCommand` reference is in a blocklist that stops plugins injecting it (`internal/app/plugin_api.go:459`).

## Red flags
None found.
- No obfuscated code, and no eval of fetched code. `base64` is used only for the OSC 52 clipboard and Kitty image encoding (`internal/core/clipboard/clipboard.go:49`, `internal/image/kitty.go:25`).
- No bundled binaries or archives in the tree.
- There are two `curl | sh` patterns. Both are the project's documented installer fetching its own GitHub releases, which is normal but means you trust that repo and its releases (`README.md:25`, `herdr-plugin/scripts/install.sh:10`).
- `install.sh` may use `sudo mv` into `/usr/local/bin` on macOS (`install.sh:59-60`). It also removes the macOS quarantine attribute from the downloaded binary (`install.sh:51`), which is standard for unsigned CLI tools but skips Gatekeeper.
- `AGENTS.md` and `README.md:425` address AI agents, but only with contributor and debugging guidance. Nothing in them tries to steer an agent into harmful actions.

## Verdict
**LOOKS FINE.** The build only compiles Go code, and nothing runs on install. Network access is limited to the project's own GitHub endpoints and features you trigger yourself (plugin registry, `gh`, LSP). I found no attempts to read credentials and no hidden behaviour. Two things to keep in mind:
- Third-party Lua plugins can be granted exec, network and env access, so check what permissions a plugin asks for before installing it.
- The `--listen` debug server should only be enabled when you need it.
