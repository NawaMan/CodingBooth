# Changelog

This file contains a list of changes for each released version.

## 0.58.0

- **`shell` and `exec` can bring up a non-running booth with `--run`.** By default `booth shell` and `booth exec` require the target booth to already be running. Passing `--run` makes the booth available first and then connects — so you can jump straight into a booth from its workspace without a separate launch step.
  - It does whatever is needed: an already-running booth is used as-is; a stopped container (e.g. a `--keep-alive` booth) is started; and when **no container exists** — the common case, since stopping a normal booth removes it — a new one is created from the workspace with `booth run` in daemon mode.
  - A booth that `--run` brought up does not outlive the session: when you disconnect it is returned to its prior state (a created booth is removed, a stopped `--keep-alive` booth goes back to stopped, an already-running booth is left untouched). Pass `--keep-alive` to leave it running instead — which also creates it as a keep-alive booth so it survives a later `booth stop`. Interrupting with Ctrl+C still tears it down.
  - Concurrent `--run` sessions on the same booth are reference-counted (tracked under `/run/booth-run/` inside the container): the booth is only brought down when the **last** session disconnects, so one session exiting never kills another's still-attached booth. `--keep-alive` from any session promotes the booth to persistent.
  - Opt-in by design: without `--run`, a non-running booth stays an error, which keeps `booth exec` predictable in scripts and CI. The booth's startup output goes to stderr so `exec`'s forwarded stdout stays clean, and `shell`/`exec` wait for the container's `coder` user alignment to finish before connecting so the first command never races startup. New unit tests cover the resolve/start/run decisions, and `tests/manual/run-shell-run-manual-test.sh` exercises the real Docker path (run-from-scratch, keep-alive, start-stopped, and concurrent sessions). See `docs/BOOTH_CONNECT.md`.

## 0.57.0

- **Egress filtering — restrict a booth's outbound network to an allowlist of domains.** `--egress` (or `egress = true` in `.booth/config.toml`) routes the container's HTTP/HTTPS traffic through an Envoy forward-proxy sidecar with a domain allowlist, backed by iptables rules that drop any direct egress — a defense-in-depth layer for running third-party AI agents or untrusted dependencies that bounds where they can connect.
  - Configure the allowlist with `--egress-allowlist-file` (one domain per line; subdomains and ports are matched automatically), `--egress-allowlist` (extra inline domains merged on top), or `--egress-policy-file` (a full custom Envoy config for advanced rules). With none set, a comprehensive built-in allowlist covering common dev services (source control, package managers, registries, CDNs, cloud, AI services) is used.
  - Not supported together with `--dind` — privileged containers can bypass the firewall in the shared network namespace. New example workspaces `egress-envoy-example` and `egress-allowlist-extra-example`; complex tests under `tests/complex/test-egress-*`. See `docs/implementations/EGRESS.md`.
- **Config TUI edits package lists as multi-row fields.** Package-list parameters that accept multiple values — `apt-pkg`, `npm-pkg`, `pip-pkg`, `cargo-pkg`, `go-pkg`, `gem-pkg`, and the other `*-pkg` / install extensions — are now edited one row per package in the right panel (the same style as the Expose / Env / Mount fields on the Config tab) instead of as a single comma-joined string.
  - `↑`/`↓` move between rows; `Space`/`Enter` on **(+ add)** adds a package; `Space`/`Enter` on a package edits it; `Delete`/`Backspace` removes it; `Esc` returns to the template list.
  - Each package is stored as its own entry and compiled into a single install step (e.g. `install apt htop jq`) — equivalent to the CLI form `--select apt-pkg:htop,jq`. On save the list is deduplicated and sorted into a canonical form so the generated Boothfile is stable regardless of entry order. See `docs/BOOTH_CONFIG_TUI.md`.
- **`apt-pkg` config extension for system packages.** Debian/Ubuntu packages can now be selected through `booth config` (CLI `apt-pkg:htop,jq` or the TUI) instead of only hand-edited into the Boothfile. Supports apt's native `pkg=version` pinning and honors the `APT_SNAPSHOT` archive freeze that `booth config` stamps for reproducible builds. See `docs/BOOTH_CONFIG.md`.
- **`deno/tool` config extension** installs global Deno CLI tools via `deno install` (e.g. `deno+tool:npm:cowsay`), alongside the existing `deno/pkg` extension.
- New config-tui test suite under `tests/config-tui/` (13 scripted TUI scenarios plus shared helpers and a runner), and `install` integration tests covering every package manager under `tests/complex/test-install-*` (apt, brew, bun, cabal, cargo, conan, conda, deno, deno-pkg, gem, go, hex, luarocks, npm, pecl, pip, uv, yarn). New config tests verify each install manager has a selector extension (`test64-all-installs-have-selector`).

