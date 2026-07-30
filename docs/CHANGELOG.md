# Changelog

This file contains a list of changes for each released version.

## Unreleased

- **Wrapper `0.15.0` — `booth config` offers to install when the project has no
  binary yet.** Typing `booth config` in a folder (or under a parent) that has
  no `codingbooth.lock` used to either hard-error or — worse — open the TUI
  via a *foreign* wrapper that already had a lock (e.g.
  `../CodingBooth/booth config` from an empty project). The offer is keyed on
  **the project tree** (`$PWD` and parents: executable `./booth` *and*
  `codingbooth.lock` — a bare lock under e.g. `~/.booth` does not count), not
  on the invoked wrapper’s own lock. On a TTY: *Install and continue? [Y/n]* →
  install into `$PWD` (shared cache) and re-run `config`. Non-TTY with no
  usable binary still hard-errors. Only `config` gets the offer. Covered by
  `tests/wrapper/052-config-offer-install.sh`.

- **Booth call trace for the complex suite (`CB_DIAG_LOG`).** Complex tests capture
  booth with `2>/dev/null`, so a run that intermittently returns nothing left no
  evidence: the suite printed `FAILED:` with no output and there was nothing to
  diagnose from. `run_coding_booth` now records the command, its exit code, and a
  copy of stderr whenever `CB_DIAG_LOG` is set, and the complex runner points it at
  `tests/logs/complex-booth-calls.log` by default (`CB_DIAG_LOG=/dev/null` opts out).

  Stdout is deliberately left untouched — buffering it through a variable or a
  process substitution can itself drop output, which is the exact symptom under
  investigation, so only stderr is teed. The worst case is a few missing log lines,
  never missing test data. This is instrumentation, not a fix: booth occasionally
  returning nothing under full-suite load is still unexplained, and the intent is
  that the next occurrence explains itself rather than being retried away.

- **`test-env` now runs, and pins that a project-root `.env` is not imported.** The
  directory is `test-env/` but its script was named `test--workspace-env.sh`, and
  discovery expects `test--<dirname>.sh` — so it had never run since it was added in
  January, which only became visible once skipped tests started being reported. Its
  first assertion expected a project-root `.env` to be auto-loaded; that is not the
  design (only `.booth/.env` is, and it must be gitignored — a bare `.env` is often
  committed, sometimes with real values). The assertion is now inverted: it asserts
  the variable does **not** reach the container, so bare-`.env` auto-loading cannot
  be introduced silently. Use `env-file = ".env"` in `.booth/config.toml` to opt in.

  Its assertion harness was also broken — `[[ … ]] || fail` followed by an
  unconditional `pass`, so a failing check printed both ❌ and ✅ and the file
  reported four checks for three assertions. Each is now a plain `if/else`.

- **Test captures no longer lose booth's output to SIGPIPE.** `X=$(booth … | head -1)`
  under `set -o pipefail` let `head` close the pipe as soon as it had its line;
  booth took SIGPIPE, the pipeline went non-zero, and the capture collapsed to `""`.
  Where the call site had a `|| X=""` guard the test failed with an empty
  `Actual output:`; where it had none, `set -e` killed the script outright and the
  suite reported `FAILED:` with no output at all. It is a race, so it only landed on
  a loaded machine — which is why it read as flakiness for so long, and why
  `capture_codingbooth`'s retry papered over it instead of fixing it.

  All 66 affected call sites now capture booth's output first and apply the
  transform afterwards, and `capture_codingbooth` does the same internally, so its
  21 callers are covered too. `test-lifecycle`'s `grep -qx` probe got the same
  treatment — an early-exiting `grep` could turn a listed booth into a false
  negative. Consumers that drain stdin (`tail`, `tr`, `grep -v`, `grep -c`) were
  never affected and are unchanged. Regression test:
  `tests/dryrun/test028--capture-no-sigpipe.sh`, which forces the losing side of the
  race deterministically rather than waiting for load to expose it.

- **Six install managers were broken; the skipped tests had been hiding them.**
  - `install deno …` — Deno 2 requires `--global` to install a *command* (permission
    flags are global-only), so every `install deno` failed the build. The manager now
    supplies `--global` unless the caller already passed it (`--global` or a short
    bundle like `-Agf`). Project dependencies are unaffected — those go through
    `install deno-pkg`, which uses `deno add`.
  - `install luarocks …` — looked for luarocks under `/opt/lua-stable/bin`, but
    `setup lua` installs it from apt to `/usr/bin/luarocks`; no `/opt/lua-stable`
    exists at all, so the manager aborted every time. It now resolves luarocks from
    `PATH`, still honouring `LUA_HOME` when that really holds one.
  - `install pecl …` — `setup php` never installed `php-pear`, so no `pecl` binary
    existed; the setup's own `command -v pecl || true` swallowed it and advertised
    pecl anyway. `php-pear` is now part of the package set.
  - `install cabal …` — installed as root with cabal's default symlink method, so
    `/usr/local/bin/<tool>` pointed into `/root/.local/state/cabal/store/…`, which is
    unreadable for the `coder` user the booth runs as — the tool appeared as a
    dangling symlink. Now uses `--install-method=copy`.
  - `install conan …` — downloaded into root's `/root/.conan2`, invisible to `coder`,
    so the cache always looked empty. Now downloads as `coder`, and a failed download
    fails the build instead of being swallowed by `|| true`.
  - `install bun …` — `bun add -g` puts shims in `~/.bun/bin`, which is not on `PATH`,
    so the package installed and the command was still not found; they are now
    symlinked into `/usr/local/bin`. `setup bun` additionally links `node -> bun` when
    no real Node is present, since npm packages ship `#!/usr/bin/env node` shims that
    otherwise fail on a bun-only image (a genuine Node install is never shadowed).

- **Nineteen complex tests were never actually running.** `test-install-*`,
  `test-boothfile-apt`, and `test-boothfile-apt-snapshot` wrote their build-half
  check as `-- bash -lc '<cmd>'`. Everything after `--` is joined into one shell
  command line, so that flattened to `bash -lc <cmd>` — running `<cmd>`'s first
  word with `$0` set to the second, which fails quietly rather than loudly. The
  checks are now passed as a single quoted argument (`-- '<cmd>'`), which is also
  what `tests/basic` already did. The CLI is unchanged: the space-join is the
  documented `--` contract, and `tests/basic/test001--command.sh` depends on it to
  get a redirect inside the container. `install-pip` / `install-uv` additionally
  asserted the wrong CLI — PyPI's `cowsay` needs `-t`. **Once running, 13 of the 19
  pass and 6 fail on real defects in the install managers** (`deno`, `luarocks`,
  `pecl` fail the build outright; `cabal` leaves a dangling symlink into `/root`;
  `bun` puts binaries outside `PATH`; `conan` leaves an empty cache). Those are
  left failing deliberately — they are the breakage the skipped tests were hiding.

