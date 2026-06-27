# CodingBooth Feature Split — Layers

The `booth` CLI spans these layers, ordered roughly by where they sit in the user's stack — wrapper → binary → image → in-container surface:

- **Part A — Wrapper** (`booth` shell script): what the user touches *before* the tool is installed (install/update/cache, distribution).
- **Part B — Binary + Image** (`codingbooth` Go + variant Dockerfiles): what the user touches *once it's installed* — orchestration, lifecycle, scaffolding. The variant Dockerfiles live with the binary because the binary's build/run pipeline is what produces and launches them.
- **Part C — Setups** (build-time install scripts under `variants/base/setups/`): the install layer baked into the image — language toolchains, IDE extensions, kernels, AI tools, etc.
- **Part D — In-container CLI helpers** (`booth--*` commands): user-facing scripts invoked from a terminal inside the running booth.
- **Part E — In-container daemons**: always-on background services inside the booth — idle monitor, timer notifier, lifecycle watcher, HTTP message API server.
- **Part F — Web UI** (overlay, lifecycle panel, proxy pane, nginx + index.html): browser-rendered presentation surface for the web variants.
- **Part G — Contributor tooling**: repo-only scripts that exist for people hacking on CodingBooth itself; never shipped to users.

## Part A — Wrapper (`booth` shell script, ~1191 lines)

The wrapper's work splits three ways: things it does *about* the binary (without invoking it), things it does *for itself*, and the seam where it forwards everything else to the binary.

### A1 — Lifecycle

The lifecycle of the wrapper and the binary, all from the wrapper side: lands the wrapper itself (install.sh), then resolves which `codingbooth` to run, fetches it, verifies it, pins it, and keeps the cache tidy. None of these subcommands hand control to the binary.

- Install bootstrap (`install.sh`) — standalone one-liner that fetches the wrapper itself
- `booth install [version]` (`--cache=shared|local`) — download + install the `codingbooth` binary (positional version arg)
- `booth update [version]` (`--cache=…`) — re-download to latest or specified version
- `booth uninstall` — remove project lock + local binaries
- `booth tools-cache list` / `tools-cache clean [--all|VERSION]` — inspect / prune the shared binary cache
- Cross-platform binary download (Linux/macOS/Windows × amd64/arm64) with sha256 verification
- Cache layout: shared (`~/.cache/codingbooth/`, `~/Library/Caches/…`, `%LOCALAPPDATA%\…`) vs local (`.booth/tools/`); selected per-install via `--cache`, recorded in lock file
- Lock file `.booth/tools/codingbooth.lock` (`version=`, `downloaded_at=`, `cache=`) — version-controlled, pins the binary

### A2 — Wrapper-self behavior (everything else the wrapper does on its own)

Bash-only behavior that doesn't touch the binary at all: help text and invocation guards. All early-handled before the curl-required path so they work without network access.

- `booth help` — wrapper help (heredoc; does not invoke the binary)
- `booth version` (wrapper-self half) — prints wrapper banner + `VERSION` constant; runs without network or binary. *Also listed in A3 (forward half).*
- Wrapper runs relative to its own location, not cwd (so `/path/to/project/booth` works from anywhere)
- Nested-booth detection — only on `booth run`; warns when invoked inside an existing booth container

### A3 — Forwarding to the binary

Anything that isn't an A1 / A2 subcommand falls through to the run-mode path (`booth run` is also explicitly routed here). The wrapper does no parsing of the forwarded args — that's all Part B — but it does run a pre-exec integrity gauntlet first.

- Pre-exec checks on every forwarded invocation: read lock file → detect platform → locate binary in cache → auto-download if missing → verify binary SHA256 against `codingbooth.sha256` → maintain `booth` → `codingbooth-<platform>` symlink → `exec` the binary with original argv.
- `booth version` (forward half) — shells out to `codingbooth version` and appends to the wrapper banner already printed. *Also listed in A2 (wrapper-self half).*
- All other invocations: `booth run`, `booth list`, `booth start`, `booth stop`, `booth config`, `booth build`, `booth message`, … → straight pass-through to `codingbooth` after the gauntlet.

## Part B — Binary + Image (`codingbooth` Go, ~88 .go files; variant Dockerfiles)