## 0.56.0

- **New `install apt` manager — install Debian/Ubuntu system packages from a Boothfile.** `install apt <pkg>[=<version>]` compiles to `RUN apt--install.sh ...`, alongside the existing language package managers (`install pip`, `install npm`, …). Version pins use apt's native `pkg=version` syntax. The `apt` manager auto-registers from `variants/base/setups/apt--install.sh` — no separate allowlist.
  - **Reproducible by archive snapshot.** `apt--install.sh` honors an `APT_SNAPSHOT` env var (a UTC `YYYYMMDDTHHMMSSZ` id) and passes `--snapshot` to apt, freezing the whole resolution — transitive dependencies included — to that day's Ubuntu archive (base image is Ubuntu 24.04, where `--snapshot` is auto-supported). With no `APT_SNAPSHOT`, apt resolves against the live archive as usual.
  - **`booth config` stamps the date.** Generated Boothfiles get an `env APT_SNAPSHOT=<configuration date>` line (UTC, day granularity) so rebuilds stay frozen until the next `booth config`. `CB_APT_SNAPSHOT` overrides the stamped value. See `docs/REPRODUCIBILITY.md` and `docs/BOOTH_INSTALL_APT.md`.
  - New `apt-example` workspace demonstrates `install apt` + the snapshot freeze; `clang-example` now pulls the header-only `nlohmann/json` C++ library via `install apt`. Complex tests `test-boothfile-apt` and `test-boothfile-apt-snapshot` cover both modes.

## 0.54.0

- **Native multi-arch image builds — published images are no longer cross-built under QEMU.** Each architecture is now built on a runner of that architecture, eliminating the emulation that silently broke build-time steps on the non-native arch.
  - The publish pipeline previously ran a single `buildx --platform linux/amd64,linux/arm64` on one amd64 runner, so the arm64 image was assembled under QEMU. `code-server --install-extension` fails under emulation (`Invalid ELF image`), so the codeserver build *skipped* baking its VS Code extensions (and the `.extensions-installed` marker) into the arm64 image, deferring the install to first launch on every Apple-Silicon run.
  - `docker-build.sh` gains `--arch <amd64|arm64>` (build one arch natively, push by digest) and `--merge` (assemble the per-arch digests into the multi-arch tags with `docker buildx imagetools create`, then cosign-sign). The legacy single-runner `--push` path is kept for local/standalone builds.
  - `publish-docker-images.yaml` is restructured into native per-arch matrix jobs (`ubuntu-24.04` + `ubuntu-24.04-arm`) feeding `merge` jobs: `build-base → merge-base → build-variants → merge-variants → integration-tests`. Per-arch digests pass between jobs as artifacts.
- **Fix codeserver crash on hosts whose user is not UID 1000 (e.g. macOS, where the first user is 501).** The launcher aborted with `touch: cannot touch '/usr/local/share/code-server/.extensions-installed': Permission denied`.
  - `/usr/local/share/code-server` was created at build time owned by the build-time `coder` user (UID 1000) and was not writable by other UIDs. At runtime `booth-entry` remaps `coder` to the host user's UID/GID, so the marker `touch` only succeeded when the host happened to be UID 1000 — i.e. on most Linux hosts but not on macOS. It surfaced together with the QEMU bug above, because the emulated-arch image always took the runtime (deferred) install path.
  - The shared dir is now `chmod 1777` (sticky bit, like `/tmp`) at build time so any remapped runtime UID can write the marker, and the runtime `touch "$MARKER"` is guarded with `2>/dev/null || true` so a missing optimization marker can never abort the launcher under `set -e`.
