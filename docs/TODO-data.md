# TODO — Data modes: one extension per data item, the storage is a choice

Plan, written 2026-10-29 against `0.81.0--rc1` (`96b39cd1`). **To be implemented after the 0.81.0
release.** Nothing below is built yet.

Back to [TODO](TODO.md) | See also: [Home seeding](BOOTH_HOME.md), [cache](BOOTH_LOCALCACHE.md),
[shared](BOOTH_SHARED.md), [IN-OUT](IN-OUT.md), [template schema](AGENT_TEMPLATE.md)

---

## Table of Contents

- [The idea](#the-idea)
- [Why](#why)
- [The five modes](#the-five-modes)
- [Design](#design)
- [What happens when a mode does not fit](#what-happens-when-a-mode-does-not-fit)
- [Compatibility and migration](#compatibility-and-migration)
- [Phases](#phases)
- [Candidate inventory](#candidate-inventory)
- [Open questions](#open-questions)
- [Risks](#risks)

---

## The idea

A tool's persistent data — its config, history, bookmarks, plugins, package cache, service data —
is one **data item**, offered as one extension named for *what the data is*:
`+config`, `+history`, `+bookmarks`, `+plugins`, `+pkg-cache`, `+data`, `+credential`, … *Where*
that data lives is a **mode**, chosen as the extension's value:

```bash
booth config --select 'neovim+config:shared'     # commit the nvim config with the project
booth config --select 'neovim+config'            # default mode for this item (seed)
booth config --select 'python+history:bind'      # share ~/.python_history with the host
booth config --select 'go+pkg-cache:cache'       # per-project instead of machine-wide
```

Each item declares which modes it allows and which is the default. An item whose data has only one
sensible home (a credential, a template-content seed) simply allows one mode.

## Why

The survey of the catalog (2026-10-29) found **110** templates/extensions using one of these
mechanisms, spelled five different ways (`run-args` host mounts, `/etc/cb-home-seed`,
`cache-*`, `shared-*`, named volumes), and the mode baked into the extension *name*:

- **The same item ships as two or three extensions that differ only in mode** —
  `neovim+config` / `+config-shared`, `xfce+desktop-icons-cache` / `-shared`,
  `rust+cargo-cache` (bind) / `+registry-cache` (cache). Selecting both is possible and wrong.
- **Some of those names lie.** `firefox+bookmarks-shared`, `+extensions-shared` and
  `+settings-shared` all share the **same** dir (`.mozilla/firefox`); `google-chrome+bookmarks-shared`
  and `+settings-shared` both share `.chrome-data/Default`. Three descriptions promise a
  difference that does not exist.
- **One idea, three implementations.** Package caches are machine-wide volumes for go / npm / pnpm /
  pip / uv / gradle, host binds for `java+m2` / `rust+cargo-cache` / `rust+sccache` /
  `lean+mathlib-cache`, and a project cache for `rust+registry-cache`.
- **Big gaps.** Only `codeserver` has settings extensions — desktop VS Code, zed, the JetBrains
  IDEs, lazygit, k9s and the terminals (alacritty, kitty, ghostty) have none.

## The five modes

| Mode | Meaning | Lives | Survives | In git | Emitted as today |
| --- | --- | --- | --- | --- | --- |
| **bind** | live sync with a host path | host | always | no | `run-args` `-v <host>:<target>` (optionally `:create`) |
| **seed** | copied from the host at start | booth home | until container removed | no | `-v <host>:/etc/cb-home-seed/<rel>:ro` (never overwrites) |
| **cache** | kept between sessions, this machine, this project | `.booth/cache/` | yes | no (gitignored) | `cache-dirs` / `cache-files` |
| **shared** | committed with the project | `.booth/shared/` | yes | **yes** | `shared-dirs` / `shared-files` |
| **volume** | named Docker volume | Docker | until `docker volume rm` | no | `-v booth-<…>:<target>` + `owner-permission` |

`volume` has a **scope**: `booth` (`booth-<svc>data-{name}`, the service-data convention),
`project` (`{project}`), or `machine` (`booth-cache-<tool>`, the package-cache convention).

Two variants already in use that the model must keep:

- **seed-overwrite** — `/etc/cb-home/` instead of `/etc/cb-home-seed/`: copied every start,
  overwriting (claude-code `.credentials.json`, "always use fresh host credentials").
- **content seed** — `[files.shared-seed]` / `[files.cache-seed]` / `[files.home-seed]`: first
  content from the *template*, not the host (`firefox+bookmarks-seed`, `appwrite-server+seed`).
  This is an *initial-content option* on cache/shared, not a mode of its own.

## Design

### Schema — a `[data]` table on the extension

The compiler, not the template author, turns a mode into today's keys. Sketch:

```toml
# templates/tools/neovim/config--extension.toml
cb-version    = "2.0.0"
display-name  = "Neovim Config"
display-disc  = "Your nvim config — from the host, or committed with the project"

[data]
modes     = ["seed", "bind", "shared", "cache"]   # allowed, in TUI order
default   = "seed"
sensitive = false                                 # true ⇒ shared is refused

[[data.path]]
target = "/home/coder/.config/nvim"
type   = "dir"                                    # dir | file  (file ⇒ booth--file-sync for shared)
host   = ["~/.config/nvim", "~/AppData/Local/nvim"]   # bind/seed; first existing wins
# volume = "booth-nvimconfig-{name}"              # only when "volume" is in modes
# mode-flags = "0700"                             # cache/shared dir mode (envfolio)
```

- **The mode is the extension's value** — `+config:shared`. It is a reserved, `runtime = true`
  parameter (never a Boothfile `arg`: changing where data lives must not rebuild the image). The
  default is omitted from the `# Configured by:` header, like any other default.
- **Several paths, one mode.** An item with several paths (`neovim+data` covers `.local/share/nvim`
  and `.local/state/nvim`; `go+pkg-cache` covers the module and build caches) applies its mode to all.
- **`seed` stays no-overwrite;** an item opts into overwrite with `seed-overwrite = true` (only the
  claude-code credential needs it today).
- **`volume`** takes `volume-scope = "booth" | "project" | "machine"` and emits the matching name
  plus its `owner-permission` entries (the go/gradle uid fix carries over unchanged).
- Everything else an extension can carry (`env`, `[segments]`, `[files.*]`) still works beside
  `[data]` — e.g. `go+pkg-cache` keeps its `-e GOMODCACHE=…` in every mode.

### Mapping

| Mode | Compiler emits |
| --- | --- |
| bind | `run-args`: `-v <host>:<target>` for each host alternative (the missing-mount filter keeps the first that exists) |
| seed | `run-args`: `-v <host>:/etc/cb-home-seed/<target relative to /home/coder>:ro` (or `/etc/cb-home/`) |
| cache | `cache-dirs` / `cache-files` (+ mode flags) |
| shared | `shared-dirs` / `shared-files`; content seed → `[files.shared-seed]` |
| volume | `run-args`: `-v <volume>:<target>`, `[[owner-permission]]` |

So the runtime is untouched: booth-entry, the cache/shared mounting, the seed copy and the mount
filters all keep consuming the same `config.toml` keys they do today. **No booth-entry change.**

### Surfaces

- **TUI:** a data item row gets a mode picker listing only its allowed modes (like a param with
  `suggests`, but closed). The detail pane explains the chosen mode in one line.
- **`--select` / recipes:** `tool+item:mode`.
- **`booth template show`:** lists the modes, the default, and per mode what it does.
- **configweb:** same picker.

## What happens when a mode does not fit

Rule: **refuse at config time, never fall back silently** — falling back from `bind` to `seed`
means the user asked for live sync and got a one-time copy, the kind of quiet surprise the catalog
guards exist to stop.

| Situation | When | Result |
| --- | --- | --- |
| Mode not in the item's `modes` | `booth config` | error: `neovim+config: mode "volume" not offered (seed, bind, shared, cache)` |
| `sensitive = true` and mode `shared` | catalog load **and** `booth config` | hard error — a committed credential cannot be un-committed |
| `bind` / `seed` offered but no `host` | catalog load | error; guarded by a catalog test |
| `volume` offered but no `volume` name | catalog load | error; guarded by a catalog test |
| Host path missing at run time | `booth run` | unchanged: mount dropped, one notice per target, booth still starts |
| Two items on the same target with different modes | `booth config` | error (two extensions, one path) |
| Nested targets with different modes (chrome profile → cache, `Default/Bookmarks` → shared) | `booth config` | extend the existing cache/shared overlap check (`cli/src/pkg/mountoverlap`); allowed only where the inner one is declared as an override, else error |
| `shared` on a single file | runtime | rename-safe `booth--file-sync` (already exists) |

## Compatibility and migration

- **Old names keep resolving.** A new `aliases` key maps an old extension name to item + mode:
  `config-shared = "config:shared"`. Existing `.booth/` headers, recipes and showcases select by
  old names; they must keep compiling.
- **Regenerating rewrites the header** to the new spelling. That changes `.booth/Boothfile` /
  `config.toml` / `.generated` for every example using a renamed extension (≈ 30 distinct
  selections across `examples/` and `tests/`) — regenerate them all in the same change, then prove
  the round trip (re-run with no flags, `cmp`).
- **Hand-written guard.** An alias resolve must produce the *same* generated content, or every
  user's `.booth/` reads as hand-edited after upgrading. A unit test pins that.
- **Catalog versioning.** A rename/merge is a **major** `cb-version` bump on the affected
  extension (and on the parent for service volumes); regenerate `build/catalog-manifest.tsv`.
- **Aliases warn** (`config-shared is now config:shared`) and stay until 1.0.

## Phases

Each phase is its own commit series in one worktree (`worktree/data-modes`), landed together or
in two halves (1–3, then the rest).

- [ ] **0. Prereqs** — 0.81.0 released; worktree + version stamp.
- [ ] **1. Schema + compiler** (Go only, no catalog change)
  - [ ] `[data]` / `[[data.path]]` / `aliases` in the loader and model
  - [ ] reserved mode param: positional `:mode`, `runtime = true`, default dropped from header
  - [ ] mode → keys in the compiler (table above)
  - [ ] validation errors (section above), including sensitive + shared
  - [ ] unit tests: every mode's emitted keys; each refusal; alias ⇒ byte-identical output
- [ ] **2. Catalog guards** (`tests/config/catalog/`)
  - [ ] every `[data]` has a valid default inside `modes`; bind/seed ⇒ `host`; volume ⇒ name
  - [ ] no item marked `sensitive` offers `shared`; every `+credential` is `sensitive`
  - [ ] update test88 (params wired) and test121 (README complete) for the reserved param
- [ ] **3. Group A — merge the duplicates** (see inventory) — the proof the model is right
  - [ ] fix the firefox / chrome duplicate shared extensions as part of `+profile` / `+bookmarks`
- [ ] **4. Split the AI `+settings-cache` items** into `+settings` (no credentials) and the
      existing `+credential` — prerequisite for offering them anything but `cache`
- [ ] **5. Group B — config, history, plugins, IDE settings**
- [ ] **6. `+pkg-cache`** — one item per language over volume / bind / cache
- [ ] **7. Service `+data`** — move the per-booth volumes off the parent templates (riskiest)
- [ ] **8. Credentials** — mark `sensitive`; decide read-only `bind` for host-refreshed tokens
- [ ] **9. Gaps** — new `+config` for zed, desktop VS Code, JetBrains IDEs, lazygit, k9s,
      alacritty, kitty, ghostty
- [ ] **10. Docs and tests**
  - [ ] `templates/README.md`: a "Data items" section replacing the per-mechanism prose
  - [ ] `docs/AGENT_TEMPLATE.md`: the `[data]` schema; `docs/IN-OUT.md`: the five modes
  - [ ] `CHANGELOG` Unreleased: renames + aliases
  - [ ] a `tests/config/` case per mode, a `tests/config-tui/` case for the picker
  - [ ] one `tests/basic/` booth proving each runtime mode end to end (bind, seed, cache, shared, volume)
  - [ ] regenerate examples; round-trip check

## Candidate inventory

From the 2026-10-29 survey. **Bold** = proposed default. "Old" lists today's extensions that
become aliases.

### Group A — the same item already ships in several modes (phase 3)

| Item | Tools | Old | Modes |
| --- | --- | --- | --- |
| `+config` | neovim | `+config` (seed), `+config-shared` | **seed**, bind, shared, cache |
| `+desktop-icons` | xfce, lxqt | `+desktop-icons-cache`, `+desktop-icons-shared` | **cache**, shared, seed |
| `+bookmarks` | firefox, google-chrome | `+bookmarks-seed` (shared + content), `+bookmarks-shared` | **shared** (+content seed), cache, seed |
| `+profile` | firefox, google-chrome, chromium | `+profile-cache`, `+settings-shared`, `+extensions-shared` | **cache**, shared, seed |
| `+pkg-cache` | rust | `+cargo-cache` (bind), `+registry-cache` (cache) | **volume** (machine), bind, cache |
| `+settings` / `+state` | codeserver | `+settings-shared` (settings.json), `+settings-cache` (whole dir) | settings: **shared**, seed, cache · state: **cache** |

### Group B — one mode today, more make sense (phases 5–7)

**Config and IDE settings (phase 5)**

| Item | Tools | Old | Modes |
| --- | --- | --- | --- |
| `+config` | helix, fresh, ttt, croft | `+config-shared` | **seed**, bind, shared, cache |
| `+starship` | zsh | `+starship-shared` | **seed**, bind, shared |
| `+keybindings`, `+snippets` | codeserver | `+keybindings-shared`, `+snippets-shared` | **shared**, seed (host VS Code `User/`), cache |
| `+keyboard-shortcuts` | xfce | `+keyboard-shortcuts-shared` | **shared**, cache |
| `+lab-settings` | notebook | `+lab-settings-shared` | **shared**, seed, cache |
| `+connections`, `+drivers`, `+scripts` | dbeaver | `+*-shared` | **shared**, seed, cache |
| `+data` | neovim | `+data-cache` | **cache**, volume |

**AI tools (phases 4–5)**

| Item | Tools | Old | Modes |
| --- | --- | --- | --- |
| `+plugins` | gemini-cli, goose, grok, oh-my-pi, opencode | `+plugins` (seed) | **seed**, bind, shared |
| `+settings` | claude-code, codex, gemini-cli, goose, grok, oh-my-pi, opencode | `+settings-cache` (whole home dir, **includes credentials**) | **cache** until split (phase 4); then cache, seed, shared |

**History (phase 5)** — shared deliberately left out: psql / redis / shell history holds passwords.

| Item | Tools | Old | Modes |
| --- | --- | --- | --- |
| `+history` | python, nodejs, ruby, php, elixir | `+repl-history` | **cache**, bind |
| `+history` | postgresql, mysql, mongodb, redis, sqlite | `+cli-history` | **cache**, bind |
| `+history` | shell-history (template) | — | **cache**, bind |

**Package caches (phase 6)** — shared never.

| Item | Tools | Old | Modes |
| --- | --- | --- | --- |
| `+pkg-cache` | go | `+mod-cache` (volume) | **volume**, bind, cache |
| `+pkg-cache` | nodejs | `+npm-cache`, `+pnpm-cache` (volume) | **volume**, bind, cache — see open question 3 |
| `+pkg-cache` | python | `+pip-cache`, `+uv-cache` (volume) | **volume**, bind, cache — same question |
| `+pkg-cache` | java | `+gradle-cache` (volume), `+m2` (bind) | **volume**, bind, cache |
| `+pkg-cache` | lean | `+mathlib-cache` (bind) | **volume**, bind, cache |
| `+sccache` | rust | `+sccache` (bind) | **volume**, bind, cache |

**Service and app data (phase 7)**

| Item | Tools | Old | Modes |
| --- | --- | --- | --- |
| `+data` | postgresql, mysql, mongodb, redis, kafka, rabbitmq, floci | volume on the **parent** template | **volume** (booth), cache |
| `+data` | n8n, appwrite-server | `+persist` (cache); appwrite `+seed` (content) | **cache**, volume |
| `+data` | android-sdk | `+avd-cache` | **cache**, volume |
| `+store` | envfolio | `+store-cache` (0700) | **cache**, volume |

### Group C — one valid mode, kept single (phase 8)

- **`+credential` (seed, `sensitive`)** — claude-code (seed + seed-overwrite), codex, gemini-cli,
  goose, grok (+ `token-credential`), oh-my-pi, opencode, antigravity, cursor, warp, aws-cli,
  aws-sam-cli, azure-cli, gcloud, firebase, appwrite-cli, gh, kubectl, openssh, ruby, rust.
  Also seed-only: `git-credential`, `ssh`, `dind+docker-config`, `nodejs+npmrc`,
  `python+pip-config`, `gh+copilot`. Only candidate second mode: read-only `bind` for tokens the
  host refreshes (gcloud, AWS SSO) — decide in phase 8.
- **Content seeds** — `claude-code+auto-accept`. Not a data item; unchanged.

### Gaps — no data extension yet (phase 9)

zed, desktop VS Code (`settings`/`keybindings`/`snippets` — only code-server has them), JetBrains
IDEs, lazygit, k9s, alacritty, kitty, ghostty.

## Open questions

1. **Combined modes.** `seed` then `cache` ("copy from host the first time, then keep it local")
   and `seed` then `shared` look useful and may already work, since the seed copy only fills
   what is missing. Allow `seed+cache` / `seed+shared` as modes, or keep the five exclusive?
2. **Mode name in `--select`.** `+config:shared` puts the mode where a param value goes; an
   item that also has real params (`+pkg-cache` with a manager?) needs a fixed position for the
   mode — first, or a named form?
3. **One item or one per manager?** nodejs (`npm`, `pnpm`) and python (`pip`, `uv`) have two
   caches. `+pkg-cache` covering both, or `+npm-cache:<mode>` / `+pnpm-cache:<mode>` kept apart?
4. **`volume` scope as a mode or a flag.** `volume` with a fixed scope per item, or
   `volume-booth` / `volume-machine` as separate modes the user picks?
5. **Moving service volumes off the parent.** Today selecting `postgresql` alone persists its
   data. With `+data` auto-selected that stays true — but `~data` would then mean "throwaway DB".
   Wanted, or should the parent keep its volume and `+data` only offer alternatives?
6. **Alias lifetime.** Until 1.0, or forever (they are cheap)?

## Risks

- **Service data (phase 7)** — a mistake loses a user's database. Migration must keep the exact
  volume names (`booth-pgdata-{name}`); add a `tests/complex/` case that writes a row, regenerates
  `.booth/` with the new extension, restarts, and reads it back.
- **Hand-edit guard** — if alias output is not byte-identical, every upgraded project looks
  hand-edited and `booth config --no-tui` refuses to regenerate. Unit-tested in phase 1.
- **Committing secrets** — the whole point of `sensitive`; the AI `+settings-cache` split (phase 4)
  must land before any of them offers `shared`.
- **Ownership on mounted dirs** — volume and cache modes for paths written at build time need the
  `owner-permission` entries the go/gradle caches already carry; a new item that forgets them fails
  only on hosts whose uid is not 1000. The phase-10 `tests/basic/` cases should run as a non-1000 uid.