- **The `cb-local` test gate no longer goes stale.** `build/build-all.sh` now tags
  `cb-local/codingbooth:base-<version>` after a successful base build. That tag is
  what `use_local_base_image` gates on; it was applied by hand, so every version
  bump silently disabled the 23 tests that depend on it.

- **Skipped tests are reported instead of vanishing.** `tests/run-automate-tests.sh`
  counts skips per suite, shows them beside the pass tally, and prints a
  `Skipped: N` line in the summary. A self-gating test exits 0 and its remaining
  checks never print, so the totals used to just shrink — a run with 35 checks
  disabled still read `All tests passed`.

- **Documented how `--` is parsed.** [BOOTH_RUN.md](BOOTH_RUN.md#command-mode----cmd)
  now spells out that `booth -- …` is one shell command line (operators work,
  quoting does not survive) while `booth exec … -- …` is the opposite (argv passed
  straight to `docker exec`, no shell). The README's
  `booth -- python -c "print('hello')"` example was broken by this and is fixed.

- **Project-local templates, extensions, and recipes.** A booth can ship its own
  catalog under `.booth/templates/` (same category/`template.toml` /
  `*--extension.toml` layout as the stock tree). `booth config` (CLI + TUI) and
  `booth template list|show|…` load them automatically and **merge** them into the
  stock registry: same name → **local wins** with a stderr warning
  (`project template "go" overrides built-in …`). Bare recipe names resolve to
  `.booth/recipes/<name>.recipe` (`.recipe` appended when missing). Path-shaped
  `@` refs (`/…`, `./…`, `../…`, `~/…`, `C:\…`) and URLs (`@https://…` or `@@…`,
  with bare `@@host/path` assuming `https://`) still work. Missing recipe or
  unknown template/extension remains a hard error. Docs:
  [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md). Tests:
  `tests/config/test82-project-local-templates-and-recipes.sh` (config/dryrun) and
  `tests/complex/test-project-local/` (config + image build; markers
  `CB_DETECT_{TEMPLATE,EXTENSION,SETUP}_v1`).

- **Firebase host credentials win over empty/`{}` placeholders.** The
  `setup firebase` startup copies
  `/etc/cb-home-seed/.config/configstore/firebase-tools.json` into the home when
  the destination is missing, empty, or only `{}` (firebase-tools often creates
  that stub before login). A real login in the container is not overwritten.
  Documented mount path matches `firebase+credential` (single file). Fixes the
  firebase example when home-seed no-clobber would otherwise skip the host file.

- **Conservative team shared configs (no secrets).** Additional `shared-*`
  extensions for code-server keybindings/snippets, Neovim config, JupyterLab
  user-settings, XFCE keyboard shortcuts, and Starship prompt — all
  `shared-files`/`shared-dirs` only. Docs list explicit non-goals (IDE extension
  stores, JetBrains licenses, credentials, shell history).
- **DBeaver drivers and SQL scripts as separate shared extensions.**
  `dbeaver+drivers-shared` mounts `DBeaverData/drivers/` **and**
  `workspace6/.metadata/.config/` (for `drivers.xml` registry — jars alone still
  re-download). `dbeaver+scripts-shared` mounts project `Scripts/`. Sample
  gitignores for driver jars / metadata config.

- **`.booth/shared/` — team/git live state.** First-class bind mounts for selected
  paths outside `/home/coder/code` that are **meant to be committed** (mirror of
  `.booth/cache/` layout, opposite git policy). Config keys `shared-files` /
  `shared-dirs`; docs in [BOOTH_SHARED.md](BOOTH_SHARED.md). Opt-in extensions:
  `google-chrome+bookmarks-shared`, `chromium+bookmarks-shared`,
  `firefox+bookmarks-shared`, `codeserver+settings-shared`,
  `dbeaver+connections-shared`.
- **Chrome/Chromium `+profile-cache` paths fixed** to `~/.chrome-data` (matches the
  setup wrappers’ `--user-data-dir`), not `~/.config/google-chrome` /
  `~/.config/chromium`.
- **Chrome bookmarks shared as `Default/` directory, not a single Bookmarks file.**
  Chrome renames `Bookmarks.tmp` → `Bookmarks`, which detaches a file bind-mount;
  bookmarks never reached the host. Docs + extensions updated; shared walker skips
  non-container paths (e.g. `README.md` under `.booth/shared/`).
- **Fix Google Chrome setup key import in Docker builds.** Overwriting an existing
  apt keyring with `gpg --dearmor -o` without `--batch --yes` prompts on `/dev/tty`
  (missing in BuildKit), which aborted `setup google-chrome` with curl (23).

- **Fix GitHub “latest” version resolution under minified API JSON.** Several setup
  scripts used `grep '"tag_name"' | sed 's/.*"v?\([^"]+\)".*/\1/'`, which on a
  single-line (minified) release payload captures the *last* quoted token — often
  the reactions key `"eyes"` — instead of the tag. That broke `setup mkcert`
  (`Invalid mkcert version resolved: 'eyes'`) and `setup buf` during complex
  tests. Parsing now extracts the `tag_name` key with `grep -oE`, and mkcert/buf
  fall back to a known-good pin when resolution still fails.
- **Browser settings and extensions via shared (not cache).** Opt-in
  `+settings-shared` and `+extensions-shared` for Google Chrome, Chromium, and
  Firefox — all use `shared-dirs` under `.booth/shared/` only. Chrome family:
  settings → `Default/`, extensions → `Default/Extensions/`. Firefox: whole
  `~/.mozilla/firefox/` (profile holds prefs and add-ons).
- **Browser managed-policies extensions + sample gitignores.**
  `+managed-policies` runs `chrome-managed-policies` / `firefox-managed-policies`
  setups (enterprise JSON under `/etc/…`). Sample `.gitignore` files under
  `docs/samples/` for Chrome `Default/` and Firefox `firefox/`. Example workspace:
  `examples/workspaces/browser-shared-example/`.

- **Binary companion templates (Phase 1).** Selectable tools for companions that used
  to need raw `*-pkg` knowledge: `protobuf` (apt `protobuf-compiler` / `protoc`, with a
  `go` extension for `protoc-gen-go` and `protoc-gen-go-grpc`), `buf` (official GitHub
  release binary via `setup buf`), standalone `ffmpeg`, and standalone `graphviz`.
  Remotion/VHS/PlantUML still install their own companions. See
  `docs/TODO-BINARY_COMPANIONS.md`.

- **`dotnet-pkg` / `install dotnet` (Phase 2 binary companions).** Global .NET tools
  via `dotnet tool install --global`, selectable as `csharp+dotnet-pkg:dotnet-ef` (also
  under the `dotnet` template). Pins with `package@version`. Closes the Entity Framework
  CLI gap without a one-off template per tool. See `docs/TODO-BINARY_COMPANIONS.md`.

- **Browser companion stacks (Phase 3 binary companions).** Playwright-shaped setups for
  tools that need a second-step browser/driver download: `puppeteer` (shared
  `PUPPETEER_CACHE_DIR=/opt/puppeteer`), `cypress` (shared `CYPRESS_CACHE_FOLDER=/opt/cypress`),
  and `selenium` (Chrome for Testing + chromedriver under `/opt/selenium`; optional
  geckodriver). Avoids Ubuntu snap-stub packages for chromium/firefox. See
  `docs/TODO-BINARY_COMPANIONS.md`.

- **Binary companions docs catalog (Phase 4).** [BOOTH_CONFIG.md](BOOTH_CONFIG.md#binary-companions--library-x--also-select-y)
  lists “library X → also select Y” for dedicated templates and `*-pkg` recipes
  (protoc, buf, ffmpeg, browsers, ORM CLIs, …), with a pointer from
  [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md).

- **Harden cross-platform volume bind filtering.** Missing host bind-mount paths (`-v` / `--volume`) are skipped at runtime so Docker Desktop does not create empty directories for OS-specific credential locations. Windows drive-letter specs parse correctly, named volumes are preserved, CommonArgs (e.g. TLS cert mounts) are included, and skips are reported on stderr. See `docs/BOOTH_HOME.md`.
- **The config TUI now has a field for every setting a booth can hold.**
  It reached 18 of the 48 keys a `config.toml` may contain; the other 30 — `idle-time`,
  `persist-home`, `timezone`, `project-name`, the egress detail keys, `cmds`, the cache
  lists, and the rest — were reachable only by hand-editing or `--set`. All of them have
  fields now, grouped into Container, Egress, Build, Cache, Session and Temp Files
  sections. Integer settings get a digits-only editor and are written unquoted, which
  they have to be: `idle-time = "30"` fails the TOML decode and takes the whole booth
  with it.

  The field list is no longer hand-kept. It is generated from the settings booth actually
  reads, so a setting added to booth has no field until one is written for it (a test
  says so), and one removed from booth loses its field automatically. The hand-kept copy
  is what drifted before — and while it was adrift, a TUI save deleted the settings it
  had fallen behind on.

  Two things this surfaced. The **Version** field was labelled and documented as the
  prebuilt image tag but had always been wired to `--version`, the *template release* the
  configure run compiles from — it never wrote the `version` key at all. It is now
  **Templates Version**, with **Image Version** alongside it for the real setting. And
  reconfiguring a booth **grew its cache lists**: a `cache-files` entry was applied both
  from the existing `config.toml` and from the `Configured by:` header, so it doubled on
  every save. Both fixed. See
  [booth config — the Config tab](BOOTH_CONFIG_TUI.md#the-config-tab).

- **A booth on a git worktree (or submodule) now starts.**
  The base image installs a `git lg` convenience alias at container start. Git runs repo discovery
  before *every* subcommand — including `git config --global`, which needs no repo — so in a
  workspace whose `.git` is a dangling gitfile (a worktree or submodule, whose real git dir lives
  outside the mount) that alias exited `128`. Under `set -euo pipefail` it took the entrypoint with
  it, and the booth died before running anything: not the user's command, not `.booth/startup.sh`,
  not a build. `booth exec --run -- echo hello` failed with `did not become ready in time` and a
  container `Exited (128)`. The alias is now guarded — skipped when git is absent, run from `/`
  (the only directory with no possible `.git` ancestor) otherwise, and never fatal.

- **Removed the unused `variants/base/setups/libs/git-on-token.sh`.**
  It configured git identity and a `gh` credential helper from `GH_TOKEN`, but had no callers
  anywhere in the repo. It also carried the same startup-fatal hazards described above — unguarded
  `git config --global` calls plus `exit 1` on a missing or invalid token — so wiring it in as-is
  would have prevented the booth from starting for any user without GitHub credentials. Removed
  rather than repaired, since nothing used it.

  Note this makes the booth *start* on a worktree; it does not make git *work* inside one. The
  parent repo's `.git/worktrees/<name>` is still outside the mount, so in-booth `git status`,
  `lazygit`, and `gh` will not find the repo. Full worktree support is a separate change.

- **`booth exec` accepts `--daemon` (`-d`) to start a command detached.**
  The command is started inside the booth and `exec` returns immediately, so long-running things
  (a dev server, a watcher, a build daemon) can be launched without holding the terminal:
  `booth exec myproject --daemon -- bash -c './server >/tmp/server.log 2>&1'`. Detaching trades away
  the result — no output is streamed back and the command's exit code is not forwarded, so `exec`
  exits `0` once the command has *started*; redirect output inside the container to keep it. Two
  combinations are refused rather than silently misbehaving: `--daemon -it` (a detached command has
  no terminal to attach to) and `--daemon --run` without `--keep-alive` (the booth would be stopped
  the moment `exec` returns, killing the command that was detached to outlive it). The same check
  applies to a booth an earlier `--run` left ephemeral. `booth shell` is unaffected — detaching an
  interactive shell has no meaning.

- **The default container name auto-suffixes with the port on collision instead of failing.**
  Running the same project twice used to error (`container name "myproj" already exists`). Now the
  first booth keeps the stable folder-derived name (`myproj`) and a second concurrent booth of the
  same project auto-falls back to `myproj-<port>` — no extra flags, and the port is already unique
  because `--port` defaults to `NEXT`. The stable base name stays with the first booth, so no-argument
  lifecycle commands (`booth stop` / `remove` / `restart`) still target it. This applies only to the
  derived default name; an **explicit** `--name` remains a contract that errors on collision (use a
  `{project}-{port}` placeholder when you want an explicit-but-unique name).

- **`--port NEXT` / `RANDOM` can start from a chosen base: `NEXT:<base>` / `RANDOM:<base>`.**
  Both symbolic port modes previously always scanned from 10000; now an optional `:base` suffix
  moves the starting point, e.g. `--port NEXT:20000` picks the first free port ≥ 20000 and
  `--port RANDOM:20000` a random free one ≥ 20000 (still stepping by 1000). `NEXT` is unchanged and
  equals `NEXT:10000`. This lets related projects claim separate, predictable port bands while still
  auto-avoiding collisions. `<base>` is validated 1–65535; a malformed base is a clear error. The
  `:base` forms remain create-only symbolic values, so `exec`/`shell --run --port NEXT:20000` is not
  asserted against an existing booth's port.

- **`--name` accepts `{port}` / `{project}` / `{variant}` placeholders, resolved after port
  selection.** Running several booths of the same project used to collide on the container name
  (it defaults to the folder name) even when `--port NEXT` avoided the port collision — you had to
  hand-pick a port and thread it into `--name` yourself (`PORT=12000 booth --port $PORT --name gp$PORT`).
  Now the name can follow the auto-picked port: `booth --port NEXT --name '{project}-{port}'` picks a
  free port and names the container `myproj-12000` in one command, so a second run lands on
  `myproj-13000` with no collision on either axis. The template is stored literally (so
  `name = "{project}-{port}"` in `config.toml` re-resolves every run) and expanded in the run pipeline
  right after `PortDetermination`; literal characters that are not Docker-name-safe are replaced with
  `-`. It mirrors how booth-relative `+OFFSET` publishes let service ports follow the booth port. Works
  through `booth exec`/`shell --run` too: because the resolved name is only known after the run, the
  created container is located by diffing the booth set before and after.

- **List a booth's ports, from either side.** `booth expose list` (host) reports every
  port a booth publishes — the front door, published `-p` ports, and runtime tunnels — and
  confirms each against `docker port`. Inside a booth, `booth--expose list` shows the same
  ports plus which process is listening on each (from `ss`), including internal-only services
  that are not published. Both read a new run-time manifest, `.booth/.tmp/ports.json`, written
  by the run pipeline after the ports are resolved; when it is absent (an older booth) the host
  command falls back to the live `docker port` view. See `docs/BOOTH_EXPOSE.md`.

- **A host-env expose port can fall back to a booth-relative offset: `${SERVER_PORT:-+300}:1234`.**
  The two host-side forms now compose. Previously a `${NAME:-default}` fallback had to be a fixed
  number, so a published port was either env-overridable (`${SERVER_PORT:-12345}`) or booth-relative
  (`+300`), never both. Now `${SERVER_PORT:-+300}:1234` publishes on `$SERVER_PORT` when the variable
  is set and on `boothPort + 300` when it is not — a default that follows the booth port so two booths
  of the same project stop colliding, without baking a fixed host port into the config. It works
  because `${…}` is expanded at TOML unmarshal, *before* `ResolveRelativePorts` runs: expansion yields
  `+300:1234`, then the offset step rewrites it against the booth port. Only the config-time validation
  had to change — it rejected the `+` in the fallback.

  A `+OFFSET` fallback requires an explicit `:CONTAINER`: the bare `HOST:HOST` shorthand would put the
  `+OFFSET` on the container side too, which is not a port, so `--expose '${SERVER_PORT:-+300}'` is
  refused with a message pointing at the missing container port.

- **Web apps get a desktop icon that opens them in a browser.** Server-style tools that serve an
  HTTP UI on an internal port — Jupyter Notebook, CloudBeaver, Scratch — now get a desktop launcher
  (and, on the Wayland variant, a panel button) that opens the service in a dedicated app-mode
  browser window. Because the desktop session runs inside the same container, the launcher points
  straight at `http://localhost:<internal-port>` — no host mapping or proxy. A setup registers one
  with `cb-web-icon`, which drops the launcher into the same `/etc/skel/Desktop` registry the app
  icons use; at click time `cb-web-open` resolves the port from its env var (falling back to the
  default), appends an access token when one is set, starts the service if it is not already
  listening, and opens it.

  Two launch fixes rode along. On **XFCE**, desktop launchers no longer trip Thunar's "insecure
  location / Mark Executable" prompt: they are stamped with the `metadata::xfce-exe-checksum` that
  `libxfce4util`'s trust check expects (the same value "Mark Executable" writes) before the desktop
  loads. And on **Wayland**, the waybar buttons launch each app's `Exec` directly instead of via
  `gtk-launch`, which the Wayland image does not ship — so every panel button works, not just the
  new ones.

- **`mkcert` install survives GitHub rate limits.** A full `--no-cache` build+test run can exhaust
  the unauthenticated GitHub API/download budget, and `curl --retry` alone does not retry an HTTP
  429 or 5xx — so the mkcert binary download failed hard and took the booth build (and
  `test-boothfile-mkcert`) down with it. The GitHub API call and the binary download now pass
  `--retry-all-errors`, and a download that still fails falls back to the pinned known-good version
  before giving up.

- **`shell` / `exec` accept create-time `--port` and fail on mismatch by default.** With `--run`, a missing booth is created via `booth run --daemon`, and `--port` (number, `NEXT`, or `RANDOM`) is forwarded so the new booth gets the host UI port you asked for — same for `--name` / `--keep-alive` as before. Against an **existing** booth, an explicit numeric `--port` is a contract: if it does not match the published host port, the command **refuses to connect** (so scripts do not run against the wrong environment). Pass **`--accept-existing`** to connect anyway with a warning on stderr. Symbolic `--port NEXT` / `RANDOM` are only applied on create and are not compared. Unit tests cover the mismatch rules and run-arg construction; complex test `tests/complex/test-connect-run-port/` exercises create, match, refuse, accept-existing, `NEXT`, and ephemeral teardown. See `docs/BOOTH_CONNECT.md`.
- **Desktop apps now appear as icons on the graphical desktop.** On the XFCE, KDE, and LXQt
  variants, every selected GUI application — VS Code, the JetBrains IDEs, DBeaver, Firefox, Chrome,
  Chromium, GIMP, Inkscape, LibreOffice, Obsidian, Eclipse, Antigravity, Thonny, BlueJ, Greenfoot —
  drops a launcher on the desktop that runs on double-click. On XFCE the icons are laid out
  top-centre, spreading left and right as more are added; the Wayland (labwc) variant draws no icon
  surface, so each app becomes a button on the waybar panel instead. A setup registers its launcher
  by calling `cb-desktop-icon <app>`, which copies the matching `.desktop` into `/etc/skel/Desktop`;
  `booth-entry` seeds that directory into each user's `~/Desktop`, and both the XFCE arrangement and
  the Wayland panel derive their app list from it, so one registry drives every variant.

- **Three fixes made those launchers actually work.** `cb-has-desktop.sh` now recognises labwc (and
  the other wlroots compositors), so desktop-only setups such as PyCharm and DBeaver install on the
  Wayland variant instead of silently skipping. The VS Code launcher wrapper no longer hard-codes
  `DISPLAY=:1`; it honours the session's display — `:0` (Xwayland) on Wayland, `:1` (VNC) elsewhere —
  so clicking VS Code opens it rather than failing to find a display. And on LXQt, `~/Desktop`
  launchers are marked trusted (`gio set … metadata::trusted`) before the pcmanfm-qt desktop renders,
  so they no longer carry an "untrusted" emblem or ask for confirmation on first launch.

- **`booth build` now expands variant aliases, so it works for the configs `booth config` writes.**
  The variant names the base image tag, and only the canonical names (`base`, `codeserver`,
  `desktop-xfce`, …) are published — the aliases (`xfce`, `ide`, `desktop`, `console`, …) are expanded
  by `ValidateVariant` before the tag is assembled. The run path did that; `booth build` never called
  it, and passed the alias through raw. A project whose `config.toml` says `variant = "xfce"` — which
  is exactly what `booth config --variant xfce` writes — therefore failed with
  `nawaman/codingbooth:xfce-<version>: not found` on the `FROM` line, while `booth run` on the same
  project built fine. An unknown variant is now refused by `booth build` too, rather than handed to
  docker as a bogus tag.

- **A booth no longer generates a config docker refuses to start.** Docker cannot bind one host
  port twice — it fails the container with `address already in use` — and run-args grew duplicates
  in two ordinary ways. A template's short-form `-p` plus the user's long-form `--publish` for the
  same mapping (`cloudbeaver+expose --expose 8978:8978`) were both emitted, because the two flag
  forms are deliberately not deduped against each other. And two templates could resolve to the
  same mapping (`nginx+expose/apache+expose`, both `8080:80`) because the compiler's dedup runs
  *before* params are expanded, so it compares `${NGINX_PORT}:80` against `${APACHE_PORT}:80` and
  finds them different. Neither combination needed a hand-edited config to reach; both simply did
  not start.

  Identical mappings are now collapsed (the user-owned `--publish` is the one kept, since it is
  what `booth config` reads back into `--expose` when re-configuring). Anything that genuinely
  cannot bind is refused at start with both mappings named, instead of docker's `driver failed
  programming external connectivity`. That check runs after `+OFFSET` resolution, so it also
  catches an offset that lands on an absolute mapping, and it accounts for the booth's own port —
  `--expose 20000:8978` on a booth at 20000 is now an error rather than a mystery. Publishing one
  *container* port on two host ports stays legal, because docker allows it; but a `--expose` that
  does so now says that it adds a second mapping rather than moving the first, and points at
  `+expose:<port>`, which does move it.

- **An expose host port can be booth-relative: `rabbitmq+start+expose:+4567`.** A `+OFFSET` host
  port stays literal in `run-args` (`"-p", "+4567:5672"`) and resolves at container start as
  `boothPort + OFFSET`, so a booth on port 20000 publishes AMQP on 24567 — and two booths of the
  same project on different ports stop colliding on published ports. A bare number is still an
  absolute host port; the `+` is what makes it relative.

  The resolution itself is not new — `--expose +4567:5672` and hand-written `run-args` have always
  been rewritten this way, for template-contributed `-p` as much as user-set `--publish`. What was
  missing was any way to *say* it in a selection: the DSL splits an item on `+` to find its
  extensions, so `expose:+4567` parsed as an extension named `4567` ("unknown extension"). Inside a
  param list a `+` now starts an extension only when followed by a letter — names are identifiers
  and never digit-initial — so `expose:+4567+start` is a relative port *and* a `+start` extension,
  while a malformed `go++linter` still reports an empty extension name. It also makes
  `apt-pkg:libstdc++6` parse, which errored out before.

- **The booth now refuses to start unless `.booth/cache/` is gitignored *and* untracked.** The
  cache is whatever the container writes to the mounted paths, and with `claude-code+settings-cache`
  that includes a live credential: `~/.claude/` is mounted as a whole directory, so the host token
  the `/etc/cb-home` override layer copies to `~/.claude/.credentials.json` on every start is
  written straight back into your project tree, next to `history.jsonl` and the `projects/`
  transcripts.

  The old check greped `.booth/.gitignore` for a `cache/` line, which cannot see the failure that
  actually happens: **gitignore does not apply to files git already tracks.** Once a cache file is
  in the index — force-added, or added before the rule existed — git keeps committing it and the
  grep still reports green. The check now asks git, and fails two ways: `is NOT gitignored` (add the
  rule) and `is tracked by git` (`git rm -r --cached .booth/cache`, then **rotate any credential
  that was committed** — a gitignore rule will not untrack it for you). Projects that are not git
  repos are unaffected: there is nothing to commit to, so the check is skipped, matching
  `.booth/.env`.

  `.booth/.gitignore` had two writers — `booth config` and the wrapper script, which has to write it
  before the CLI binary exists — and they had drifted into twelve variants in the wild. Both now
  emit one canonical block (`output.BoothGitignore`), pinned by a test that diffs the wrapper's
  heredoc against the constant. This was not cosmetic: both writers overwrite the file
  unconditionally, so a rule only one of them knew about vanished as soon as the other ran. The
  wrapper emitted the `tools/` rules only for `--cache=local`, so the first `booth config` in such a
  project un-ignored the downloaded binaries; those rules are now always present (a no-op in
  shared-cache mode, where `tools/` holds nothing but the lock file).

  A cache entry that maps onto a protected container path (`/home/coder/code`, `/opt/codingbooth`)
  is now an error naming every offender, not a warning that silently drops the mount — as the docs
  had always claimed. A skipped mount is indistinguishable from a cache that inexplicably does not
  work.

- **`expose` extensions now have a host port you can move on its own.** The host side and the
  container side of the published mapping were the same param, so the only way to get off a busy
  host port was to move the service inside the booth as well. Each `expose` extension now declares
  its own `*_HOST_PORT` (`SSH_HOST_PORT`, `CLOUDBEAVER_HOST_PORT`, …) defaulting to `"${SVC_PORT}"`
  — a reference, so `cloudbeaver:25.3.5,9000+expose` still publishes `9000:9000` and the two cannot
  drift apart, while `cloudbeaver:25.3.5,9000+expose:19000` publishes `19000:9000`. `rabbitmq` takes
  both of its ports positionally: `rabbitmq+start+expose:15672,25672`. Defaults are unchanged, so
  existing configs regenerate byte-identically. In the TUI a followed port renders as its resolved
  value with a `(follows SVC_PORT)` note rather than the raw `${SVC_PORT}`; editing the field shows
  the reference, so overwriting it is a deliberate pin rather than an accident.

  Param pins carried over from an existing Boothfile now distinguish a value the user *chose* from
  one the last generation *derived*. `arg` lines hold resolved values, so a followed host port
  reaches the Boothfile as a number and string comparison alone cannot tell `SSH_HOST_PORT=2200`
  ("I want 2200") from `SSH_HOST_PORT=2200` ("that is what `${SSH_PORT}` came to"). Re-resolving the
  default against the Boothfile's own args reconstructs the derived value: a match re-derives from
  the new selection, anything else is preserved as before. Without it, re-configuring
  `openssh+server:2200+expose` to `openssh+server:22+expose` published 2200 while sshd listened on
  22 — the very drift the host-port param exists to prevent.

- **A param default can now reference another param.** Writing `default = "${SVC_PORT}"` used to be
  a coin flip: param expansion was a single pass over a Go map, so `-p ${SVC_HOST_PORT}:${SVC_PORT}`
  came out as `8080:8080` or as a dangling `${SVC_PORT}:8080` depending on the run's map iteration
  order. Param values are now resolved to a fixpoint before anything consumes them, so run-args,
  `arg` lines and startup scripts all see literals. Circular defaults are a compile error naming the
  cycle; a reference to a name that is not a param (`${HOME}`) is still passed through untouched for
  the shell to expand at runtime. This is what lets an `expose` extension carry a host port that
  *follows* the port the service actually listens on rather than a hardcoded literal.

- **Server templates can now auto-start and publish themselves.** `notebook`, `codeserver` and
  `ollama` each installed a server and then left it sitting there: `start-notebook` and
  `start-codeserver` were on `PATH` but nothing called them, and Ollama's startup hook only created
  `~/.ollama` while its docs told you to run `ollama serve` by hand. Each now gets the
  `autostart` + `expose` extension pair that `excalidraw`, `mermaid`, `plantuml` and `cloudbeaver`
  already had — so `--select notebook+autostart+expose` puts JupyterLab on 18888 next to your
  code-server or desktop, reachable from the host.

  `notebook` and `codeserver` are both a template *and* a variant, and on their own variant the
  server is already the primary service **on that same port** (JupyterLab on 18888, code-server on
  19999, each behind the booth's nginx). Auto-starting there would not be merely redundant, it would
  collide — so both startup scripts bail out on the matching variant. The port is now a param
  (`NOTEBOOK_PORT`, `CODESERVER_PORT`, `OLLAMA_PORT`) instead of a hardcoded literal.

  `nginx` and `apache` get `expose` only. They already auto-start from their own
  `/usr/share/startup.d/` hook, but nothing published the port, so the daemon was unreachable from
  the host. Both serve on container port 80, and the extension maps a host port to it
  (default 8080) — which also means they cannot share a booth.

- **Java notebook kernels installed nothing on the `base` variant.** All three Java kernel setups
  (`java-nb-kernel`, `java-ijava-nb-kernel`, `java-jjava-nb-kernel`) opened with a guard that exited 0
  when `BOOTH_VARIANT_TAG == base`, printing "Variant does not include VS Code (code) or CodeServer" —
  a message about VS Code, in a Jupyter kernel installer. It was copy-pasted from a VS Code extension
  setup. None of the other fourteen notebook kernels (bash, python, go, rust, scala, kotlin, …) carry
  it. The effect was that `java+kernel/notebook` on `base` built successfully and silently produced no
  Java kernel. The guard is removed; the setups already check what they actually need (python with
  `jupyter_client`/`jupyter_core`, `javac`, `JAVA_HOME`).

- **`coder` now owns uid 1000 in the base image.** Ubuntu 24.04 (noble) ships a stock `ubuntu` user
  holding uid/gid 1000, so `free_uid()` handed `coder` 1001 — and 1000 is the uid nearly every Linux
  host has. `booth-entry` therefore renumbered `coder` and re-owned `$HOME` on *every* start. With
  large host directories bind-mounted under `/home/coder` (a `~/.m2`, a project tree, a `.booth/cache`)
  that reconcile was slow enough to look like a hang — booths took minutes to start. The stock `ubuntu`
  user is deleted at build time, so the uids already agree and the renumber is skipped entirely.

- **Setups retry their network fetches instead of failing the build on a blip.** Two of them pulled
  from the network with no retry at all, and a single connection reset took the whole image down.

  `go--install.sh` ran `go install` bare. It fetches through proxy.golang.org, which resets connections
  often enough that this was the single most common cause of a failed build — it took out an entire
  test suite three times in one day. Go has no retry of its own, so the call is now wrapped in one
  (3 attempts, backing off). A genuinely broken package still fails, just three attempts later.

  `kafka--setup.sh` fetched from `downloads.apache.org`, a CDN that only carries the *current* release
  — so it 404s for any pinned older version and every build falls through to `archive.apache.org`,
  which is durable but throttled. The archive fetch now retries (`--retry-all-errors`, because curl
  does not treat a reset mid-transfer as retryable on its own); the CDN still fails fast, since a 404
  is not worth retrying.

- **Credential extensions now seed credentials, not whole application-state directories.**
  `aws-cli`, `aws-sam-cli`, `azure-cli`, `gcloud`, `kubectl` and `codex` each mounted the tool's entire
  home directory into `/etc/cb-home-seed`, and every one of them is `auto-select = true`. Because that
  seed is copied into the container home on every start, the copy swept up whatever else lived there:
  gcloud writes a log file per invocation (733 of 741 files in a normal `~/.config/gcloud`), `az` writes
  a telemetry file per invocation and unpacks extensions as full Python packages, kubectl caches a
  discovery document per cluster, and `~/.codex` keeps a transcript of every conversation. None of it is
  a credential, and all of it was copied into every container.

  Each now mounts the specific credential and settings files. Mounts whose host path does not exist are
  already dropped before `docker run` (`FilterMissingVolumeMounts`), so listing paths that only some
  users have — `application_default_credentials.json`, an SSO session cache, the Windows gcloud layout —
  costs nothing. What is intentionally left behind is spelled out in each extension's `display-detail`.

  `antigravity` and `cursor` are **not** narrowed: they are VS Code forks that need most of their
  `User/` directory to stay signed in, so they need cache *exclusion* rather than file selection, which
  `smart_copy` has no mechanism for yet.

- **Home-seeding no longer forks a subprocess per file.** `booth-entry`'s `smart_copy` walked
  `/etc/cb-home-seed` and `/etc/cb-home` entry by entry, forking `basename` *and* `cp` for every one,
  because any directory below might carry a `.mount-this` marker asking to be copied as a unit. No
  marker ships in any template and host directories never have one, so in practice the walk always ran
  to the bottom — at roughly 56 files/sec. A booth seeding a real home directory took *minutes* to
  start, and looked hung.

  A subtree with no marker anywhere below it has nothing that can change the copy's behaviour part-way
  down, so it is now taken in a single recursive `cp` (`-L`, matching the walk, which tested entries
  with `[ -f ]` / `[ -d ]` and so copied link targets rather than links). The walk is kept for subtrees
  that do carry a marker. Copying 20,000 files went from **146s to 0.65s**, with identical output.

- **`booth config --no-tui` now reads the existing booth as its baseline, like the TUI does.** It only
  ever read `config.toml`'s long-form run-args, never the `# Configured by:` header — so a reconfigure
  that did not restate `--select` rebuilt from an *empty* selection. The Boothfile escaped by luck (an
  empty one serializes to nothing, and the writer skips empty content), but `config.toml` was rewritten
  regardless: `variant`, `port`, `cmds` and every template-contributed run-arg were dropped, while the
  envs and mounts survived because those are recovered from `config.toml` itself. Losing the `variant`
  silently rebuilds the booth on the wrong base image. The header is now parsed back as the baseline,
  so a reconfigure need only state what changes.

  The flags that steer the run — `--overwrite`, `--beside`, `--dryrun`, `--start` — are deliberately
  *not* inherited: the header records the `--overwrite` that wrote it, so inheriting them would make
  every later run an overwriting one and quietly disarm the hand-written-file guard.

  Restating a list flag (`--env`, `--mount`, `--expose`) now **replaces** the saved list rather than
  unioning with it — which is what makes removing an entry possible. Omitting the flag still keeps it.

- **New Java template extensions.** `java/kernel-jjava` installs the JJava notebook kernel
  (dflib/jjava, Java 11+) as an alternative to `java/kernel`, which installs IJava — pinned at 1.3.0
  and predating the modern JDKs the template offers. Pick one, not both: they install over the same
  `java` kernelspec. `java/jbang` pre-warms the jbang dependency cache at build time, so the first
  jbang run (or Java notebook cell) does not stall on the network.

- **`examples/demo` is now generated by `booth config`** rather than hand-written, so it can be
  reopened and edited in the config TUI.

  Its `~/.claude` home-seed mount is narrowed to `~/.claude/settings.json` in the process. The mount
  was labelled "credentials" but seeded the whole directory — 418 MB of conversation transcripts, jobs
  and file-history — into the container on every start, and because the `claude-code` template
  bind-mounts `/home/coder/.claude` to the project's `.booth/cache/`, that copy landed in the project
  tree. Credentials were never the reason it worked: the template already seeds `~/.claude.json` and
  overrides `~/.claude/.credentials.json`. Seeding an entire application-state directory is the
  anti-pattern here — mount the credential files, not the app's home.

- **`booth config` no longer silently destroys a hand-written Boothfile / config.toml.** Configuring
  regenerates both files from scratch, so a hand-written booth — or a generated one that was later
  hand-edited — lost that content on the next `booth config`, with no warning. The `# Configured by:`
  header could not prevent this: it survives a hand-edit, so it cannot distinguish "still ours" from
  "someone edited this". `booth config` now fingerprints (SHA-256) what it writes, recording it in
  `.booth/.generated`, and compares before overwriting. Content it did not write is now protected, and
  "overwrite or give up" is not the only way out — you get two choices, in the TUI on save or as flags:

  - **Keep yours** (`--beside`, or `Enter` in the TUI): the generated content is written alongside as
    `<name>.new` and your file is not touched, for you to merge by hand — the same idea as
    `pacnew`/`rpmnew`/`dpkg-dist`. Nothing is destroyed, and the kept file stays guarded until you
    actually merge it. This is the TUI's default.
  - **Replace yours** (`--overwrite`, or type `overwrite` in the TUI): your file is replaced and kept
    as `<name>.bak`. Destroying work takes more than a reflex keystroke; getting at the generated
    output does not.

  The config TUI also says so **up front**, in a yellow dialog on open (Enter to continue) — otherwise
  you would configure an entire booth before discovering, at save time, that the result could not
  simply be written over what you have. It is a heads-up, not a blocker: nothing is touched until you
  save, so you are still free to go in and look around.

  `.bak` and `.new` are gitignored. A booth generated before `.generated` existed is adopted on its
  header, so no existing project starts crying wolf. Hand-written booths are the norm — every
  `examples/workspaces/*` booth is one — so this covers the mainstream case, not an edge case. See
  `cli/src/pkg/boothinit/output/guard.go` and `writer.go`; tests
  `tests/config/test68-config-guards-handwritten.sh` and
  `tests/config-tui/test15-tui-overwrite-guard.sh`.
- **New `desktop-wayland` variant (experimental) — a Wayland-native desktop in the browser.** The existing
  `desktop-xfce`/`desktop-kde`/`desktop-lxqt` variants are X11 (TigerVNC + noVNC);
  `desktop-wayland` runs [labwc](https://labwc.github.io/) (a wlroots compositor) on the
  headless wlroots backend and streams it via [wayvnc](https://github.com/any1/wayvnc)
  (`wlr-screencopy` → RFB) through the **same** websockify + noVNC delivery over the single
  booth port — only the compositor and VNC server change (TigerVNC/X11 → labwc+wayvnc/Wayland).
  The wlroots headless backend needs no logind/seat, `wlr-screencopy` reliably captures the
  session, and existing X11 apps (Firefox/Chrome/VS Code) run via Xwayland. Selected with
  `--variant wayland` (alias of `desktop-wayland`). No VNC password by default (localhost
  model, like the other desktop variants); `--public` password auth via wayvnc TLS is a
  follow-up. New setup `variants/base/setups/wayland--setup.sh`; wrapper `start-wayland-wrapped`;
  template `templates/desktops/wayland/template.toml`. See `docs/BOOTH_VARIANTS.md` and
  `variants/desktop-wayland/README.md`.
- **Fix flaky `setup jdk` builds — JBang no longer pulls its own bootstrap JDK.** `jdk--setup.sh`
  installed JBang before the JDK, so on a fresh image JBang found no `javac`/`JAVA_HOME` and
  downloaded a bootstrap JDK from `api.foojay.io` — the exact flaky download the script's
  direct-download strategy (Temurin/Corretto) exists to avoid. Under `set -o pipefail` a foojay
  outage aborted the whole build at the `curl … sh.jbang.dev | bash` step. For direct-download
  vendors the JDK is now installed first and `JAVA_HOME` exported before JBang runs, so JBang
  reuses it and skips the bootstrap download entirely; JBang-fallback vendors (openjdk, graalvm)
  are unchanged. The `sh.jbang.dev` fetch also gains `--retry 3`. Fixes `tests/config/test01-init-cli-basic`
  and `tests/complex/test-boothfile-gradle`. See `variants/base/setups/jdk--setup.sh`.

## 0.64.0

- **`booth shell-config` restores the shell convenience layer (bash, zsh, fish).**
  `shell-config install` copies the wrapper to an OS data directory
  (`~/.local/share/codingbooth/booth` on Linux, Application Support on macOS,
  LocalAppData on Windows) and installs an idempotent, marker-fenced `booth()`
  function into `~/.bashrc`, `~/.zshrc`, and fish `conf.d/codingbooth.fish`.
  The function walks up from `$PWD` for a project `./booth` and falls back to
  the central wrapper; project commands without a project still fail with the
  usual messages. Markers:

  ```
  # >>> codingbooth shell-config begin >>>
  ...
  # <<< codingbooth shell-config end <<<
  ```

  `shell-config uninstall` removes the block and the central copy;
  `shell-config status` reports install state. The one-liner installer now runs
  `shell-config install` after `booth install`.

- **Central `booth install` copies `./booth` into `$PWD` before installing.**
  Invoking install via the central wrapper (shell-config fallback) used to write
  `.booth/` next to the central script. It now places a project wrapper in the
  current directory, re-execs that wrapper, and installs the lock/binary there.
  The shell `booth()` function also appends `--code <project-root>` when walk-up
  finds a project booth above `$PWD` (so subdir runs name/mount the project, not
  the subdir). **0.14.2:** install/update always target `$PWD` even when a parent
  `./booth` exists (walk-up no longer steals install into the parent).
  **0.14.3:** fish installs to `~/.config/fish/functions/booth.fish` (autoload);
  when `--code <dir>` is given, the shell function prefers `<dir>/booth` so the
  lock next to that project wrapper is used (not a parent `./booth`).
  **0.14.4:** fish no longer uses `cd` inside command substitutions (fish does
  not run those in a subshell), so `booth` from a project subdirectory no longer
  leaves the shell sitting in the project root.
  **0.14.5:** `./booth shell-config` defaults to install; new `./booth create <dir>`
  creates the directory and runs install inside it.

## 0.61.0

- **Every desktop variant now keeps the CodingBooth wallpaper instead of the stock desktop backdrop.**
  On XFCE, `xfdesktop` overwrote the seeded system default with its built-in `xfce-blue` backdrop on
  first login, so the brand wallpaper never appeared; the other desktops relied on a system default a
  first-run session could shadow just as easily. Each variant now re-applies the wallpaper once its
  session is up, so it wins regardless of first-run behavior — XFCE via `xfconf-query`, KDE via
  `plasma-apply-wallpaperimage` (falling back to plasmashell scripting over `qdbus`), and LXQt via
  `pcmanfm-qt --set-wallpaper`, each from an autostart entry; Wayland/labwc already writes `swaybg`
  into its session autostart on every start. The wallpaper image itself was refreshed. See the
  `*-wallpaper--setup.sh` scripts under `variants/`.

- **The base image build no longer stalls on IPv6-only mirror lookups.** `ports.ubuntu.com` (the
  arm64/ports mirror) publishes AAAA records, and on a build host without a working IPv6 route — the
  common case for the emulated arm64 leg under QEMU — `apt` preferred IPv6, stalled, and reported
  every package as "unable to locate", aborting the base build. The base image now writes an
  `Acquire::ForceIPv4` apt drop-in before its first `apt-get`, inherited by every downstream setup and
  variant, so package fetches use IPv4. See `variants/base/Dockerfile`.

## 0.59.0

- **`booth config` preserves pinned param values across reconfiguration.** Previously, reconfiguring a booth (e.g. adding or removing a template/extension) rebuilt the Boothfile entirely from the selection DSL and reset every non-default param — `NODE_VERSION`, `GO_VERSION`, `PYTHON_VERSION`, `PLAYWRIGHT_VERSION`, … — back to its template default, because pins live in the Boothfile's `arg NAME=VALUE` lines and were not carried by the stored selection. Now the resolver reads those `arg` lines back and preserves any non-default pin unless the new selection explicitly overrides it (explicit selection still wins).
  - This bit the Playwright example concretely: adding an unrelated extension silently reset the pinned Playwright version to `latest`, so the pre-baked browser no longer matched the version `npm ci` installed at runtime and headless launches failed with "Executable doesn't exist".
  - The config **TUI** now also loads real pinned values from the existing Boothfile into its param fields (instead of showing the template default), so what you see matches what is saved. New `selection.ResolveWithOverrides`; `readExistingArgs`/`overlayExistingArgs` helpers. Tests: `TestResolveWithOverrides_*`, `TestReadExistingArgs_*`, `TestOverlayExistingArgs_*`, `tests/config/test67-config-preserves-pin.sh`, and `tests/config-tui/test14-tui-preserve-pin.sh`. See `docs/BOOTH_CONFIG.md`.
- **Playwright template gains a `PLAYWRIGHT_VERSION` param.** `setup playwright` already accepted `--version`, but it wasn't reachable through `booth config`, so the version could only be hand-pinned in the Boothfile (and was lost on regeneration). Pin it with `--select playwright:chromium,1.58.2` (browsers stay the first positional; version is second). Default is `latest`; pin it so the pre-baked browsers match the Playwright installed at runtime. Multi-browser selection via the comma-positional CLI form remains a TUI path. Test: `tests/config/test66-init-playwright-version.sh`.
- **`npm-upgrade` config extension for Node.js.** Opt-in extension that upgrades the global npm to a newer version than Node.js bundles, via `run npm install -g npm@NPM_VERSION` at build time (`--select nodejs+npm-upgrade`, or `nodejs+npm-upgrade:11.18.0` to pin). Off by default — the npm that ships with the selected Node.js stays the reproducible baseline. Test: `tests/config/test65-init-npm-upgrade.sh`.

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