- **Removed `booth shell-config` and the host-side `booth()` shell function.** Earlier versions of the wrapper shipped a `shell-config` subcommand that wrote a `booth()` one-liner into `~/.bashrc`, `~/.zshrc`, `~/.bash_profile`, and `~/.profile`, letting users type `booth` from any subdirectory of a project. The subcommand, the function it managed, the version-marker bump mechanism, the rc-file cleanup logic, and the `--shell-config` uninstall scope are all gone. Users now always invoke `./booth` by path, or hand-write their own three-line walk-up shell function if they want a shortcut. `install.sh` and the wrapper's pipe-install bootstrap no longer touch rc files.
- Wrapper trimmed from ~1450 to ~990 lines: legacy v1–v4 rc-file cleanup awk, the `update-wrapper` subcommand, the `ALL_PLATFORMS` uninstall loop, multi-platform sha-file plumbing, and other defensive code for states the wrapper never produced are all removed.
- `booth uninstall` gets scope flags for incremental removal
  - `booth uninstall` (no flags) keeps current behavior — removes only the project binary association (`.booth/tools/` lock + sha + project-local binaries)
  - `--shared-binary` — also remove the shared-cache binary pinned by this project's lock file (`~/.cache/codingbooth/versions/<v>/`)
  - `--all-shared-binary` — also remove every version in the shared cache
  - `--wrapper` — also delete the `./booth` wrapper itself (safe self-delete on Linux/macOS)
  - `--all` — composite shorthand: shared cache (all versions) + wrapper
  - `-y` / `--yes` — skip the single all-in-one confirmation prompt; required when stdin isn't a TTY
  - All scopes compose; one prompt summarises everything before any removal happens
- `booth install` outside a project bootstraps the wrapper in the current directory
  - Running `booth` from a folder with no booth wrapper in the directory tree previously errored with a "wrapper not found" message and required the user to copy-paste a `curl ... | bash` command from the message — a natural next attempt (`booth install`) was rejected the same way
  - `booth install` now prompts "install the booth wrapper here?" then (after the wrapper lands) "install the binary now?" — two explicit confirmations, no implicit network fetch
  - `booth install -y` skips both prompts and runs `https://codingbooth.io/install.sh | bash` directly (wrapper + binary)
  - Refuses to clobber if a non-executable file named `booth` already exists in the current directory; refuses to prompt if stdin isn't a TTY (must use `-y`)
- Bash-like variable expansion for `.booth/.env`, `config.toml`, and `CB_*` env vars (see `docs/BOOTH_VARS.md`)
  - `$VAR`, `${VAR}`, `${VAR:-default}`, `${VAR:?required-message}`, leading `~`, `\$` / `\\` / `\"` / `\~` escapes, and bash-style `"..."` (expanding) / `'...'` (literal) quoting are now resolved by booth before the value reaches docker
  - `.booth/.env` and `--env-file <path>`: booth now parses the file, expands each value (earlier lines visible to later ones, falling through to host env), and hands docker a `0600` expanded copy under `.booth/.tmp/`. Docker's `--env-file` does not substitute `$VAR` or `~` natively, so without this the values were reaching the container literally
  - `${VAR:?msg}` aborts booth with a source-located error (e.g. `.booth/.env:12: required for app boot`) before any container is started, instead of producing a silent empty value
  - CLI `-e KEY=VAL` / `--env KEY=VAL` is intentionally unchanged: the invoking shell has already done its expansion, so booth does not double-expand
  - The previous `os.ExpandEnv`-based expansion (no quotes, no defaults, no errors) is replaced by `pkg/shellexpand`; existing simple `$VAR` / `~` usages keep working unchanged
- Fix UI lockup when a message title or body contains multibyte characters (em-dash, accented letters, CJK, emoji)
  - `booth-message-api-server` was setting HTTP `Content-Length` from bash's `${#body}`, which counts characters (not bytes) in a UTF-8 locale — an em-dash is 1 char / 3 bytes, so every response containing one was truncated and the browser failed to parse the JSON
  - The polling failure then triggered the lifecycle overlay's "Container stopped" guard, blanking the entire console even though the container was healthy
  - `send_response` now sends the byte count via `wc -c`
- Booth message overlay tolerates transient poll failures instead of locking the UI
  - "Container stopped" fullscreen previously fired on a single failed `/booth-messages/api/list` poll with no recovery path, even when subsequent polls succeeded
  - Threshold raised from 1 to 3 consecutive failures (~6 s at the 2 s poll interval) and the overlay auto-hides when polls resume
  - Recovery is scoped via a `data-poll-driven` marker so a deliberately-shown fullscreen (user-confirmed shutdown, `BoothPanel.showStopped`) is never auto-hidden
- ttyd terminal panes auto-reconnect on transient websocket drops
  - `start-ttyd-split` and `start-ttyd` now pass `-r 5` so the ttyd client retries every 5 seconds after a drop
  - Previously a backgrounded tab or idle timeout left a frozen pane until manual reload; the bash session inside the container survives the drop, so the reconnected ws picks up the same shell
- Pin Caddy install in `tls--setup.sh` to GitHub releases
  - `caddyserver.com/api/download` was unreachable during a build and — because the `curl` had no timeout — the `tls--setup.sh` step hung for 40+ minutes before being noticed
  - Switched to `https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_${CADDY_ARCH}.tar.gz` with `CADDY_VERSION=2.11.2` pinned, `--connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5` so failures surface fast, and a tarball extract instead of a raw binary download
