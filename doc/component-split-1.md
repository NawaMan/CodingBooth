# CodingBooth Component Split — First Draft

Where `feature-split-1.md` slices the project by **what the user touches** (wrapper → binary → image → in-container surfaces), this doc slices by **what the project is made of**: concrete artifacts — files, directory roots, scripts, Go types, named conventions, long-lived processes — that participate in *more than one* feature.

The qualifying property is cross-feature reuse. An artifact used by exactly one feature is that feature's implementation; it doesn't earn a component listing here. References like `→ B1d / B3 / B4b` point to feature-split-1.md sections.

Sections:

- **C1 — Carriers**: configuration bundles parsed in one place, consumed in many.
- **C2 — Filesystem realms**: directory roots that hold cross-feature state, on host and in the image.
- **C3 — Naming conventions and identifiers**: prefixes, labels, segment/LEVEL numbers, internal port assignments — names that carry meaning across the codebase.
- **C4 — Go types**: in-binary objects threaded through the orchestration pipeline.
- **C5 — Image-baked scripts**: shell scripts installed into variant images that participate in multiple features.
- **C6 — Long-lived processes**: in-container daemons and host-side watchers (running instances of C5/C4 artifacts).
- **C7 — Web UI assets**: HTML / CSS / JS / nginx config served from inside the booth.
- **C8 — Contributor-only artifacts**: things in the repo that never ship.

## C1 — Carriers

Single artifacts whose contents fan out into many features. These are the same items called out at the bottom of feature-split-1.md, restated here for completeness because they are the most load-bearing components in the system.

- **Boothfile** (`Boothfile`, parsed by `pkg/boothfile/parser.go` / `compiler.go`) — DSL with `# syntax=codingbooth/boothfile:1` header and `setup` / `install` / `run` / `env` / `copy` / `expose` directives. Primary: B3b (parse → Dockerfile). Also: B1d (run input), B4b (Template emits Boothfile segments).
- **`.booth/config.toml`** — TOML config bundle. Primary: B4a (TUI reads/writes). Also: B1d (run-time precedence chain), B4b (Template emits scalar/array values: `dind`, `run-args`, `build-args`), B6a (`booth--expose --permanent` writes tunnel entries).
- **Template** (`templates/**/*.toml`) — 77+ TOML definitions across `languages/`, `databases/`, `ides/`, `tools/`, `ai-tools/`, `browsers/`, `desktops/`, `education/` (with `meta.toml` per dir). Primary: B4b. Emits into B3 (Boothfile segments), B1d (config), B1j (home seeding), B1k (cache), B1a (startup files under `.booth/startups/`).
- **Recipe** (`.recipe` files) — multiline format with `+` continuation, loaded via `@file` / `@@url` / stdin. Wraps the B4b selection DSL. Primary: B4c.
- **`.booth/.env`** — auto-loaded environment file, **gitignore-enforced** (`git check-ignore` refuses to run otherwise). Primary: B1l. Layered before any explicit `--env-file`.
- **`.booth/tools/codingbooth.lock`** — pin file: `version=`, `downloaded_at=`, `cache=`. Primary: A1 (wrapper writes/reads). Also: A3 (consulted on every forwarded invocation to locate the binary).
- **`version.txt`** — single-source version string. Consumed by: A2 (wrapper banner), B (binary version), `README.md` (consistency-enforced by `.githooks/pre-commit` from G), the build pipeline, and ultimately the `cb.*` labels written at run time.
- **Variant Dockerfile** (`variants/{base,codeserver,notebook,desktop-xfce,desktop-kde}/Dockerfile`) — image recipe. Primary: B3 (built by binary). Also: B1c (variant selection picks one), C (setups bake into them).

The `.booth/` *directory itself* is also a cross-cut, but at the realm level rather than the carrier level — see C2.

## C2 — Filesystem realms

Directory roots whose contents are written by one feature and read by several. The realm is the component; the individual files inside are usually feature-specific.

### Host-side, persistent (in the user's repo)

