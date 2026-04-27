# CodingBooth Feature Split — Layers

The `booth` CLI spans four layers, in order of how the user encounters them:

- **Part A — Wrapper** (`booth` shell script): what the user touches *before* the tool is installed (install/update/cache, distribution).
- **Part B — Binary + Image** (`codingbooth` Go + variant Dockerfiles): what the user touches *once it's installed* — orchestration, lifecycle, scaffolding. The variant Dockerfiles live with the binary because the binary's build/run pipeline is what produces and launches them.
- **Part C — Setups** (in-container helper scripts and overlay assets under `variants/base/setups/`): runtime features the user encounters *inside* the container — `booth--*` commands, web overlay, message API, idle monitor, web proxy. They're baked into the image only because that's the convenient delivery vehicle; conceptually they're their own layer.
- **Part D — Contributor tooling**: repo-only scripts that exist for people hacking on CodingBooth itself; never shipped to users.

## Part A — Wrapper (`booth` shell script, ~1191 lines)

The wrapper's work splits three ways: things it does *about* the binary (without invoking it), things it does *for itself*, and the seam where it forwards everything else to the binary.

### A1 — Binary lifecycle management (manages the binary without calling it)

Resolves which `codingbooth` to run, fetches it, verifies it, and keeps the cache tidy. None of these subcommands hand control to the binary.

- `booth install [version]` (`--cache=shared|local`) — download + install the `codingbooth` binary (positional version arg)
- `booth update [version]` (`--cache=…`) — re-download to latest or specified version
- `booth uninstall` — remove project lock + local binaries
- `booth tools-cache list` / `tools-cache clean [--all|VERSION]` — inspect / prune the shared binary cache
- Cross-platform binary download (Linux/macOS/Windows × amd64/arm64) with sha256 verification
- Cache layout: shared (`~/.cache/codingbooth/`, `~/Library/Caches/…`, `%LOCALAPPDATA%\…`) vs local (`.booth/tools/`); selected per-install via `--cache`, recorded in lock file
- Lock file `.booth/tools/codingbooth.lock` (`version=`, `downloaded_at=`, `cache=`) — version-controlled, pins the binary
- `.booth/.gitignore` generation — written by `DownloadBooth` (so it lands during `install`/`update`); content varies with cache mode. **Cross-cutting**: only ~2 of 6 entries are binary-cache related (`tools/codingbooth-*`, `tools/*.sha256` in local mode); the rest (`.booth.password`, `.env`, `cache/`, `.tmp/`) are project-hygiene. Lives here because install/update is the wrapper's natural project-touching moment, but the artifact is also produced by the binary's init path — must stay in sync with `cli/src/pkg/boothinit/output/writer.go`. *[Note: shared concern, revisit if we ever extract project-hygiene as its own layer.]*
- Install bootstrap (`install.sh`) — standalone one-liner that fetches the wrapper itself

### A2 — Wrapper-self behavior (everything else the wrapper does on its own)

Bash-only behavior that doesn't touch the binary at all: help text, shell integration, invocation guards. All early-handled before the curl-required path so they work without network access.

- `booth help` — wrapper help (heredoc; does not invoke the binary)
- `booth shell-config [--force|--eval]` — emit / install a shell function that walks parents to find a project-local `booth`
- Wrapper runs relative to its own location, not cwd (so `/path/to/project/booth` works from anywhere)
- Nested-booth detection — only on `booth run`; warns when invoked inside an existing booth container

### A3 — Forwarding to the binary

Anything that isn't an A1 / A2 subcommand falls through to the run-mode path (`booth run` is also explicitly routed here). The wrapper does no parsing of the forwarded args — that's all Part B — but it does run a pre-exec integrity gauntlet first.

- Pre-exec checks on every forwarded invocation: read lock file → detect platform → locate binary in cache → auto-download if missing → verify binary SHA256 against `codingbooth.sha256` → maintain `booth` → `codingbooth-<platform>` symlink → `exec` the binary with original argv.
- `booth version` — the one self-command that also calls the binary: prints wrapper banner + `VERSION`, then shells out to `codingbooth version` and appends the result. Hybrid self/forward.
- All other invocations: `booth run`, `booth list`, `booth start`, `booth stop`, `booth config`, `booth build`, `booth message`, … → straight pass-through to `codingbooth` after the gauntlet.