- Idle-timer Pause and Disable controls in the web overlay
  - Persistent `Idle:` chip in the lifecycle panel whenever `--idle-time` is armed, in three visual states: `Idle: 15m` (green, normal), `Idle: PAUSE 1h 42m` (blue, time-boxed hold with live countdown), `Idle: DISABLED` (red, pulsing — indefinite hold)
  - **Pause** = time-boxed hold that auto-resumes to normal cadence. **Disable** = indefinite hold; only cleared by Resume or a restart
  - Click the chip for a sectioned "Idle shutdown" dialog: header + description ("shuts down after X minutes... so an idle run doesn't rack up unexpected costs"), then three divider-separated sections — "Hold off for a while" (time-boxed Pause with minute input defaulted to 60), "Turn it off entirely" with danger-styled Disable button (or "Back to normal" with Resume button when already paused/disabled), and "Got it, carry on" with Close
  - Timeout "Still using this booth?" prompt shares the sectioned layout with the chip dialog — same "Hold off for a while" (Pause) + "Turn it off entirely" (Disable) sections, plus an "I'm still here" section in place of "Got it, carry on". Header shows a **live countdown** driven by the message's `expires` timestamp
  - Monitor↔overlay protocol uses semantic answer codes (`ok`, `pause:<seconds>`, `disable`) so custom-minute pauses flow through the same channel as presets
  - New API endpoints under `/booth-messages/api/idle/`: `state` (GET — returns `{enabled, idle_time, base_idle_time, shutdown_time, disabled, pause_until}`), `pause` (POST `{"seconds":N}`, capped 7d), `disable` (POST), `resume` (POST), `set-time` (POST `{"seconds":N}` — override base idle time for this session; cleared on restart)
  - "Change the timeout" section in both the chip dialog and the timeout prompt: input the new base in minutes + Apply. Monitor re-reads the effective base each loop tick so changes take effect within ~10 s
  - State persisted as ephemeral files under `.booth/.tmp/` (`.idle-disabled`, `.idle-pause-until`, `.idle-base-override`); container restart always returns to normal cadence
- Boothfile compiler skips `setup` steps the chosen variant already provides
  - `setup notebook` with `--variant notebook` (and `setup codeserver` with `--variant codeserver`) used to be re-executed on top of the variant base image, paying a full JupyterLab / code-server reinstall for nothing
  - The compiler now emits a `# skipped: ...` comment in the generated Dockerfile and a warning naming the redundant step; non-variant setups (e.g. `setup codeserver` under `--variant notebook`) still run
  - Wired through `CompilerOptions.Variant`, populated from the resolved variant at build time
- `booth_messages` Jupyter server extension removed from the notebook variant
  - All `/booth-messages/api/*` traffic has been served by the shared bash API server (via nginx) since the wrapper was introduced, so the Jupyter-side handlers were dead code
  - Notebook startup no longer logs `error adding extension (enabled: True): The module 'booth_messages' could not be found`; `booth-message-notebook-wrapped--setup.sh` now only installs the `start-notebook-wrapped` launcher
- Wrapper nginx silences JupyterLab's `/_static/out/browser/serviceWorker.js` poll
  - JupyterLab's frontend polls that path from the wrapper root every ~2 s; the file isn't served (JupyterLab is mounted at `/lab`), so every poll was flooding the container logs with 404s
  - Added a dedicated `location = /_static/out/browser/serviceWorker.js { return 204; }` rule so the poll is absorbed at nginx instead of reaching the inner server

## 0.43.0

- `booth config` TUI warns when `.booth/` directory is not writable
  - Dismissable dialog shown before TUI interaction begins
- Fix auto-select extension round-trip in config TUI
  - Auto-selected extensions (e.g. AWS Credentials) now persist across `booth config` re-opens
  - Select DSL explicitly includes all selected extensions, including auto-selected ones
  - Pre-selection correctly auto-selects extensions when loading existing config
- Fix Boothfile parsing for legacy `init`-style first-line comments

## 0.42.0

- "Container stopped" page now appears on the console (web-ttyd-split) variant
  - Previously only showed on notebook, codeserver, xfce, and kde variants
  - Detects connection loss via API poll failures and displays a fullscreen overlay
- Logout triggers container shutdown in wrapped variants (codeserver, notebook, desktop)
  - Inner service exit (e.g. user logout) now cleanly shuts down the container
  - Proper SIGTERM/SIGINT signal propagation to child processes