- **`.booth/`** — project-local config root. Written by A1 (wrapper writes `.gitignore`), B4 (scaffolding writes most contents), B6a (`booth message --permanent`). Read by B1 (mounted read-only into the container by default; `--writable-booth` opts out). Subtrees:
  - `.booth/config.toml` → C1
  - `.booth/Boothfile` → C1
  - `.booth/.env` → C1
  - `.booth/tools/codingbooth.lock` → C1
  - `.booth/startups/NN-name--startup.sh` (Template-emitted, B1a)
  - `.booth/cache/` (B1k host-side cache mirror; `.mount-this` markers control fan-out)
  - `.booth/home/` and `.booth/home-seed/` (B1j seeding for `--persist-home`)
- **Shared binary cache** — `~/.cache/codingbooth/` (Linux), `~/Library/Caches/codingbooth/` (macOS), `%LOCALAPPDATA%\codingbooth\` (Windows). Selected per-install via `--cache=shared|local`. Primary: A1.
- **`bin/`** — compiled multi-platform `codingbooth-<platform>` binaries shipped with the repo. Consumed by A1 (no-network installs) and A3 (forwarded-invocation `exec` target).

### Host-side, ephemeral (per booth lifetime)

- **`.booth/.tmp/`** — wiped on start, cleaned on exit; `--leave-tmp-on-exit` and `--keep-tmp-on-start` for debugging. Primary: B6c. Used by:
  - B6d (`booth-startup.txt` per session)
  - B6b (TCP tunnel control files written by D's `booth--expose`, watched by host)
  - E (lifecycle messages: `booth--restart` / `booth--shutdown` write here; `booth-lifecycle-watcher` reads)
  - B2c (idle Pause/Disable state persisted by F's chip via E's API)
  - B6a (booth message files, list+response)

### Image-side (paths inside the running container)

- **`/usr/share/startup.d/`** — runs on container start as `coder`, idempotent. File convention: `<LEVEL>-cb-<name>--startup.sh` → C3. Written by C setups; executed by `booth-entry` (C5).
- **`/etc/profile.d/`** — runs on every shell. File convention: `<LEVEL>-cb-<name>--profile.sh` → C3. Written by C setups.
- **`/usr/local/bin/`** — `booth--*` runtime helpers (D) and starter wrappers from the C three-artifact pattern.
- **`/home/coder/`** — `coder` user home; UID/GID host-mapped (B1b). With `--persist-home`, backed by a Docker named volume (B1j).
- **`/home/coder/code/`** — bind mount of the user's project directory.
- **`/home/coder/code/booth`** — host wrapper read-only mount inside the container (`cli/src/pkg/booth/booth.go`); lets the in-container user invoke the same `booth` they ran on the host.
- **`/opt/codingbooth/`** — AGENT.md and the symlink farm (CLAUDE.md, COPILOT.md, CURSOR.md, …).
- **`.booth/.tmp/` (in-container view)** — same dir as the host realm above, mounted in. The control-file protocol surface between Parts D, E, and B6.

## C3 — Naming conventions and identifiers

Names that carry semantics. Several layers of code agree on these, so they qualify as components even though they have no file of their own.

### Docker labels (set by B1g, queried by B2 lifecycle commands)

- `cb.managed` — "this container is ours."
- `cb.project` — project name (defaults to cwd basename).
- `cb.variant` — `base` / `codeserver` / `notebook` / `desktop-xfce` / `desktop-kde`.
- `cb.role` — `main` vs sidecar roles (`dind`, `egress`, …).
- `cb.parent` — sidecar → main container linkage.

### Filename / path prefixes

- **`booth--*`** — in-container CLI helpers (D layer). Examples: `booth--expose`, `booth--restart`, `booth--shutdown`, `booth--msg`, `booth--info`, `booth--envs`.
- **`*--setup.sh`** — build-time install scripts (C layer). The double-dash distinguishes them from in-container helpers.
- **`*--install.sh`** — package-install variants of setup scripts (per-language package managers).
- **`*-code-extension--setup.sh`** — code-server VS Code extension installers.
- **`*-nb-kernel--setup.sh`** — Jupyter kernel installers.
- **`<NN>-cb-<name>--startup.sh`** / **`<NN>-cb-<name>--profile.sh`** — the C three-artifact pattern's outputs in `/usr/share/startup.d/` and `/etc/profile.d/`.
- **`CB_*`** — environment-variable namespace for binary config (`CB_LOG_TIME`, etc.) → B1d precedence chain.

### Numeric ordering schemes

- **Setup `LEVEL` (50–79)** for `<LEVEL>-cb-<name>--{startup,profile}.sh`: 50–54 base, 55–59 OS/UI, 60–64 languages, 65–69 language extensions, 70–74 dev tools, 75–79 tool extensions. Verified examples: `53-cb-python--profile.sh`, `55-cb-codeserver--profile.sh`, `60-cb-{aws-cli,gh,gcloud,firebase,azure-cli}--startup.sh`, `61-cb-{aws-sam-cli,clojure}`, `62-cb-cmake`, `70-cb-{claude-code,cloudbeaver,codex}`, `71-cb-gh-copilot`.
- **Boothfile segment ordering (40 / 50 / 60 / 65 / 70 / 90)**: 40 infra, 50 base, 60 dependent, 65 extensions, 70 kernels, 90 post. → B3b, B4b merge rules.

### Internal ports (in-container)

Conventions that nginx, the message API, and per-variant launchers all agree on.

- **10000** — nginx front door (web variants).
- **10001 – 10004** — internal proxy targets (verified via `proxy_pass` in nginx configs).
- **10007** — `booth-message-api-server` (bash + socat HTTP).
- **10099** — noVNC (desktop-xfce, desktop-kde).
- **18888** — JupyterLab inner service.
- **19999** — code-server inner service.

### URL params and markers

- **`_booth_inner=1`** — query param that breaks the `/` → `/booth` redirect loop in F.
- **`# syntax=codingbooth/boothfile:1`** — Boothfile shebang/header (C1).
- **`.mount-this`** — marker file that opts a `.booth/cache/` subtree into the bind-mount (B1k, smart_copy).