Everything the wrapper forwards to, plus the Docker images the binary builds and runs. The 5 variant Dockerfiles (`variants/*/Dockerfile`) belong here because the binary's `build` / `run` pipeline owns their lifecycle — the user picks a variant via a binary flag, never by hand-editing a Dockerfile.

This is a wide skeleton; each section gets fleshed out separately. Cross-cuts are marked with arrows; **carriers** (single artifacts whose contents fan out into many sections) are flagged.

### B1 — Run

Configure → launch a container. The default verb of the binary; everything else either supports this or operates on its results.

- **B1a — Start**: `booth run` / default; daemon / foreground / command modes (`--daemon`, `-- cmd`); `--keep-alive`; exit-code forwarding
- **B1b — User permission**: UID/GID mapping; `coder` user with passwordless sudo; `.booth/` read-only mount; `--writable-booth`; `no-sudo` template
- **B1c — Variant selection**: 5 variants (base / codeserver / notebook / desktop-xfce / desktop-kde) + terminal alias; friendly init-phase error messages
- **B1d — Config inputs**: precedence defaults → env (`CB_*`) → TOML → CLI; consumes *Boothfile* and *Template* (see Carriers)
- **B1e — Mounts**: `-v`; Docker pass-through via `run-args`; host wrapper read-only mount into `/home/coder/code/booth` (`cli/src/pkg/booth/booth.go:517`)
- **B1f — Ports**: `--port` (explicit / NEXT / RANDOM)
- **B1g — Labels**: `cb.managed` / `cb.project` / `cb.variant` / `cb.role` / `cb.parent`
- **B1h — Logging/debug**: `--dryrun`, `--verbose`, `--silence-build`, `--log-time` (+ `CB_LOG_TIME`)
- **B1i — Run modes**: `--dind` (sidecar), `--egress` (Envoy + iptables egress filter), booth-in-booth detection + opt-in
- **B1j — Home**: `--persist-home` (Docker named volume); `home-volume list` / `-export` / `-import`; smart_copy seeding via *Template* `files.home` / `files.home-seed`
- **B1k — Cache**: `.booth/cache/` host mirror with auto-bind-mounts; smart_copy + `.mount-this` markers; `cache-files` / `cache-dirs` declared via *Template*; Claude Code `~/.claude/` cache persistence
- **B1l — Container environment**: env vars that land inside the running booth as regular `$FOO`. Sources: `.booth/.env` (auto-loaded, **gitignore-enforced** via `git check-ignore` — refuses to run otherwise), explicit `--env-file` (CLI / config; `-` sentinel disables), `-e` in `run-args`, `booth config --env`. Layering: `.booth/.env` first, explicit env-file second (overrides on conflict)

### B2 — Lifecycle

Manage running booths from outside the container.

- **B2a — Container CRUD**: `list` / `start` / `stop` / `restart` / `remove` / `prune`
- **B2b — Session timers**: `--show-run-time`, `--show-count-down`, `--count-down-exit-code` (binary-side; UI in Part C)
- **B2c — Idle auto-shutdown**: `--idle-time <s>[,t]`, `--idle-exit-code` (binary-side; Pause/Disable chip in Part C)

### B3 — Build

Construct an image. Overlaps B1 when `booth run` triggers build-when-image-missing.

- **B3a — Build commands**: `booth build`, `booth build --push`
- **B3b — Boothfile** [carrier]: DSL parser + compiler → Dockerfile; skips setups the variant already provides. *Cross-listed: B1d (run input), B4b (Template emits Boothfile segments).*
- **B3c — Build cache**: build hash; image-cache reuse
- **B3d — Diagnostic emitters**: `emit-dockerfile`, `print-default-allowlist.txt`

### B4 — Scaffolding

Generate `.booth/` from templates.

