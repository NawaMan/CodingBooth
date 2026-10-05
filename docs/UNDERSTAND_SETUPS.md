# Understanding Setups — the Seven Pieces of the Catalog

A map of how a booth gets its tools, from a bash script in `variants/base/setups/` to a running
container. Read this first; the detailed references are linked from each section.

| # | Piece | Lives in | In one line |
| --- | --- | --- | --- |
| 1 | **setup** | `variants/base/setups/*--setup.sh` | bash that gets a tool onto the image — and wires it into every shell |
| 2 | **install** | `variants/base/setups/*--install.sh` | packages through a known package manager, into a platform a setup installed |
| 3 | **variant** | `variants/<name>/Dockerfile` | a prebuilt image: a fixed set of setups baked in, plus the booth's primary UI |
| 4 | **template / extension** | `templates/**` | a selectable unit that *generates* `.booth/` — it does no work itself |
| 5 | **recipe** | `--select @name` | a named, saved selection of templates and extensions |
| 6 | **local** | a project's `.booth/` | the project-scoped version of every layer above, plus generated files and state |
| 7 | **example** | `examples/workspaces/*` | published projects that run the whole pipeline, and test it |

The one-sentence version: **templates generate config; setups and installs do the work; variants
are setups pre-baked; local is each layer again, owned by one project; examples prove it all.**

---

## 1. Setup — get a tool onto the image

`setup <name>` in a Boothfile compiles to `RUN <name>--setup.sh`. The script runs **as root at
build time**, but it does more than install: it may also emit the runtime artifacts that make the
tool usable in the booth.

| Artifact | Path | Runs |
| --- | --- | --- |
| Profile | `/etc/profile.d/<LEVEL>-cb-<name>--profile.sh` | every shell login (PATH, env) |
| Startup | `/usr/share/startup.d/<LEVEL>-cb-<name>--startup.sh` | once per container start, as the user |
| Starter | `/usr/local/bin/<name>` | every invocation (wrapper that `exec`s the tool) |

Common shapes: a single release binary (`helix`, `lazygit`), a versioned toolchain with a
`-current` symlink (`go`), an apt meta-package, and a **guarded add-on** (VS Code extension,
notebook kernel, desktop app) that calls `skip_setup` and exits 0 when its host is missing.

Nothing registers a setup: the base Dockerfile copies the whole directory onto `PATH`. A setup is
usable with no template at all — a hand-written `setup <name>` line works.

→ Reference: [BOOTH_SETUP.md](BOOTH_SETUP.md) (trio, LEVEL ordering, shared helpers).

## 2. Install — packages through a known package manager

`install <mgr> <pkgs…>` compiles to `RUN <mgr>--install.sh <pkgs…>`. Install scripts are thin
wrappers over an ecosystem's own manager: `pip`, `uv`, `conda`, `npm`, `yarn`, `bun`, `deno`,
`go`, `cargo`, `gem`, `hex`, `cabal`, `luarocks`, `pecl`, `dotnet`, `conan`, `brew`, `apt`,
`code-extension`, `jetbrains-plugin`, `pg-ext`.

**Setup vs install:** a setup brings in the *platform* (version choice, env, runtime hooks); an
install adds *packages within* that platform, pinned in the ecosystem's own syntax
(`pkg@1.2.3`, `pkg==1.2.3`, `pkg=1.2.3-1`).

Shared conventions:

- run as root; comma-separated lists are split (so a variadic param `jq,ripgrep` works);
- **an empty list is a no-op, exit 0** — the `*-pkg` templates default to `""`
  (`tests/setups/test--install-empty-args.sh`);
- network calls go through `cb_retry` (`libs/retry-source.sh`), which retries transient errors only;
- `apt` honours `APT_SNAPSHOT` — that archive freeze, not a per-package pin, is what makes apt
  reproducible.