## C4 — Go types

Object types in the binary that get threaded through multiple pipeline stages. Verified against `pkg/appctx/`, `pkg/nillable/`, `pkg/ilist/` (2026-04-30).

- **`AppContext`** (`pkg/appctx`) — immutable bundle of run-time state. Read by every B-layer transform.
- **`AppContextBuilder`** (`pkg/appctx`) — mutable counterpart used during construction; produces an `AppContext`.
- **`AppConfig`** (`pkg/appctx`) — the user-visible config slice of context (precedence-merged from defaults / `CB_*` / TOML / CLI).
- **`List[T]` / `AppendableList[T]`** (`pkg/ilist`) — generic immutable list and its mutable builder; mirrors the `AppContext` ↔ `Builder` pairing one level down. Used wherever an `AppContext` carries a slice.
- **`NillableString` / `NillableBool`** (`pkg/nillable`) — pointer-backed optional values for "unset vs. zero" config semantics. Used throughout `AppConfig` and Template parsing.
- **`SemicolonStringList`** (`pkg/nillable`) — semicolon-delimited string list parser; used where TOML or CLI accept a `;`-joined list.

> Other types (Boothfile AST nodes, Template model, Selection DSL parsed structures, run-mode enum) are also cross-feature but sit inside `pkg/boothfile/`, `pkg/boothinit/template/`, and `pkg/boothinit/selection/`. Listing every named struct here would duplicate code; the package is the component for those.

## C5 — Image-baked scripts

Scripts installed into the variant images. Listed by *role* — the same script can be a launcher and a daemon, or a setup *and* a UI asset.

### Variant entry / launchers