## Part B — Binary + Image (`codingbooth` Go, ~88 .go files; variant Dockerfiles)

Everything the wrapper forwards to, plus the Docker images the binary builds and runs. The 5 variant Dockerfiles (`variants/*/Dockerfile`) belong here because the binary's `build` / `run` pipeline owns their lifecycle — the user picks a variant via a binary flag, never by hand-editing a Dockerfile.

### Run & run-mode flags

- `booth run` / default run — container orchestration
- Daemon / foreground / command modes (`--daemon`, `-- cmd`, exit-code forwarding)
- `--keep-alive`, `--writable-booth`, `--dind`, `--sandboxed`
- `--persist-home` + `home-volume-list` / `-export` / `-import`
- `--port` (explicit / NEXT / RANDOM), `-v` mounts, Docker pass-through via `run-args`
- `--dryrun`, `--verbose`, `--silence-build`, `--log-time` (+ `CB_LOG_TIME`)
- Config precedence: defaults → env (`CB_*`) → TOML → CLI flags
- UID/GID mapping, `coder` user, `.booth/` read-only mount
- Mounts host `booth` wrapper read-only into `/home/coder/code/booth` so in-container `booth --restart` resolves (`cli/src/pkg/booth/booth.go:517`)
- 5 variants (base / codeserver / notebook / desktop-xfce / desktop-kde) + terminal alias
- Label-based container management (`cb.*`)
- Booth-in-booth opt-in logic (binary-side)
- Friendly init-phase error messages

### Lifecycle & connect

- `list` / `start` / `stop` / `restart` / `remove` / `prune`
- `shell` / `exec` — attach to running booths
- Runtime session timers: `--show-run-time`, `--show-count-down`, `--count-down-exit-code`
- Idle auto-shutdown: `--idle-time`, `--idle-exit-code`

### Scaffolding & build

- `config` TUI (multi-tab, preview, `--no-tui`, `--select` DSL, `--env`/`--expose`/`--mount`, `--version`)
- Project init / scaffolding writes `.booth/.gitignore` via `cli/src/pkg/boothinit/output/writer.go`. *[Note: also written by the wrapper's `DownloadBooth` (see A1) — shared artifact, two writers must stay in sync. Revisit later.]*
- Selection DSL + 77+ templates, auto-select extensions, round-trip persistence
- TUI unwritable-`.booth/` warning, cycle-field edit mode
- `template list` / `help`
- `example list` / `try` (~45 workspaces)
- `build` / `build --push`
- Boothfile DSL parser + compiler → Dockerfile (skips setups the variant already provides)
- Template merge rules (segments 40/50/60/65/70/90)
- `emit-dockerfile`, `print-default-allowlist.txt`

### Messaging & runtime helpers

- `message send` / `list` / `response`
- Host-side TCP-tunnel watcher for `booth--expose` control files
- `.booth/.tmp/` lifecycle (wipe on start, clean on exit; `--leave-tmp-on-exit`, `--keep-tmp-on-start`)
- `booth-startup.txt` session metadata

## Part C — Setups (in-container surface)

The ~186 scripts under `variants/base/setups/` (plus per-variant overlays). They live inside the Docker image because that was the convenient delivery vehicle, but they're a distinct concern from the image itself: language toolchains, in-container helpers, daemons, the web overlay, the message API, the idle monitor. The binary enables/wires them via flags; the user only ever sees their effects.

- `booth--expose`, `booth--restart`, `booth--shutdown`, `booth--msg`, `booth--info`, `booth--envs`, `booth--idle-monitor`
- Web overlay, lifecycle panel, idle Pause/Disable chip, "Container stopped" page
- Web proxy pane (`/proxy/{port}/`)
- HTTP message API server, overlay JS/CSS, per-variant wrapper scripts
- Code-server extensions, Jupyter kernels, noVNC, desktop actions, `no-sudo`, Claude Code cache, `.mount-this` smart_copy, AGENT.md

## Part D — Contributor tooling (repo-only, not shipped)

Scripts and config that exist for people hacking on this repo. End users who install CodingBooth never see them.

- Onboarding (`on-board-me.sh`) — installs pre-commit hook enforcing `version.txt` ↔ `README.md` consistency
- `.githooks/pre-commit` — the hook itself