Users reach installs mostly through `*-pkg` extensions (`nodejs+npm-pkg:typescript@5.4.5`,
`apt-pkg:jq,htop`). `tests/config/catalog/test64-all-installs-have-selector.sh` fails if an install
script has no template that emits it.

→ Reference: [BOOTH_CUSTOMIZATION.md → Installs](BOOTH_CUSTOMIZATION.md#installs),
[BOOTH_INSTALL_APT.md](BOOTH_INSTALL_APT.md).

## 3. Variant — a fixed set of setups, prebuilt

A variant is an image that has already run a set of setups, and that defines the booth's primary UI.

| Variant | Built from | Setups baked in (main ones) |
| --- | --- | --- |
| `base` | `ubuntu` | `tls`, `just`, `lazygit`, `viewmd`, fonts, `booth-message-wrapper` |
| `notebook` | `base` | `python`, `notebook`, `bash-nb-kernel`, web preview, message wrapper |
| `codeserver` | `base` | `python`, `codeserver`, code extensions, message wrapper |
| `desktop-xfce` / `-kde` / `-lxqt` / `-wayland` | `base` | the desktop, `firefox`, `google-chrome`, `vscode`, code extensions, kernels, desktop actions |

How variants couple to the other pieces:

- **Redundant setups are skipped.** `variantProvidedSetups` in
  `cli/src/pkg/boothfile/compiler.go` lists what each variant's Dockerfile already ran; a `setup X`
  on that list is dropped with a warning. It is **hand-synced** with the Dockerfiles.
- **Guarded add-ons ask the variant.** `cb-has-vscode.sh`, `cb-has-desktop.sh`, … decide whether a
  setup applies, so one Boothfile builds on every variant.
- **Some things are both a template and a variant** (`notebook`, `codeserver`, the desktops). A
  template can pin `variant = …`; startup code checks `BOOTH_VARIANT_TAG` so it does not start a
  second copy of the variant's own primary service.

→ Reference: [BOOTH_VARIANTS.md](BOOTH_VARIANTS.md).

## 4. Template / extension — generate the booth's config

A template is the unit `booth config` offers for selection. It is **declarative** — it does no
work itself — and generates `.booth/`:

- **Boothfile lines** — `setup …` / `install …`, placed by segment order band
  (40 desktops · 45 system libraries · 50 base · 55 second passes · 60 IDEs and dependents ·
  65 VS Code extensions · 70 kernels and JetBrains plugins · 90 post-setup);
- **`config.toml` keys** — `variant`, `run-args` (credentials, ports, env), `cmds`, `requires`;
- **paths and files** — `cache-*`, `shared-*`, `[files.setups|home|home-seed]`.

Some templates emit no Boothfile line at all (`no-sudo`, `git-credential`, `shell-history`) — they
only change config.

An **extension** is a `<name>--extension.toml` beside its parent: an add-on that shares the
parent's params, is selected with `+` (`go+linter`), and can be `auto-select`ed (dropped with `~`).
"X support for language Y" is almost always an extension.

Params map positionally in declaration order (`java:21,corretto`); only the last may be
`variadic`; a `runtime = true` param never becomes a Boothfile `arg`. Server templates follow one
shape: an `X_PORT` param plus opt-in `+expose` and `+autostart` extensions.

→ Reference: [templates/README.md](../templates/README.md) (patterns, order bands),
[AGENT_TEMPLATE.md](AGENT_TEMPLATE.md) (schema).

## 5. Recipe — a saved selection

A recipe is a `--select` string kept in a file, in the same syntax with multi-line formatting
(`+ ext` on continuation lines, `~ext` to drop an auto-selected one). Reference it as `@name`
(from `.booth/recipes/`) or `@./path.recipe`. It is an input to `booth config` and adds no
behaviour of its own.

→ Reference: [AGENT_RECIPE.md](AGENT_RECIPE.md).

## 6. Local — the project's own `.booth/`

Local is not a new kind of thing. It is **each catalog layer again, scoped to one project**, plus
the generated files and the runtime state.

| Group | Entries | Notes |
| --- | --- | --- |
| **Generated** | `Boothfile`, `config.toml`, `.generated` | written by `booth config`; `.generated` is the fingerprint that guards hand edits — commit all three |
| **Local catalog** — hand-written; `booth config` copies these, never regenerates them | `setups/` | local setup *and* install scripts; first on `PATH`, so they **shadow built-ins** |
| | `templates/<cat>/<name>/` | local templates; they override a stock one of the same name |
| | `recipes/` | `@name` recipes |
| | `startups/`, `startup.sh` | project startup hooks |
| | `home/`, `home-seed/` | copied to `~` — `home/` overwrites, `home-seed/` does not overwrite |
| **Runtime / state** | `cache/` | machine-local, gitignored |
| | `shared/` | committed, live bind mount |
| | `.env`, `.<profile>--env` | secrets, gitignored |
| | `<profile>--config.toml` | profile overlays (`--profile`) |
| | `console.json`, `egress/`, `.tmp/` | console layout, egress policy, runtime scratch (ports manifest) |

The pattern that keeps a project's own logic local **and** the Boothfile generated is a local
template that emits a local setup. `lamp-example` does it:
`.booth/templates/project/lamp-init/template.toml` emits `setup lamp-init`, which runs
`.booth/setups/lamp-init--setup.sh`. `lemp-example`, `wordpress-example` and `data-example` follow
the same shape.

→ Reference: [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md),
[BOOTH_CONFIG.md → Hand-Written Files](BOOTH_CONFIG.md#hand-written-files),
[BOOTH_LOCALCACHE.md](BOOTH_LOCALCACHE.md), [BOOTH_SHARED.md](BOOTH_SHARED.md),
[BOOTH_PROFILES.md](BOOTH_PROFILES.md).

## 7. Example — the pipeline, end to end

`examples/workspaces/*` are small real projects, each with a generated `.booth/`, a README, and
usually a `Justfile` and a `.cb-tests/` suite (`tags.txt`, an on-host test, in-booth assertions).
They do three jobs:

1. **demo** — published, with a README saying what it shows;
2. **witness** — proof that a catalog piece actually works
   (`examples/workspaces/run-example-tests.sh --example <name>`);
3. **try-it folder** — where a catalog change is exercised while it is being made (`setup-work`).

An example's `.booth/setups/` holds **only project-specific scripts**, never copies of built-in
setups — a copy shadows the real script and drifts from it.

---

## How the pieces connect

```
                 recipe ─(saved)─► selection
                                      │ booth config
   catalog: templates/extensions ─────┤◄──── local: .booth/templates/, .booth/recipes/
                                      ▼ generates
             .booth/Boothfile (setup … / install …) + config.toml (variant, run-args, …)
                                      │ build
   variant image (base + baked setups)│◄──── local: .booth/setups/ (shadow on PATH)
        FROM ─────────────────────────▼
             project image = variant + the Boothfile's setups and installs
                                      │ run  ◄── local: startups/, home*/, cache/, shared/, .env
                                      ▼
                                    booth

   examples/workspaces/* = real projects running this whole pipeline (+ .cb-tests)
```

## Where to go next

| To… | Read |
| --- | --- |
| add, modify or fix a setup, template or extension | the `setup-work` skill (`.claude/skills/setup-work/`) |
| write a setup script | [BOOTH_SETUP.md](BOOTH_SETUP.md) |
| pick a template's order band or follow a pattern | [templates/README.md](../templates/README.md) |
| look up a template key | [AGENT_TEMPLATE.md](AGENT_TEMPLATE.md) |
| write a recipe | [AGENT_RECIPE.md](AGENT_RECIPE.md) |
| customise one project | [BOOTH_CUSTOMIZATION.md](BOOTH_CUSTOMIZATION.md) |
