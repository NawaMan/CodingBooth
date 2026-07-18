# CodingBooth Architecture

CodingBooth delivers **reproducible, isolated development environments as Docker
containers**. A project carries a small `.booth/` folder and a `booth` launcher;
running it drops you into a container that mirrors your host identity, serves a
terminal / IDE / desktop in the browser (or a plain shell), and throws the
container away when you are done. Your code stays on the host; the environment
is rebuilt from a recipe every time.

This document describes how the pieces fit together. It is the canonical
architecture reference; the companion brainstorm notes in this directory
(`feature-raw.md`, `feature-split-1.md`, `component-raw.md`,
`component-split-1.md`) are the raw inventories it was distilled from, and the
user-facing guides live in `../docs/` (`BOOTH_*.md`) with internals under
`../docs/implementations/`.

> Facts below were verified against the tree at **v0.61.0-rc1**: 149 Go files
> under `cli/src`, 294 TOML templates, 213 setup scripts, 7 image variants.
> Counts drift; the shapes do not.

---

## Table of contents

1. [The big picture](#1-the-big-picture)
2. [Repository layout](#2-repository-layout)
3. [Layer A — the `booth` wrapper](#3-layer-a--the-booth-wrapper)
4. [Layer B — the `codingbooth` binary](#4-layer-b--the-codingbooth-binary)
5. [The run pipeline](#5-the-run-pipeline)
6. [Configuration model — the carriers](#6-configuration-model--the-carriers)
7. [The template / init system](#7-the-template--init-system)
8. [Images and variants](#8-images-and-variants)
9. [The in-container runtime surface](#9-the-in-container-runtime-surface)
10. [Web UI and the messaging bus](#10-web-ui-and-the-messaging-bus)
11. [Networking, ports, and sidecars](#11-networking-ports-and-sidecars)
12. [Filesystem realms and persistence](#12-filesystem-realms-and-persistence)
13. [Naming conventions and identifiers](#13-naming-conventions-and-identifiers)
14. [Build, release, and testing](#14-build-release-and-testing)
15. [Design principles](#15-design-principles)

---

## 1. The big picture

CodingBooth is **three layers stacked on Docker**:

```
┌──────────────────────────────────────────────────────────────────┐
│  Layer A — booth (bash wrapper, ~26 KB)                           │
│  Lives in each project. Installs/updates/verifies the binary,     │
│  writes .gitignore guards, then exec's the binary with your argv. │
└───────────────────────────────┬──────────────────────────────────┘
                                │ exec codingbooth <argv>
┌───────────────────────────────▼──────────────────────────────────┐
│  Layer B — codingbooth (Go binary, 149 .go files)                 │
│  All real orchestration: parse config → build/pull image →        │
│  compute ports/mounts/labels → start sidecars → docker run.       │
│  Shells out to the docker CLI; never links a Docker client lib.   │
└───────────────────────────────┬──────────────────────────────────┘
                                │ docker build / docker run
┌───────────────────────────────▼──────────────────────────────────┐
│  Layer C — the image + in-container runtime                       │
│  A variant image (base/codeserver/notebook/desktop-*) baked from  │
│  ~213 setup scripts. booth-entry maps host UID/GID onto `coder`,  │
│  runs startup.d, and execs the variant's main process (ttyd /     │
│  code-server / Jupyter / noVNC), all fronted by nginx + a web      │
│  overlay for messaging and lifecycle control.                     │
└──────────────────────────────────────────────────────────────────┘
```

The **unit of reproducibility** is the `.booth/` directory that travels inside
the project repo. It holds the config, the build recipe (`Boothfile` or
`Dockerfile`), home/cache seeds, the pinned binary version, and ephemeral
runtime state. Given the same `.booth/`, any machine with Docker reproduces the
same environment (subject to the tiered reproducibility stance — see
`../docs/REPRODUCIBILITY.md`).

Two properties define the user experience and drive most of the design:

- **Host-identity mirroring.** The launcher passes `HOST_UID`/`HOST_GID` in;
  `booth-entry` creates a matching `coder` user so files created in the
  container are owned by *you*, not root. All work runs as the unprivileged
  `coder` (passwordless sudo). See `../docs/HOW_IT_WORKS.md`.
- **Disposable containers, persistent recipe.** Only `/home/coder/code`
  (bind-mounted project) and explicitly-cached paths survive a restart.
  Everything else is rebuilt from the image, so "fix it in the Dockerfile,"
  not "fix it in the container."

---

## 2. Repository layout

```
CodingBooth/
├── booth                     # Layer A: the bash wrapper (shipped per project)
├── install.sh                # one-liner bootstrap that lands the wrapper
├── version.txt               # single-source version string (e.g. 0.61.0--rc1)
│
├── cli/                      # Layer B: the Go source
│   └── src/
│       ├── cmd/codingbooth/  # command dispatch (main.go + one file per verb)
│       └── pkg/              # the orchestration packages (see §4)
│
├── variants/                 # Layer C: image recipes
│   ├── base/
│   │   ├── Dockerfile        # the base image everything derives from
│   │   ├── booth-entry       # container entrypoint (UID map, startup.d, exec)
│   │   ├── setups/           # ~213 build-time install scripts (*--setup.sh)
│   │   └── web-ttyd-split/   # console UI: index.html + nginx.conf.template
│   ├── codeserver/           # VS Code in the browser
│   ├── notebook/             # JupyterLab
│   ├── desktop-xfce/         # noVNC desktop (X11)
│   ├── desktop-kde/          #   "
│   ├── desktop-lxqt/         #   "
│   └── desktop-wayland/      # labwc + wayvnc (Wayland) desktop
│
├── templates/                # 294 TOML template definitions, by category:
│   ├── languages/ databases/ ides/ tools/ ai-tools/
│   └── browsers/ desktops/ education/     (+ meta.toml per dir)
│
├── examples/                 # ready-to-run example workspaces + demo
├── build/                    # cli-build.sh, docker-build.sh, build-all.sh
├── bin/                      # pre-compiled multi-platform binaries
├── tests/                    # unit/ basic/ boothfile/ config/ complex/ dryrun/ …
│
├── docs/                     # SHIPPED user guides (BOOTH_*.md) + implementations/
├── doc/                      # internal design notes (this file + brainstorms)
├── blog/  site/              # Svelte blog + marketing site (codingbooth.io)
└── experiments/              # spikes (e.g. desktop-gnome go/no-go scripts)
```

Note the two doc roots: **`docs/`** ships to users and into the image at
`/opt/codingbooth/`; **`doc/`** is internal and stays in the repo.

---

## 3. Layer A — the `booth` wrapper

`booth` is a self-contained bash script committed into every project. Its job is
everything that must work *before and around* the binary — including on a
machine that has never seen CodingBooth. It is **location-based**: it resolves
`.booth/` relative to its own path, so `/path/to/project/booth` works from any
cwd.

Its work splits three ways:

- **Binary lifecycle (does not invoke the binary).** `install` / `update` /
  `uninstall`, plus `tools-cache list|clean`. It downloads the right
  `codingbooth-<os>-<arch>` binary, verifies it against a `.sha256`, and pins
  the choice in `.booth/tools/codingbooth.lock` (`version=`, `downloaded_at=`,
  `cache=`). Binaries live in a **shared cache** (`~/.cache/codingbooth/` on
  Linux, `~/Library/Caches/…` on macOS, `%LOCALAPPDATA%\…` on Windows) or a
  **local** `.booth/tools/`, selected via `--cache`.
- **Wrapper-self behavior.** `help`, the version banner, and guards like
  nested-booth detection — all handled before any network path so they work
  offline.
- **Forwarding.** Anything else runs a pre-exec gauntlet (read lock → detect
  platform → locate/verify binary, auto-downloading if missing → maintain the
  `booth → codingbooth-<platform>` symlink) and then `exec`s the binary with
  the original argv. The wrapper does **no** parsing of forwarded args.

The wrapper also writes `.booth/.gitignore` — a responsibility it shares with
the binary's scaffolder (`pkg/boothinit/output`); the two writers must stay in
sync. The same `booth` script is bind-mounted read-only into the container at
`/home/coder/code/booth`, so code running *inside* the booth can invoke the
identical launcher.

---

## 4. Layer B — the `codingbooth` binary

A Go 1.24 binary (module `github.com/nawaman/codingbooth`), deliberately
minimal in dependencies (`BurntSushi/toml`, `golang.org/x/term`). It talks to
Docker by shelling out to the `docker` CLI — no client library — which keeps it
portable and easy to reason about.

### 4.1 Command dispatch

`cmd/codingbooth/main.go` is a flat switch; each verb has its own file:

| Verb(s)                                            | File                | Package used            |
|----------------------------------------------------|---------------------|-------------------------|
| `run` (and the default)                            | `run.go`            | `pkg/booth`             |
| `list` `start` `stop` `restart` `remove` `prune`   | `lifecycle_cmd.go`  | `pkg/lifecycle`         |
| `shell` `exec`                                     | `lifecycle_cmd.go`  | `pkg/lifecycle`         |
| `home-volume-list` `-export` `-import`             | `lifecycle_cmd.go`  | `pkg/lifecycle`         |
| `message`                                          | `lifecycle_cmd.go`  | `pkg/lifecycle`         |
| `config`                                           | `config.go`         | `pkg/boothinit`         |
| `template`                                         | `template.go`       | `pkg/boothinit`         |
| `example`                                          | `example.go`        | `pkg/boothinit`         |
| `build`                                            | `build.go`          | `pkg/booth`, `pkg/docker` |
| `emit-dockerfile`                                  | `emit.go`           | `pkg/boothfile`         |
| `print-default-allowlist.txt`                      | `print_default_allowlist.go` | `pkg/booth`    |
| `tools-cache` (help shim; real work in wrapper)    | `tools_cache.go`    | —                       |
| `version` `help`                                   | `version.go` `help.go` | —                    |

`init.go` / `init_guard.go` hold the shared setup that turns raw argv +
`.booth/` + environment into the immutable `AppContext` every command consumes.

### 4.2 Packages (`cli/src/pkg/`)

| Package        | Responsibility |
|----------------|----------------|
| **`appctx`**   | `AppContext` (immutable run-time state), its `AppContextBuilder`, and `AppConfig` (the precedence-merged config slice). The spine everything is threaded through. |
| **`booth`**    | The orchestration pipeline: image ensure, port logic, DinD/egress sidecars, env-file, `.booth/.tmp` lifecycle, build hashing, the TCP-tunnel host watcher, and the final `docker run`. See §5. |
| **`boothinit`**| The template engine and scaffolder: `template/` (load/model/search), `selection/` (the DSL parser), `compiler/` (template → Boothfile/Dockerfile), `output/` (file emission), `cache/`, and `tui/` (the `booth config` terminal UI). |
| **`boothfile`**| Parser + compiler for the Boothfile DSL. |
| **`docker`**   | The `docker` CLI wrapper — BuildKit/buildx, TTY handling, dry-run/verbose command printing. |
| **`lifecycle`**| Everything that operates on already-built/running booths: list/start/stop/restart/remove/prune, `shell`/`exec` connect, the `message` CLI, and persist-home volumes. |
| **`ilist`**    | Generic immutable `List[T]` + its `AppendableList[T]` builder. |
| **`nillable`** | Pointer-backed optionals (`NillableString`/`NillableBool`) for "unset vs. zero" config semantics, plus `SemicolonStringList`. |
| **`shellexpand`** | `${VAR:-default}`-style expansion used when parsing config values (e.g. expose ports). |
| **`defaults`** | Default config values — the bottom of the precedence chain. |

### 4.3 The immutability pattern

CodingBooth models configuration as **immutable values threaded through pure
transforms**. Two paired abstractions recur:

- `AppContext` ↔ `AppContextBuilder` — read-only context vs. its mutable builder.
- `List[T]` ↔ `AppendableList[T]` — the same pairing one level down, for slices.

Every pipeline stage takes an `AppContext` and returns a *new* one
(`ctx = Stage(ctx)`). Nothing mutates shared state in place, which makes the run
sequence easy to read as data flow and easy to unit-test stage-by-stage.

---

## 5. The run pipeline

`booth run` (the default verb) is the heart of the binary. `BoothRunner.Run()`
in `pkg/booth/booth_runner.go` applies an ordered series of `AppContext`
transforms and then hands off to `docker run`. The order is load-bearing:

```
ValidateVariant          resolve variant name/alias → one of the 7 (or error)
      │
EnsureDockerImage        build (from Boothfile/Dockerfile) or pull if missing
      │
PortDetermination        pick the host port (explicit / NEXT / RANDOM)
ResolveRelativePorts     turn +OFFSET / ${VAR:-…} expose forms into real ports
NormalizePortMappings    canonicalize all host:container mappings
      │
ShowDebugBanner          (dryrun/verbose) print what is about to happen
      │
SetupDind                if --dind: network + Docker-daemon sidecar
SetupEgress              if --egress: Envoy proxy sidecar + iptables allowlist
      │
PrepareRunMode           DAEMON | FOREGROUND | COMMAND
FilterMissingVolumeMounts drop -v sources that don't exist on the host
PrepareBoothTmp          wipe/recreate .booth/.tmp for this session
ApplyEnvFile             expand .booth/.env (+ --env-file) into .booth/.tmp
                         (deliberately AFTER PrepareBoothTmp so it survives)
PrepareCommonArgs        assemble the final docker-run argv (labels, mounts, …)
      │
ensureContainerNameAvailable   refuse to collide with an existing container
      │
NewBooth(ctx).Run(mode) →  docker run
```

**Run modes** (chosen in `PrepareRunMode`):

- **DAEMON** (`--daemon`) — detached; container keeps running, managed via the
  lifecycle commands.
- **FOREGROUND** — no command given; attach to the variant's main process (the
  common interactive case).
- **COMMAND** (`booth -- <cmd>`) — run one command, forward its exit code, exit.

Two orderings inside the pipeline encode real bugs-avoided and are worth
remembering: `ApplyEnvFile` runs *after* `PrepareBoothTmp` so the expanded env
file it writes into `.booth/.tmp/` isn't immediately wiped; and port resolution
is a three-step chain (`determine → resolve-relative → normalize`) because
`${VAR:-+OFFSET}` fallbacks are expanded at TOML-unmarshal time and only *then*
rewritten against the booth port.

---

## 6. Configuration model — the carriers

Configuration flows through a **fixed precedence chain**, lowest to highest:

```
defaults  →  CB_* env vars  →  .booth/config.toml  →  CLI flags
```

The heavy lifting is done by a handful of **carriers** — single artifacts whose
contents fan out into many features:

| Carrier | Parsed by | What it drives |
|---------|-----------|----------------|
| **`.booth/config.toml`** | `pkg/appctx` / `pkg/boothinit` | Persistent per-project config: variant, ports, mounts, `dind`, `run-args`, `build-args`, pinned template `arg` values. Written by the `config` TUI, read on every run. |
| **`Boothfile`** | `pkg/boothfile` | Build recipe DSL (`# syntax=codingbooth/boothfile:1`) with `setup`/`install`/`run`/`env`/`copy`/`expose` directives. Compiled to a Dockerfile; skips setups the base variant already provides. |
| **Template** (`templates/**/*.toml`) | `pkg/boothinit/template` | The 294 declarative building blocks the scaffolder composes. Emits into the Boothfile, config, home/cache seeds, and `.booth/startups/`. See §7. |
| **Recipe** (`.recipe`) | `pkg/boothinit` | A multiline, `+`-continuation wrapper over the selection DSL, loadable via `@file` / `@@url` / stdin. |
| **`.booth/.env`** | `pkg/booth/apply_env_file.go` | Auto-loaded environment, **gitignore-enforced** (`git check-ignore` must confirm it is ignored, or the run refuses). Layered before any explicit `--env-file`. |
| **`codingbooth.lock`** | the wrapper | Pins the binary version; committed to the repo. |
| **`version.txt`** | everything | The single source of the version string, propagated to the banner, the image, and the `cb.*` run-time labels. |

`AppConfig` inside `appctx` is where these collapse into one precedence-merged
value; `nillable` types let it distinguish "unset" from "false/empty" so a
lower-priority source isn't clobbered by an absent higher-priority one.

Details: `../docs/BOOTH_CONFIG.md`, `BOOTH_VARS.md`, `BOOTH_EXPOSE.md`,
`implementations/BOOTHFILE.md`.

---

## 7. The template / init system

`booth config` scaffolds a `.booth/` from **templates**. This is `pkg/boothinit`,
the largest subsystem.

- **Selection DSL** (`selection/`) — a compact grammar like
  `go:1.25+linter/python:3.13+uv/notebook`: `/`-separated selections, `name:version`
  pins, `+extension` add-ons. `booth config --select …` and `.recipe` files
  both feed it.
- **Templates** (`templates/`) — TOML files grouped by category (`languages/`,
  `databases/`, `ides/`, `tools/`, `ai-tools/`, `browsers/`, `desktops/`,
  `education/`, each with a `meta.toml`). A template declares Boothfile
  segments, config scalars/arrays, home/cache seeds, startup segments, and its
  required extensions.
- **Merge rules** — when several templates combine: **scalars must agree** (a
  conflict is an error, not a silent override), **arrays combine and dedup**,
  and everything is emitted in **segment order** so infrastructure lands before
  the things that depend on it:

  | Segment | 40 | 50 | 60 | 65 | 70 | 90 |
  |---------|----|----|----|----|----|----|
  | Role | infra | base | dependent | extensions | kernels | post |

- **Compiler + output** (`compiler/`, `output/`) — resolve the selection, merge
  templates, and emit `.booth/` files (Boothfile/Dockerfile, `config.toml`,
  `startups/NN-name--startup.sh`, home/cache seeds, `.gitignore`).
- **TUI** (`tui/`) — the interactive `booth config`: category browsing, a
  multi-tab layout with live preview, cycle-field edit mode, and round-trip
  editing of existing configs. `--no-tui` drives the same engine headlessly.

Reference: `../docs/BOOTH_CONFIG_TUI.md`, `implementations/BOOTHINIT.md`,
`../docs/BOOTH_EXAMPLE.md`.

---

## 8. Images and variants

All images derive from **`variants/base`**, which bakes the common toolset
(bash/zsh/tini, curl/wget/httpie, git/gh/tig, editors, jq/yq/tree,
ca-certificates/locales/sudo, socat) plus `booth-entry` and the whole
`setups/` + web-overlay machinery. The 7 variants differ only in the **main
process** they front in the browser:

| Variant | Inner surface | Delivery |
|---------|---------------|----------|
| `base` | ttyd terminal | console UI (split terminal + proxy pane) over nginx |
| `codeserver` | VS Code (code-server, `:19999`) | wrapped behind nginx + overlay |
| `notebook` | JupyterLab (`:18888`) | wrapped behind nginx + overlay |
| `desktop-xfce` / `desktop-kde` / `desktop-lxqt` | X11 desktop via noVNC (`:10099`) | wrapped behind nginx + overlay |
| `desktop-wayland` | labwc + wayvnc → websockify → noVNC | wrapped behind nginx + overlay |

Everything after `base` — the ~213 scripts in `variants/base/setups/` — is the
**setup layer**: language toolchains, package-manager installers
(`*--install.sh`), cloud CLIs, IDEs, AI tools, code-server extensions
(`*-code-extension--setup.sh`), Jupyter kernels (`*-nb-kernel--setup.sh`), and
desktop bits. A setup runs once at build time (as root) and follows the
**three-artifact pattern**: it may drop a *startup* script, a *profile* script,
and/or a *starter wrapper* (see §9 and §13).

> A `desktop-gnome` (real GNOME on Wayland) variant was prototyped and **parked**
> on branch `wip/desktop-gnome-webrtc` — it needs systemd-as-PID1 to run
> logind/grd. The full write-up is `../docs/implementations/DESKTOP_GNOME_WAYLAND.md`.
> `desktop-wayland` (labwc + wayvnc) is the shipped Wayland answer.

Reference: `../docs/BOOTH_VARIANTS.md`, `implementations/VARIANTS.md`,
`implementations/DESKTOP_NOVNC.md`.

---

## 9. The in-container runtime surface

Once `docker run` starts, `booth-entry` is PID 1's payload:

1. Ensure a `coder` user/group with the host's UID/GID; own `/home/coder` and
   `/home/coder/code`; grant passwordless sudo; write `.bashrc`/`.zshrc`.
2. **Seed the home directory** from four sources, in order — team defaults
   (`.booth/home-seed/`, no-clobber), team overrides (`.booth/home/`), host
   personal defaults (`/etc/cb-home-seed/`, no-clobber), host personal overrides
   (`/etc/cb-home/`). A `.mount-this` marker copies a directory as a unit;
   without it, only individual files are seeded and subdirs recursed.
3. Run **startup scripts** — system scripts in `/usr/share/startup.d/` then user
   scripts in `.booth/startups/` — idempotently, as `coder`.
4. `exec` the variant's main process.

Key image-side realms and conventions:

- **`/usr/share/startup.d/<LEVEL>-cb-<name>--startup.sh`** — runs on start.
- **`/etc/profile.d/<LEVEL>-cb-<name>--profile.sh`** — runs on every shell.
- **`/usr/local/bin/booth--*`** — in-container CLI helpers: `booth--expose`
  (request a runtime TCP tunnel), `booth--restart`, `booth--shutdown`,
  `booth--msg`, `booth--info`, `booth--envs`. These write control files into
  `.booth/.tmp/` or call the message API; the host side reacts.
- **`/opt/codingbooth/`** — in-image docs plus `AGENT.md` and its symlink farm
  (`CLAUDE.md`, `COPILOT.md`, `CURSOR.md`, …) so AI agents self-onboard.

**In-container daemons** (started by the variant wrappers):

- `booth-message-api-server` — bash + socat HTTP bridge at `:10007`
  (`/booth-messages/api/`) between the web overlay and message files in
  `.booth/.tmp/`. The hub of the messaging system.
- `booth--idle-monitor` — watches web-UI activity, persists idle Pause/Disable
  state for auto-shutdown.
- `booth-timer-notifier` — pushes session-timer events into the UI.
- `booth-lifecycle-watcher` — acts on `booth--restart` / `booth--shutdown`
  writes from inside the container.

Reference: `../docs/BOOTH_SETUP.md`, `BOOTH_RUNTIME.md`, `BOOTH_HOME.md`,
`BOOTH_MESSAGE.md`, `implementations/WRAPPER.md`, `USER_PERMISSIONS.md`.

---

## 10. Web UI and the messaging bus

The web variants share one presentation layer, served from inside the booth and
fronted by **nginx** (front door on `:10000`):

- **Console UI** (`variants/base/web-ttyd-split/index.html`) — split terminal
  plus a **web proxy pane**: nginx exposes `/proxy/{port}/` (rewriting bodies via
  `sub_filter`, stripping `X-Frame-Options`/CSP) and the UI toggles an iframe or
  opens it in a new tab, so a service on an internal port is viewable without a
  host mapping.
- **Message overlay** (`booth-message-overlay.html`) — modal / toast / banner
  primitives loaded by every web variant. It speaks to the message API server
  and renders yes-no / ok / text / password / choice / radio / checkbox / toast
  messages.
- **Lifecycle panel** — Restart / Shut Down buttons, session-timer display, and
  the idle Pause/Disable chip, all routed back through the message system to the
  in-container daemons and the host.
- **"Container stopped" page** — shown across all web variants when the booth
  ends.

The **messaging bus** is the connective tissue: browser overlay ↔
`booth-message-api-server` ↔ control files in `.booth/.tmp/` ↔ host-side
`booth message` CLI and watchers. It is how a click in the browser becomes a
container action, and how a host-side event becomes a prompt in the browser.
Per-variant wiring is generated by the
`booth-message-{codeserver,notebook,desktop}-wrapped--setup.sh` scripts, which
wrap each variant's inner service in `start-*-wrapped` launchers.

Reference: `../docs/BOOTH_MESSAGE.md`, `BOOTH_UI_OVERLAY.md`, `BOOTH_IDLE.md`,
`BOOTH_HEALTH.md`.

---

## 11. Networking, ports, and sidecars

- **Ports.** A booth publishes one host port for its web front door, chosen
  explicitly (`--port N`), as the next free port (`NEXT`), or at `RANDOM`.
  Additional `--expose` mappings support **booth-relative offsets** (`+300`) and
  **env fallbacks** (`${SERVER_PORT:-+300}:1234`), resolved by the
  determine → resolve-relative → normalize chain in §5.
- **Runtime TCP tunnels.** `booth--expose` (in-container) writes a control file
  under `.booth/.tmp/`; the host-side watcher (`pkg/booth/tcp_tunnel.go`) tails
  it and stands up a `socat` listener on the host — a tunnel created *after* the
  container is already running. `--permanent` persists it into config.
- **Docker-in-Docker** (`--dind`, `pkg/booth/dind_setup.go`) — a sibling Docker
  daemon container on a dedicated network, linked to the main container via the
  `cb.parent` label.
- **Egress filtering** (`--egress`, `pkg/booth/egress_setup.go`) — an Envoy
  forward-proxy sidecar plus iptables rules that force outbound traffic through
  a domain allowlist (`--egress-allowlist[-file]`, `--egress-policy-file`; a
  built-in default from `print-default-allowlist.txt`). Not compatible with
  `--dind`.

Reference: `../docs/BOOTH_EXPOSE.md`, `implementations/DIND.md`,
`implementations/EGRESS.md`.

---

## 12. Filesystem realms and persistence

What survives a restart is deliberate and small:

| Realm | Persists? | Notes |
|-------|-----------|-------|
| `/home/coder/code/` | **Yes** | Bind mount of your project; the source of truth. |
| `/home/coder/` (rest) | Opt-in | Ephemeral unless backed by `--persist-home` (a Docker named volume) or mirrored via `.booth/cache/`. |
| `/opt`, `/usr`, `/etc`, installed pkgs | No | Rebuilt from the image; put lasting changes in the Boothfile/Dockerfile. |

Host-side `.booth/` subtrees:

- `config.toml`, `Boothfile`/`Dockerfile`, `.env`, `tools/codingbooth.lock` —
  the committed recipe (`.env` is gitignored).
- `startups/NN-name--startup.sh` — template-emitted per-session startup.
- `home/`, `home-seed/` — home seeding sources (§9).
- `cache/` — a host mirror of selected container paths, auto-bind-mounted;
  `.mount-this` markers and `smart_copy` control what is included (shell
  history, tool configs, `~/.claude/`, etc.).
- `.tmp/` — **ephemeral**, wiped on start and cleaned on exit
  (`--leave-tmp-on-exit` / `--keep-tmp-on-start` for debugging). It is the
  shared surface for the messaging bus, TCP-tunnel control files, idle state,
  and `booth-startup.txt` session metadata.

Reference: `../docs/BOOTH_HOME.md`, `BOOTH_PERSIST_HOME.md`,
`BOOTH_LOCALCACHE.md`, `BOOTH_TMP.md`.

---

## 13. Naming conventions and identifiers

Several layers of code agree on these names, so they behave like components in
their own right:

**Docker labels** (set at run, queried by lifecycle commands):
`cb.managed` (ours), `cb.project`, `cb.variant`, `cb.role` (main vs. sidecar),
`cb.parent` (sidecar → main linkage).

**Filename prefixes:** `booth--*` (in-container helpers), `*--setup.sh`
(build-time installers — the double dash distinguishes them from helpers),
`*--install.sh` (package installers), `*-code-extension--setup.sh`,
`*-nb-kernel--setup.sh`, `<NN>-cb-<name>--{startup,profile}.sh`. `CB_*` is the
env-var namespace for binary config.

**Ordering schemes:** the setup **`LEVEL`** (50–79: base → OS/UI → languages →
language-extensions → dev-tools → tool-extensions) sequences startup/profile
scripts; the **Boothfile segment** numbers (40/50/60/65/70/90) sequence template
merges (§7).

**Internal ports:** `10000` nginx front door, `10001–10004` proxy targets,
`10007` message API, `10099` noVNC, `18888` JupyterLab, `19999` code-server.

**Markers:** `_booth_inner=1` (URL param that breaks the `/` → `/booth` redirect
loop), `.mount-this` (opt a cache subtree into the bind mount),
`# syntax=codingbooth/boothfile:1` (Boothfile header).

---

## 14. Build, release, and testing

- **Build.** `build/cli-build.sh` cross-compiles the binary into `bin/`;
  `build/docker-build.sh <variant…>` builds images
  (`nawaman/codingbooth:<variant>-<version>`); `build/build-all.sh` does the
  full matrix. `booth build [--push]` builds/pushes a project's own image, and
  `emit-dockerfile` prints the compiled Dockerfile for inspection.
- **Versioning.** `version.txt` is the single source; a `.githooks/pre-commit`
  (installed by `on-board-me.sh`) enforces `version.txt` ↔ `README.md`
  consistency. Note `CODINGBOOTH.md` currently lags the changelog — trust
  `version.txt` and `docs/CHANGELOG.md`.
- **Tests.** `tests/` is shell-driven end-to-end coverage —
  `unit/ basic/ boothfile/ config/ complex/ dryrun/ manual/ extra/` — plus the
  Go unit tests co-located with their packages (`*_test.go`). Orchestrators:
  `tests/run-automate-tests.sh`, `run-manual-tests.sh`, `run-example-tests.sh`,
  `sanity-test.sh`.

Reference: `../docs/BOOTH_BUILD.md`, `implementations/EXAMPLES.md`,
`../docs/CODESTYLE.md`.

---

## 15. Design principles

The recurring decisions that explain *why* the code looks as it does:

1. **The recipe is the artifact, the container is disposable.** Reproducibility
   lives in `.booth/`, not in a long-lived container. Every design choice pushes
   state either onto the host (your code) or into the build recipe.
2. **Immutable data, pure transforms.** `AppContext`/`Builder` and
   `List`/`AppendableList` make the run a readable data pipeline and keep stages
   independently testable.
3. **Shell out to `docker`, don't embed it.** Portability and legibility over a
   client library.
4. **Host identity is sacred.** UID/GID mirroring and the unprivileged `coder`
   user mean no root-owned files and no permission theater.
5. **One messaging bus, many surfaces.** Terminal, browser overlay, desktop
   dialogs, and host CLI all speak through the message API + `.booth/.tmp/`
   control files, so a new surface reuses the existing plumbing.
6. **Templates compose, they don't conflict.** Scalar-must-agree + array-dedup +
   segment ordering make it safe to stack many small templates into one image.
7. **Layered, offline-friendly front door.** The bash wrapper handles
   install/verify/pin so the binary can assume a sane environment, and the whole
   pre-exec path works without network access.

---

*This document supersedes the placeholder. When architecture changes, update
this file and the affected `../docs/` guide together; the brainstorm notes in
this directory are historical inputs, not living documents.*