- **`booth-entry`** — variant container entry point; runs everything in `/usr/share/startup.d/` and execs the variant's main process.
- **`start-ttyd`**, **`start-ttyd-split`** — base variant launchers.
- **`start-booth-wrapped`** — generic wrapper: starts `booth-message-api-server` + inner service + nginx. Cross-listed with C7 (it's the seam where the messaging UI hooks in).
- **`start-codeserver-wrapped`**, **`start-notebook-wrapped`**, **`start-xfce-wrapped`**, **`start-kde-wrapped`** — per-variant wrappers around `start-booth-wrapped`. Generated by per-variant `booth-message-*-wrapped--setup.sh`.

### Setup pattern (build time)

The C three-artifact pattern: each `*--setup.sh` may emit a *startup* script, a *profile* script, and a *starter* wrapper. The pattern itself — same naming, same `LEVEL` ordering, same idempotency contract — is the cross-cutting component, more so than any individual setup. 152 of the 186 scripts in `variants/base/setups/` follow it.

- `booth-message-wrapper--setup.sh` — installs the shared messaging infra (`start-booth-wrapped`, `booth-message-api-server`, `booth-message-overlay.html`, nginx config). Cross-listed: C5 (it's a setup) and C7 (its outputs are UI assets) and C6 (one of its outputs is a daemon).
- The `booth-message-{codeserver,notebook,desktop}-wrapped--setup.sh` trio fills in per-variant wiring; same dual citizenship.

### In-container CLI helpers (D layer)

Cross-listed because their *implementations* are scripts (this layer) while their *role* is user-facing (D). Each shells back to host or talks to the C6 message API server.

- **`booth--expose`** → B6b host watcher.
- **`booth--restart`** → C6 `booth-lifecycle-watcher`.
- **`booth--shutdown`** → C6 `booth-lifecycle-watcher`.
- **`booth--msg`** → C6 message API server.
- **`booth--info`** — read-only.
- **`booth--envs`** — read-only.

### Image-side helpers

- **`smart_copy`** — image-side copy helper used by Template seeding (B1j) and cache mirror (B1k).
- **`cb-has-desktop*.sh`** — desktop variant probes used during build and runtime.

## C6 — Long-lived processes

Running instances. Some are scripts from C5; some are external programs the image installs. They earn a separate listing because their *protocol surface* (sockets, control files, message queues) is what other components couple to.

### In-container daemons

- **`booth-message-api-server`** (bash + socat at `:10007`, served at `/booth-messages/api/`) — protocol bridge between F (web overlay) and `.booth/.tmp/` message files. Consumed by D (`booth--msg`), F (overlay JS), B6a (host CLI via the same path).
- **`booth--idle-monitor`** — detects activity from F via the message API; persists Pause/Disable to `.booth/.tmp/` for B2c.
- **`booth-timer-notifier`** — surfaces session timer events into the web UI via the same message API.
- **`booth-lifecycle-watcher`** — watches `.booth/.tmp/` for `booth--restart` / `booth--shutdown` writes and acts on them inside the container.
- **`ttyd`**, **`nginx`** — base variant terminal + reverse proxy.
- **`code-server`** (`:19999`), **JupyterLab** (`:18888`), **noVNC** (`:10099`) — per-variant inner services.

### Sidecar containers

- **DinD daemon** (`--dind`) — Docker daemon in a sibling container; linked via `cb.parent`.
- **Envoy egress proxy** (`--egress`) — domain allowlist enforcement; iptables redirects container traffic through it.

### Host-side watchers

- **TCP tunnel watcher** (`pkg/booth/tcp_tunnel.go`) — tails `.booth/.tmp/tcp-tunnels/` control files, sets up `socat` listeners on the host for B6b.

## C7 — Web UI assets

Browser-rendered surface served from inside the booth. Cross-listed with C5 where the same file is also a build-time install target.

- **`booth-message-overlay.html`** — shared overlay CSS/JS (modal/toast/banner primitives). Loaded by every web variant. Source: `variants/base/setups/booth-message-overlay.html`. Cross-listed: C5.
- **`web-ttyd-split/index.html`** — base variant console UI: terminal split + overlay + proxy toggle (globe button).
- **`web-ttyd-split/login.html`** — base variant login page, served at `/login` when `PASSWORD` is set. Prefills the username with `coder`; posts the credential to `/booth-messages/api/login` to obtain the `booth_auth` cookie.
- **`web-ttyd-split/nginx.conf.template`** — nginx template with `/`, `/booth`, `/booth-messages/api/`, catch-all proxy, and `/proxy/{port}/` regex location. Also carries the session gate (see C9).
- **Per-variant wrapper integration** — output of the `booth-message-*-wrapped--setup.sh` trio: per-variant `start-*-wrapped` launcher + nginx config + `_booth_inner=1` redirect handling. Cross-listed: C5.
- **localStorage keys** — `cb.webSplit.{project}.proxy` and friends; cross-tab UI state convention (lightweight identifier, could also live in C3).

## C8 — Contributor-only artifacts

In the repo, never shipped to users.

- **`on-board-me.sh`** — installs `.githooks/pre-commit`.
- **`.githooks/pre-commit`** — enforces `version.txt` ↔ `README.md` consistency.
- **`build/cli-build.sh`**, **`build/docker-build.sh`**, **`build/build-all.sh`** — release build pipeline.
- **`tests/`** subtree — `unit/`, `basic/`, `boothfile/`, `config/`, `complex/`, `dryrun/`, `manual/`, `extra/`, `logs/`, plus the `run-*-tests.sh` orchestrators and `common--source.sh`.
- **`experiments/`** — `test-init-tui`, `tui-go` (egress / spike code).
- **`doc/`** — internal brainstorm docs (`feature-raw.md`, `feature-split-1.md`, `component-raw.md`, this file, `ARCHITECURE.md` placeholder). Distinct from `docs/` (user-facing guides), which ships.

## C9 — Base UI session gate

Only active when `PASSWORD` is set (the CLI injects it for `--public`). With no password every piece below collapses to a no-op and the UI is open, exactly as an unauthenticated booth has always been.

- **`booth_auth` cookie** — the session credential. Value is 32 random bytes, hex-encoded, minted once per container start by `start-ttyd-split`. `HttpOnly`, `SameSite=Strict`, plus `Secure` when `BOOTH_TLS=true`. Restarting a booth invalidates outstanding sessions.
- **`$booth_auth_ok`** — nginx map over `$cookie_booth_auth`. `default 0` plus the one live token when a password is set; the whole map is replaced by `default 1` when there is none. Requires `map_hash_bucket_size 128`, declared *before* any `map` block — nginx rejects a later one as a duplicate, and a 64-character token does not fit the default bucket.
- **Gate placement** — `/`, `/s1..s4/` and `/proxy/{port}/` redirect to `/login`; `/booth-messages/api/` returns 401 instead, because the overlay reaches it with `fetch` and a redirect would hand it the login page as "JSON". `/login` and `/booth-messages/api/login` are the two ungated paths.
- **`absolute_redirect off`** — mandatory. nginx would otherwise build the gate's `Location` from the port it listens on (10000, or 10443 behind Caddy) rather than the published host port, sending the browser to a port that is not there.
- **Upstream credential** — nginx injects `Authorization: Basic base64(coder:$PASSWORD)` toward each ttyd. ttyd keeps its own `-c` credential, so the panes are still protected on 10001–10004, but the browser never receives ttyd's 401 and therefore never opens the native Basic-auth dialog — which is the point: that dialog's username box cannot be prefilled by a server.
- **`POST /booth-messages/api/login`** — handled by `booth-message-api-server`. Fields arrive base64-encoded so quoting in a password cannot break the bash JSON parsing. Compares against `$PASSWORD`, sleeps 1s on a miss, replies `Set-Cookie` on a match.
---

## Open questions

- Is the `.booth/` directory listing in C2 complete? Subtrees not surveyed: `.booth/Dockerfile` (if Boothfile-compiled), `.booth/setups/`, anything Template-specific I missed.
- C4 stops at the truly cross-cutting low-level types. Worth adding `pkg/boothfile/` AST and `pkg/boothinit/template/` model as named components, or is package-level granularity right?
- C6 lists processes; should there be a sibling list of *protocols* (control-file shape under `.booth/.tmp/`, message API verbs, label-query patterns)? Currently mixed into C2 / C3.
- The `cb.*` localStorage namespace in F is a one-off mention. If there are more web-UI conventions, they probably want their own subsection in C3.