- Architecture documentation (`doc/ARCHITECURE.md`)

## 0.41.0

- `--idle-time <s>[,t]` — auto-shutdown after inactivity
  - Prompts "Still using this booth?" after `s` seconds of no keyboard/mouse activity
  - Auto-shuts down after `t` seconds if no response (default: 60s)
  - `--idle-exit-code <n>` — custom exit code on idle shutdown (default: 0)
  - Activity detection via browser keyboard/mouse events (throttled, once per minute)
  - Web overlay shows "Container stopped" dialog on idle shutdown
  - Works across all web variants (codeserver, notebook, xfce, kde); terminal variants shut down directly
- `--show-run-time` / `--show-count-down` — session timers in the web overlay
  - Run time: elapsed time since booth start, shown next to Restart/Shutdown buttons
  - Countdown: time remaining until auto-shutdown, with color-coded warnings at 15/10/5 min
  - `--count-down-exit-code <n>` — custom exit code when countdown expires
- `--persist-home` — persist `/home/coder` across sessions using a Docker named volume
  - `home-volume-list`, `home-volume-export`, `home-volume-import` commands
- `booth config` version setup — `--version` flag in config sets the CodingBooth version
- Desktop wallpaper branding for XFCE and KDE variants
- Renamed `booth init` to `booth config` across all code, tests, examples, and docs

## 0.40.0

- Booth message system — interactive dialogs and toast notifications inside the container
  - Message types: yes-no, ok, text, password, choice, radio, checkbox, toast
  - Web overlay with modal dialogs and auto-dismissing toasts
  - `booth--msg` terminal UI for base variant
  - HTTP API server for message create/respond
- Shutdown and restart dialogs with confirmation prompts
- Web UI overlay with lifecycle panel (Restart / Shut Down buttons)
- Fine-grained home copy with `.mount-this` markers
- `cache-dirs` template field for directory-level cache mounts
- Claude Code settings cache — persist `~/.claude/` across sessions
- Improved `booth config` TUI quit prompt
- Documentation: separate overlay and message docs

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

- Modular startup scripts — `booth config` now generates individual files in `.booth/startups/` (e.g., `65-excalidraw-autostart--startup.sh`) instead of a single merged `startup.sh`
  - User-added `*--startup.sh` files in `startups/` survive `booth config --no-tui --overwrite`
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
- Package manager templates — variadic extensions for installing global packages via `booth config`:
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
- Documentation overhaul — new standalone pages: How It Works, Lifecycle, Run, Init, Examples, Home, Setup, Variants, Egress implementation
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

- `booth template` command — new top-level command replacing `config list` and `config search`
  - `booth template list` — compact listing with descriptions (hides auto-select extensions)
  - `booth template search <term>` — search by name, description, or tag
  - `booth template show <name>` — detailed view with parameters, extensions, requires, tags, and file changes
  - `booth template show <name>+<ext>` — show extension details (e.g. `python+uv`)
  - `booth template show <name> --detail` — show file and segment contents
  - `--full` flag to include non-primary templates in list/search
- `booth config --set <key=value>` — set arbitrary config.toml values from the CLI (bare key = boolean true)
- `booth config --no-tui` without `--select` — create an empty booth with only CLI overrides
- `--port` flag for `config --no-tui`/`--dryrun` — set port directly in generated config.toml
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
- `config --no-tui --overwrite` — re-generate booth configuration (overwrites existing files)
- `--version` flag for `config --no-tui`/`--overwrite`/`--dryrun` — use templates from a specific release version
- `--overwrite` flag for `config --no-tui` — overwrite existing files without prompting
- Two-line generated file header: "Generated by" (exact command) and "Adjust with" (reformatted for easy editing with `--select` last)
- `config --no-tui` path is now optional (defaults to current directory)
- `config --no-tui` allows `.booth/` to already exist; prompts for confirmation only when individual files would be overwritten

### Changed
- `booth install` downloads only the current platform's binary (not all platforms)

## 0.21.0
- Booth config, run snake and CC auto accept.

## 0.20.0
- Init templates

## 0.19.0

### Added
- `codingbooth config` command for guided project initialization
  - `config --no-tui <path>` — generate `.booth/` configuration at a target path
  - `config --no-tui --dryrun` — preview generated output without writing files
  - `--select` DSL for template selection (inline, heredoc `-`, file `@recipe`, URL `@@url`)
  - `--start` flag to immediately start the booth after config
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
- Document that `--egress` with `--dind` is **not supported** due to firewall bypass risk in the shared network namespace.

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