- **B4a — Config TUI**: multi-tab layout, preview, `--no-tui`, `--select` DSL, `--env` / `--expose` / `--mount` / `--version`; cycle-field edit mode; warns when `.booth/` is unwritable
- **B4b — Template** [carrier]: selection DSL (`go:1.25+linter/python:3.13`), 77+ templates across categories, extensions (auto-select vs explicit), merge rules (segment 40/50/60/65/70/90, scalar match-or-error, array dedup with paired-flag awareness); `template list` / `help`. *Emits into: B3 (Boothfile segments), B1d (config scalars/arrays), B1j (home seeding), B1k (cache files/dirs), B1a (startup segments → `.booth/startups/NN-name--startup.sh`).*
- **B4c — Recipe**: `.recipe` file format (multiline, `+` continuation); `@file` / `@@url` / stdin loaders. Wraps B4b's DSL
- **B4d — Example**: `booth example list` / `try` (~45 workspaces)
- **B4e — `.booth/.gitignore` writer**: scaffolding writes `.booth/.gitignore` via `cli/src/pkg/boothinit/output/writer.go`. *[Note: also written by the wrapper's `DownloadBooth` (A1) — shared artifact, two writers must stay in sync. Tracked as a `.booth/` directory cross-cut; revisit.]*

### B5 — Connect

Attach to a running booth without SSH.

- `booth shell` / `booth exec`

### B6 — Host-side runtime support

Binary-side helpers that run while a booth is live; pair with Part C in-container counterparts.

- **B6a — Messaging CLI**: `booth message send` / `list` / `response` / `adjust`. Host half of the Part C overlay/server stack.
- **B6b — TCP tunnel watcher** (`pkg/booth/tcp_tunnel.go`): host counterpart of in-container `booth--expose` control-file protocol
- **B6c — `.booth/.tmp/` lifecycle**: wipe on start, clean on exit; `--leave-tmp-on-exit`, `--keep-tmp-on-start`
- **B6d — Session metadata**: `booth-startup.txt` per-session file

### Carriers (cross-cut nodes)

Files/abstractions that bundle configuration for one section but get consumed by many. Listed where they're parsed/emitted; cross-listed at every consumer.

- **Boothfile** — primary B3b; consumed by B1d (run), B4b (Template emits Boothfile segments)
- **`.booth/config.toml`** — primary B4a (TUI reads/writes); consumed by B1d (run input, in precedence chain); receives scalar/array values emitted by B4b (Template `dind`, `run-args`, `build-args`, etc.)
- **Template** — primary B4b; emits into B3 (Boothfile), B1d (config), B1j (home seeding), B1k (cache), B1a (startups)
- **Recipe** — primary B4c; wraps B4b's DSL
- *(`.booth/` directory itself is cross-cut between A1 (wrapper writes `.gitignore`), B4e (scaffolding writes most contents), B1 (mounts read-only at run time). Tracked as a separate directory-level concern.)*

## Part C — Setups (build-time install layer)

The ~186 build-time scripts under `variants/base/setups/` plus per-variant overlays. Each runs once during `docker build`, as root, producing up to three runtime artifacts (startup script, profile script, starter wrapper) per the documented setup pattern. They make a CodingBooth variant *be* what it is.

- **Language toolchains** (`*--setup.sh`): bun, cabal, cargo, clojure, conan, go, gradle, java/jdk, kotlin, lua, nodejs, php, python, ruby, rust, sbt, scala, …
- **Package install** (`*--install.sh`): pip, uv, conda, npm, yarn, bun, deno, go, cargo, gem, brew, cabal, hex, luarocks, pecl, conan
- **Cloud CLIs**: aws-cli, aws-cdk, aws-sam-cli, azure-cli, gcloud, firebase
- **IDE / editor**: codeserver, bluej, neovim
- **AI tools**: claude-code, codex, aider, cursor, gh-copilot, ollama, antigravity, warp; AGENT.md + symlink farm (CLAUDE.md, COPILOT.md, CURSOR.md, …)
- **Browsers / databases / build tools**: chromium-browser; cloudbeaver; cmake
- **Code-server extensions** (`*-code-extension--setup.sh`): bash, bun, clojure, codex, booth-message, booth-restart, booth-shutdown, …
- **Notebook kernels** (`*-nb-kernel--setup.sh`): bash, …
- **Desktop bits**: noVNC, XFCE/KDE wallpaper branding, `cb-has-desktop*.sh`
- **Hardening / cleanup**: `no-sudo`, `cleanup-after--setup.sh`, `tls--setup.sh` (pinned Caddy)
- **Base toolset** (variant base Dockerfile): bash/zsh/tini, curl/wget/httpie, git/gh/tig, nano/tilde/ranger/less, jq/yq/tree, unzip/zip/xz, ca-certificates/locales/sudo, socat
- **Three-artifact pattern**: each setup may install a *startup* script (`/usr/share/startup.d/<LEVEL>-cb-<name>--startup.sh`, runs as `coder` on container start, idempotent), a *profile* script (`/etc/profile.d/<LEVEL>-cb-<name>--profile.sh`, runs on every shell), and/or a *starter* wrapper (`/usr/local/bin/<name>`)
- **LEVEL ordering**: 50–54 base, 55–59 OS/UI, 60–64 languages, 65–69 language extensions, 70–74 dev tools, 75–79 tool extensions
- **Image-side cache seeding**: smart_copy + `.mount-this` markers (counterpart of B1k)

## Part D — In-container CLI helpers

Bash scripts the user invokes from a terminal inside the running booth. Each shells back to the host (or talks to the message API server in Part E) to do its work.

- **`booth--expose [port]`** — request a runtime TCP tunnel host↔container. Writes a control file in `.booth/.tmp/`; B6b watcher (host side) sets up socat. `--permanent` persists into config.
- **`booth--restart`** — write a restart message; `booth-lifecycle-watcher` (E) acts on it. `--yes` skips confirmation. Rebuilds image if needed; preserves CLI args.
- **`booth--shutdown`** — same pattern, ends the booth.
- **`booth--msg`** (`list` / `send` / `dismiss`) — terminal UI for the messaging system (replaces the missing overlay in base variant).
- **`booth--info`** — print booth identity and runtime info.
- **`booth--envs`** — print container env vars (paired with B1l container environment).

## Part E — In-container daemons

Always-on background services inside the booth, started by the variant's entry scripts. They run in addition to the user-typed helpers in Part D.

- **`booth--idle-monitor`** — detects activity from the web UI (F) via the message API; signals idle state; persists Pause/Disable state to `.booth/.tmp/` for B2c to honor.
- **`booth-timer-notifier`** — surfaces session timer events (count-down warnings) into the web UI via the message API.
- **`booth-lifecycle-watcher`** — watches messages in `.booth/.tmp/` for restart/shutdown actions and executes them inside the container.
- **HTTP message API server** (`booth-message-api-server`, bash + socat at `/booth-messages/api/`) — protocol bridge between the web UI (F) and message files in `.booth/.tmp/`.

## Part F — Web UI

Browser-rendered presentation surface served by the booth's web variants. Reaches into B and E via the message system.

- **Web overlay** (`booth-message-overlay.html`, JS/CSS) — modal / toast / banner message primitives; consumes the message API (E)
- **Lifecycle panel** — Restart / Shut Down buttons, timer display, idle chip; calls back via the message system to E and B
- **Idle Pause/Disable chip** — sectioned dialog with change-base-timeout inline; activity detection (throttled keyboard/mouse events) feeds the idle daemon
- **"Container stopped" page** — across all web variants (including console since v0.42)
- **Web proxy pane** (`/proxy/{port}/`) — nginx `sub_filter` + iframe toggle in console UI; X-Frame-Options / CSP stripped; open-in-new-tab button
- **Console UI** — `index.html` in `web-ttyd-split/`: terminal split view + overlay + proxy toggle
- **Nginx config** — `web-ttyd-split/nginx.conf.template`
- **Per-variant wrapper integration** (`booth-message-wrapper--setup.sh`, `booth-message-{codeserver,notebook,desktop}-wrapped--setup.sh`) — these are setup scripts (cross-cut with Part C) whose *role* is wiring the overlay into each variant's UI
- **Shutdown / restart confirmation dialogs** — zenity/kdialog (desktop) + web overlay (web variants)

## Part G — Contributor tooling (repo-only, not shipped)

Scripts and config that exist for people hacking on this repo. End users who install CodingBooth never see them.

- Onboarding (`on-board-me.sh`) — installs pre-commit hook enforcing `version.txt` ↔ `README.md` consistency
- `.githooks/pre-commit` — the hook itself
