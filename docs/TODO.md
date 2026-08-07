# TODO

This is where dreams begin. ✨  
A list of upcoming ideas, improvements, and future goals for the CodingBooth launcher.

Status markers: `[ ]` open · `[x]` done · `[~]` partial · `[-]` rejected/abandoned ·
`[?]` **to relook later** — still has value, but the direction is unclear or it is not a priority yet.
A `[?]` item is parked on purpose: don't merge it, don't delete it, and don't re-propose it as new.

---

## Code Features
- [ ] We might want to flip the docker chain if we want to make it start faster.
      Right now, Project -> Variant -> Base ... but users of the same project may choose different variants. So all the setup such as language, framework, libraries, tools, etc. will be done last.
      That is when people change variants, they will have to re-run the setup.
- [ ] Figure out a way to separate setups from the base variant.
- [ ] Add "previous" variable - e.g., use for continue (for --keep-alive) and previous variant can be useful to speed things up.
- [ ] **An `example-add` skill** — repo tooling, not product: adding an example workspace is a fixed
      recipe that is currently done from memory, and the two items under *Problems* about leaked host
      paths and ungenerated `.booth/` files are both what that costs. `setup-work` covers the catalog,
      `todo-add` covers this file, `blog-add` covers posts; the example surface — 65 folders and the
      first thing a new user touches — has nothing.
      Approach: follow the `setup-work` shape (`.claude/skills/<name>/SKILL.md`, numbered steps, a
      standing "try it" line). The recipe it should encode, all of it already established: generate
      `.booth/` with `booth config` **from inside the folder** so no absolute path reaches the header;
      commit `Boothfile` + `config.toml` + `.generated`; `.cb-tests/tags.txt` + a smoke test on an unused
      `CB_PORT` (they are allocated in steps of 10 — grep the existing ones); a README in the sibling
      house shape (what it demonstrates → Run → What's inside); then the three catalog surfaces
      (`EXAMPLES.md`, `docs/EXAMPLES_ADVANTAGES.md` prose *and* table) and a `docs/CHANGELOG.md` entry.
      Open questions: how far it should push on proving the example works. `pocketbase-example` shipped a
      cheap `go version` smoke test matching its siblings, with the real proof done by hand at authoring
      time (build, serve, curl) — worth deciding whether the skill mandates the deeper `inBooth-*` shape
      `go-example` uses, or keeps the cheap default and just *requires* the hand-proof be reported.
- [ ] ...

## Features
- [x] Add TESTS, add TESTS, add TESTS, add TESTS!!!
- [-] Remove CVEs for docker images -- give up (most found in core pages like python, nodejs, etc)
- [x] Try to not have "user-land" setup print anthing (unless error) -- nodejs-example
- [x] Improve Docker-in-Docker (DinD) integration — ideally without relying on a sidecar container.
- [x] Add Kubernetes (K8s) support.
- [~] Support non-X11 environments (e.g., Unity, Omarchy, Wayland). -- `desktop-wayland` variant adds a Wayland-native labwc desktop (wlroots) over wayvnc+noVNC. (Real GNOME-on-Wayland attempted via WebRTC but blocked by headless mutter frame emission; parked on branch wip/desktop-gnome-webrtc.)
- [-] Rename “variant” to “interface” for clarity: -- NOTE: `variant` is good.
- [ ] Add desktop icons for IDEs (e.g., VS Code, JetBrains IDEs).
- [-] Simplify adding Jupyter Notebooks to desktop environments (auto-add like VS Code).
- [ ] Evaluate using host disk or tmpfs (RAM) for `$HOME` to improve I/O performance.
- [ ] Improve container startup speed — some setup tasks run too early (in `STARTUP`).
- [ ] See if we can sync the setup with GitHub action (just seen it recently that it exists)
- [X] Install jpterm - for all variants. https://github.com/davidbrochart/jpterm
- [-] Install yazi CLI file browser - for all variants. https://lindevs.com/install-yazi-on-ubuntu
- [x] Change to use JJava instead of IJava. https://github.com/dflib/jjava
- [X] Add template repository.
- [ ] Add example repository.
- [x] Firebase example / home-seed placeholder — `setup firebase` startup now
      re-applies host `firebase-tools.json` when the dest is missing, empty, or only
      `{}` (firebase-tools' unauthenticated stub). Real in-container logins are left
      alone. Credential extension remains a single-file seed mount; no new global
      home-seed mode.
- [ ] Report container with the same name exists better. Also suggest how to remove the container.
- [ ] SAVE (--keep-alive)/LOAD (continue)/EXPORT (save to file)/IMPORT (load from file) 
- [ ] Add more tip to 99z-cb-profile.sh - Like those functions after setups (python-info, start-xfce and etc.)
- [ ] Consider using ubuntu-keyring instead of debian-archive-keyring.
- [ ] Add `booth-help` command inside the container to show available tools and commands.
- [ ] Polish the `booth config` hand-off for hand-written files. The feature itself is **done** and is
      deliberately as far as we go: a hand-written `.booth/Boothfile` is protected, `--beside` (or Enter
      in the TUI) keeps it and writes the generated content as `Boothfile.new`, and we print a `diff`
      command. Producing the two files is our job; merging them is the user's. Two cosmetic gaps:
      - Printed paths are absolute and long — print them relative to the cwd so the command is easy to
        copy-paste.
      - `diff` only *shows* the difference. Also suggest a side-by-side merge (`vimdiff`, `code --diff`).

      **Rejected — do not re-propose (investigated 2026-07-11):**
      - *Storing the last-generated content as a merge base, for a three-way merge.* It does not earn its
        keep. Boothfiles are tiny (largest in repo: 50 lines; average ~8), so a two-way diff is readable
        by hand and three-way saves roughly one hunk. Worse, the base does not exist for the dominant
        case — 230 of 301 tracked booth files are hand-written from scratch and never had a generated
        predecessor — so the machinery would only help the minority. The "extra hunks" a two-way diff
        shows are not noise; they are exactly the changes the user just asked for in the TUI. Costs:
        changes the `.booth/.generated` format, needs diff3 (no Go stdlib; repo runs on 2 deps), and adds
        an adoption trap — adopting a hand-edited legacy file as its own base makes a later merge *delete*
        the user's edits.
      - *Reading the Boothfile back into TUI state so the TUI can represent everything.* Impossible as a
        total function: the Boothfile DSL (`run`, `copy`, `workdir`, arbitrary shell) is strictly richer
        than the TUI's vocabulary (template selections + params), so a hand-written `run echo hi` has no
        template preimage. (Measured: ~99% of *generated* lines can be attributed back to a template
        segment, because the compiler emits segments verbatim. So a read-only "custom directives,
        preserved verbatim" panel would be feasible — if it is ever actually wanted.)
- [x] **Persist browser bookmarks & history** — largely done (see [BOOTH_SHARED.md](BOOTH_SHARED.md)).
      - Local full profiles: `+profile-cache` (cache; Chrome/Chromium → `~/.chrome-data`) and
        `--persist-home`.
      - Team/git: `.booth/shared/` + `+bookmarks-shared` / `+settings-shared` / `+extensions-shared`
        for Chrome, Chromium, Firefox; drivers need jars **and** `drivers.xml` registry.
      Deliberate non-goal: sharing History SQLite via git (personal noise, bad merges).
- [ ] **Shared-state catalog polish (no secrets)** — `.booth/shared` is in; fill remaining safe
      opt-ins and examples so other sessions don't re-derive the map.
      Decision: prefer **shared** for team non-secret state; **cache** for personal bulk; **host
      seed** for credentials; never share whole homes or password stores.
      Approach: more `*--extension.toml` `shared-files`/`shared-dirs` only (mirror existing
      dbeaver/codeserver/browser extensions); sample gitignores under `docs/samples/`; optional
      example workspace wiring. Docs stay the source of truth in `BOOTH_SHARED.md`.
      Open backlog (conservative):
      - **Neovim polish** — sample `.gitignore` for shared `~/.config/nvim/` (ignore lazy/plugin
        noise, spell, personal paths); optional share of lockfile only (`lazy-lock.json`); wire
        `neovim+config-shared` into playground / a small example. Do **not** share
        `~/.local/share/nvim` (that stays `+data-cache`).
      - **code-server+tasks-shared** — `User/tasks.json` only (no env secrets in tasks).
      - **Desktop keybindings** — KDE/LXQt one-file shortcuts shared (like `xfce+keyboard-shortcuts-shared`).
      - **File-manager bookmark for the project** — add a Places / sidebar entry for
        `/home/coder/code` (the bind-mounted project) in the desktop file browser (Thunar /
        pcmanfm-qt / Dolphin). Not a web-browser bookmark; not shared-state of random host
        paths. Approach: seed GTK bookmarks (`~/.config/gtk-3.0/bookmarks` →
        `file:///home/coder/code Project` or folder name) and/or desktop-specific places via
        home-seed or a small setup/startup on xfce/lxqt/kde; optional `shared-files` only if
        teams want to commit custom Places lists (usually a fixed seed is enough).
        Open questions: default-on for all desktop variants vs opt-in template extension;
        label text (`code` vs project folder name from `CB_PROJECT_NAME`).
      - **API client collections** — Bruno/Insomnia collections dir without env/secret files (or
        keep collections in the project tree).
      - **CloudBeaver connection defs** — only if a stable path exists and passwords stay out
        (audit before shipping).
      - **TUI clarity** — surface Shared group / collapse overlapping browser paths
        (bookmarks+settings both use Chrome `Default/`) so users don't double-select needlessly.
      Explicit non-goals: JetBrains full config/license; Warp/AI credentials; shell history;
        cookies; whole `~/.config`; VS Code extension stores / globalStorage.
- [~] **Shell history across sessions** — half done. `.bash_history` / `.zsh_history` already survive if
      the user hand-writes them into `cache_files` (`docs/BOOTH_CUSTOMIZATION.md`), and `--persist-home`
      preserves them wholesale. Missing: a first-class opt-in, so nobody has to know the incantation.
      Approach: a `shell-history--extension.toml` (or a base-level config default) that adds those two
      files to `cache_files` — no new mechanism, just a named handle on the existing one.
      Open questions: default-on or opt-in? Shell history is the single most likely place for a secret to
      leak into a cache directory that is then reused and possibly committed.
- [ ] **Live list of examples** — `booth example list` is pinned to the binary's own version. It fetches
      `example-list.txt` from the GitHub release tagged with the running binary's version
      (`cli/src/cmd/codingbooth/example.go`) and caches it at
      `~/.cache/codingbooth/versions/<tag>/example-list.txt`. An older binary therefore can never see
      examples published since it shipped, and the cache has no expiry.
      Approach: resolve a `latest` tag (or read the list off the repo's default branch) instead of the
      pinned tag, with the pinned release as the offline fallback; add a TTL or `--refresh` so the cache
      can be invalidated. The release side already builds the asset
      (`.github/workflows/release-binary-and-wrapper.yaml`), so this is a fetch-path change only.
      Open questions: does "live" mean the CLI, or a rendered list on the website (`site/`)? If both, the
      generated `example-list.txt` is the shared source and the site should consume the same asset.
- [ ] **Live list of templates** — same defect, same fix, different path: `booth template list` resolves
      through `cache.ResolveTemplatesDir(version)` (`cli/src/cmd/codingbooth/init.go`), which unpacks the
      templates bundle for the binary's pinned version. New templates are invisible to an older binary.
      Approach: share whatever tag-resolution and cache-invalidation the examples list lands on — these two
      should not grow separate mechanisms. `--templates-path` / `CB_TEMPLATES_PATH` stays the local override.
      Open questions: a template list is only useful if `booth init` can then *resolve* those templates, so
      "live listing" probably implies fetching a live bundle too — decide whether that is in scope or
      whether the list should mark newer entries as "requires booth >= X".
- [ ] **`booth config` should find a repo checkout's own `templates/`** — running it from an unreleased
      build (any `--rc`) tries to fetch `templates.zip` for a tag GitHub does not have, 404s, and hints at
      `--templates-path` / `CB_TEMPLATES_PATH`. Every generation command in a repo session has to carry
      that env var; forgetting it is the single most common way a `booth config` run dies during
      development.
      Approach: in the resolver that already handles this (`cache.ResolveTemplatesDir(version)` in
      `cli/src/cmd/codingbooth/init.go`), fall back to a `templates/` directory found by walking up from
      the binary's own location — the same discovery `tests/config-tui/tui-helpers--source.sh` already
      does when it looks for the dir holding both `codingbooth` and `templates/`. Explicit
      `--templates-path` still wins.
      Open questions: should the fallback apply only when the version is an `--rc`/unreleased tag, or
      whenever a sibling `templates/` exists? The second is friendlier but means a repo checkout silently
      ignores the released bundle — probably right for this repo, and worth a one-line "using local
      templates from …" notice either way.
- [ ] ...

## Problems
- [ ] VS Code hangs/crashes sometimes. Some cases were the 64 MB `/dev/shm` renderer crash
      fixed below (`code: 133`); watch for any that survive that fix.
- [x] **Jupyter Notebook (`.ipynb`) in VS Code hangs/crashes.** RESOLVED 2026-07-14.
      The earlier ipykernel-7 / [vscode-jupyter#17228] theory was **wrong**. Verified on a
      live `desktop-xfce` booth:
      - Desktop VS Code and `code-server` run the **same** Jupyter extension (2025.9.1) and
        the **same** ipykernel (6.31.0), yet only desktop VS Code failed — so the extension
        version was never the difference. The `ipykernel>=6,<7` pins were mitigating a cause
        that wasn't the cause; they have been removed.
      - The kernel is healthy: it executes over a native `jupyter_client` connection (`ok`).
      - The real failure is an **Electron renderer crash** —
        `CodeWindow: renderer process gone (reason: crashed, code: 133)` in `main.log`. The
        container's `/dev/shm` defaults to **64 MB**, and Chromium's renderer maps its shared
        memory there (confirmed: renderer processes hold fds into `/dev/shm`). Rendering a rich
        notebook (embedded images/widgets) overflows 64 MB and the renderer aborts.
      - `code-server` is immune — it renders in the **host** browser, which has a normal-sized
        `/dev/shm`. Bash/Java notebooks survived because their text output stays small.
      Fix (two complementary changes):
      - `vscode--setup.sh`: the `code` wrapper now passes `--disable-dev-shm-usage`, so Chromium
        puts its shared memory under `/tmp` (223 GB free) instead of `/dev/shm`. Verified: with
        the flag the renderer processes hold 0 fds into `/dev/shm` (4 under `/tmp` instead).
      - Desktop variants now run with `--shm-size=1g` (`PrepareCommonArgs`, gated on
        `HasDesktop`), which also protects the desktop's web browser and any other
        Chromium/Electron app, not just VS Code.

[vscode-jupyter#17228]: https://github.com/microsoft/vscode-jupyter/issues/17228

- [~] **Examples ship the author's home directory in their committed headers.** DONE for the content;
      the guard is still missing. Nine examples — `clang`, `claude`, `csharp`, `firebase`, `fsharp`,
      `jetbrain-exmple`, `kind`, `server`, `zig` — carried
      `# Generated by: booth config /home/nawa/dev/git/CodingBooth/examples/workspaces/<name> …` across
      18 `.booth/` files, because `booth config` echoes the target path verbatim into the header and it
      was run with the path as an argument. Every `booth example try` zip carried it.
      All nine are now path-free: `zig` by regeneration (see the item below), the other eight by editing
      the comment line, which is safe precisely *because* those files are not fingerprinted — no
      `.generated`, so their guard status is unchanged. `claude-example`'s header additionally pointed at
      a `bash-example` folder that no longer exists; that went with it.
      Note the ninth: `jetbrain-exmple` is misspelled, so it does not match `*-example` and is invisible
      to every glob in the tooling — including the one that found the first eight. Worth renaming, or at
      least making the globs `examples/workspaces/*/`.
      Enforcement shipped too: `tests/config/test93-booth-files-are-clean.sh` fails on any committed
      `.booth/` file carrying a non-`coder` home path. It scans `git ls-files`, so it guards what a
      release actually zips rather than what a dirty tree holds.
- [ ] **Nothing checks that a shipped example is still `booth config`-generated.** Of 65 examples, **6**
      carry `.booth/.generated` and 31 have a provenance header at all. A generated example opens in the
      config TUI with its selection preloaded; a hand-written one opens behind a warning dialog and
      refuses to save until the user types "overwrite" — so this is a user-visible difference in a
      surface we advertise as "take it apart and learn from it". `pocketbase-example` was built generated
      and round-trip-verified on purpose; nothing stops the next edit from quietly breaking it.
      Approach: a test walking `examples/workspaces/*/` that calls the existing `output.Drifted(path)`
      (`cli/src/pkg/boothinit/output/guard.go`) and fails on any non-empty result. That is a few lines.
      The work is the migration in front of it — **and the migration is mostly impossible**, measured
      rather than guessed (2026-08-07). Every example's own recorded header was replayed into a scratch
      copy and the results compared at the level of *directives* (ignoring comment/header-format churn and
      the `APT_SNAPSHOT` stamp, which `CB_APT_SNAPSHOT` can pin to the example's existing value):

      | Outcome | Count | Why |
      | --- | --- | --- |
      | Regenerates unchanged | 6 | 2 already generated, 2 migrated, 2 blocked — see below |
      | Directives would change | 28 | Templates evolved after the file was written; replaying alters what it installs |
      | No header at all | 30 | No recorded selection — regenerating means inventing one |
      | Fake header | 1 | `browser-shared-example`, fixed separately |

      Migrated: `playwright-example`, `zig-example`. Blocked even though they regenerate cleanly:
      `cache-example` (empty Boothfile) and `empty-example` (its Boothfile is a hand-written teaching
      scaffold of commented-out examples — the *point* of that example). For both, an empty selection
      writes no Boothfile at all, so `.generated` would fingerprint only `config.toml` and the guard would
      still flag Boothfile — a fingerprint that buys nothing. Four of the 28 would additionally delete
      hand-written explanatory comments (`clang` 4, `haskell` 4, `systemlib` 5, `playwright-polyglot` 6).
      Open questions: the honest read is that "every example is generated" is not reachable by replay, and
      the remaining 58 each need a decision, not a script.

      **Two corrections to the obvious next moves, both learned the hard way (2026-08-07):**
      - *"A file with a header must also have a matching `.generated`" is not enforceable today.* 87
        committed `.booth` files carry a header; 9 `.generated` files exist. The rule would fail across
        `blog/`, `examples/playground*/`, most of `tests/complex/`, and half the examples.
      - *A **mismatching** fingerprint is not rot — it is the guard doing its job.* It is precisely how
        the tool knows a generated file was hand-edited afterwards, which is what makes it refuse to
        clobber those edits (`playwright-polyglot-example` is exactly this, deliberately). Do **not**
        "fix" it by deleting `.generated`: with a header and no fingerprint the file is *adopted* as
        booth config's own output and silently overwritten on the next run — strictly worse. Verified
        against the real binary, in both directions.

      So the only fingerprint rule worth enforcing repo-wide is the weak structural one now in
      `test93`: no manifest entry may name a file that is not there.
      `deno-example` is the one near-miss worth a second look: same directive *set*, but regeneration
      moves `setup deno-code-extension` to the template-canonical position. Build order can matter, so it
      was left alone.
- [ ] **The example catalog is maintained by hand in three places, and nothing compares them.** Release
      packaging globs `examples/workspaces/*-example/`, while `EXAMPLES.md`'s catalog and
      `docs/EXAMPLES_ADVANTAGES.md`'s prose *and* its bottom table are each edited by hand — so an example
      can ship while appearing in none of them, or linger in the docs after being removed.
      Approach: a test comparing the three sets — folder names, the `EXAMPLES.md` catalog entries, and the
      advantages table rows — and reporting the difference in each direction. Pure string work over files
      already in the repo; no new dependency.
      Open questions: the advantages doc has *two* surfaces (grouped prose + the table) and only the table
      is mechanically checkable — decide whether prose coverage is required or best-effort. `site/more.html`
      is deliberately illustrative ("…and more"), so it should stay out of the check.
- [ ] Java example: Lombok does not work in VS Code.
- [ ] `remove`/`stop`/`start`/`restart` ignore flags placed *after* the positional name (e.g. `booth remove myproj --force` does not force) because they use plain `flag.Parse`, which stops at the first positional. `shell`/`exec` already work around this with `extractPositionalAndFlags`; apply the same handling to the other lifecycle commands so flag order doesn't matter.
- [ ] ...

---

## Parked — to relook later

Work that exists outside `main` and still has value, but is blocked on an undecided question or simply
isn't a priority. Audited 2026-07-25. Everything *not* listed here was checked and is already in `main`
— see the note at the end.

- [?] **`--sandbox` / `--sandbox-mode` isolation** — branch `DockerSandbox` (v0.58.0-rc1, 2026-06-28).
      The tip commit's own message says *"Left at adding tests."*
      Adds `cli/src/pkg/booth/sandbox_setup.go`, wiring in `cli/src/pkg/booth/init/initialize_app_context.go`,
      a `--sandbox` entry in `help.go`, `tests/dryrun/test024--sandbox.sh`, and home-seed
      `.claude/settings.json` for two examples. The design doc `docs/plans/Sandbox-Isolation-Modes.md` is
      already on `main`; the implementation is not.
      **Parked deliberately: the isolation model has an open concern.** Do not merge, and do not delete the
      branch, until that is settled. Note it sits beside the shipped `dind_setup.go` / `egress_setup.go`,
      so any revisit should say how the three isolation surfaces compose rather than adding a fourth.

- [?] **A `templates/frameworks/` tier (django, spring)** — `stash@{0}`, from the since-deleted
      `feature/BoothDesign` worktree (Feb 2026).
      Most of the stash is dead: it is written in the old `spec.toml` format, and `main` has **zero**
      `spec.toml` files (the format is now `template.toml` + `*--extension.toml`). Its go, java, python, and
      maven specs are all superseded — maven now lives as
      `templates/languages/java/maven--extension.toml`.
      The one idea that did *not* land: a **framework** category. `main` has `languages`, `tools`,
      `ides`, `browsers`, `databases`, `desktops`, `ai-tools`, `education` — but no framework tier, so
      django and spring have no home.
      Approach if revisited: write `templates/frameworks/{django,spring}/template.toml` fresh in the current
      format and drop the stash — replaying it would cost more than it returns.
      Open question: is "framework" a new top-level category, or just extensions hanging off the language
      template (`python/django--extension.toml`)? The latter matches how maven attached to java.

**Audit note (2026-07-25).** Branches `main-backup`, `backup`, `LifeCycle`, `recovered-booth-init`, and
`template-backup` were compared against `main` by content, not by commit — `main`'s history was rewritten
by the retime tooling, so ahead/behind counts are meaningless there. All of their work is present in
`main` under the current naming (`cli/src/cmd/coding-booth/` → `cli/src/cmd/codingbooth/`,
`booth/runinit/` → `boothinit/`, `docs/implementations/URL_WHITELIST.md` → `EGRESS.md`). The only file
absent from `main` is `variants/base/setups/libs/git-on-token.sh`, deleted on purpose in commit `95ef5cb0`
("drop unused git-on-token.sh"). Nothing is lost; those branches are safe to delete.

---

## Binary companions (libraries that need a separate tool binary)

Libraries whose package install alone is not enough — they also need a companion
CLI or engine (`protoc`, parser generators, ffmpeg, graphviz, browser drivers,
ORM CLIs, …). C/C++ `lib-*` / `*-dev` is a separate track.

Full audit and priority shortlist: **[TODO-BINARY_COMPANIONS.md](TODO-BINARY_COMPANIONS.md)**.

- [x] Phase 1 — TUI templates: `protobuf` (+ Go plugins), `buf`, `ffmpeg`, `graphviz`
- [x] Phase 2 — `dotnet-pkg` (`install dotnet` / `csharp+dotnet-pkg:dotnet-ef`)
- [x] Phase 3 — Puppeteer / Cypress / Selenium stacks
- [x] Phase 4 — Docs “library X → also select Y” ([BOOTH_CONFIG.md](BOOTH_CONFIG.md#binary-companions--library-x--also-select-y))

---

## Additional Setups
Add or improve support for these developer tools and environments:

- [x] `network-whitelist` - Restrict container internet access to whitelisted domains
- [x] `aws-cli`
- [x] `az-cli` (azure-cli)
- [x] `bun`
- [ ] `clang`
- [ ] `cmake`
- [x] `conda`
- [x] `deno`
- [x] `docker` (dind)
- [x] `dotnet`
- [x] `elixir`
- [x] `erlang`
- [ ] `gcc`
- [x] `gcloud`
- [x] `go`
- [x] `haskell`
- [ ] `julia`
- [x] `k3d`
- [x] `k9s`
- [ ] `kafka`
- [x] `kind`
- [x] `kotlin`
- [x] `kubectl`
- [x] `kubectx` + `kubens`
- [x] `lua`
- [ ] `make`
- [ ] `mongodb`
- [x] `mysql`
- [x] `nodejs`
- [ ] `ocaml`
- [x] `php`
- [x] `postgres`
- [ ] `rabbitmq`
- [ ] `roc`
- [x] `r-rscript`
- [x] `ruby`
- [x] `rust`
- [ ] `sbt`
- [x] `scala`
- [ ] `swift`
- [x] `zig`
- [x] `terraform`
- [x] `helm`
- [x] `aws-sam-cli`
- [x] `aws-cdk`
- [x] `gh-copilot`

- [ ] **An embedded / emulator family, following the `android-sdk` shape.** Six candidates surfaced by
      asking what else fits the pattern `android-sdk` established: a heavyweight SDK that is painful to
      hand-roll in a `Boothfile`, plus a runtime that turns the booth from "build" into "run and see".
      The machinery already exists — `FilterMissingDevices` (`cli/src/pkg/booth/booth.go`) lets a template
      ask for a device the host may not have, `templates/README.md` already names serial devices and GPUs
      as the generalization, and a graphical simulator needs nothing beyond `DISPLAY=:1` on a desktop
      variant. Unlike `android-sdk` (`unsupported-arch = ["arm64"]`), every toolchain below ships arm64,
      so none of them would be amd64-only.
      Listed most-recommended first; each is independently shippable.
      - **ESP-IDF / ESP32** — the true 1:1 repeat of Android. Heavy SDK (`install.sh`/`export.sh`,
        multi-GB toolchains) *and* a first-party emulator: `idf.py qemu` runs Espressif's QEMU fork with
        ESP32/C3/S3 machine models (eFuses, crypto accelerators, virtual framebuffer), headless with
        serial on stdout. Splits exactly like Android: `esp-idf` setup + `+qemu` extension.
      - **Arduino** — `arduino-cli` is a single Go binary whose board/library manager is a near-exact
        analog of `sdkmanager`. The valuable half is *not* emulation but real hardware:
        `--device /dev/ttyACM0` plus the `dialout` group, which `FilterMissingDevices` already makes safe
        to declare. A `+simavr` extension (apt universe; real GPIO/ADC/timer/UART models, GDB stub, VCD
        out) covers simulation; `gtkwave` is how you look at it.
        Open questions: there is **no USB/serial precedent anywhere in the repo** — no `dialout`, no
        `ttyUSB`/`ttyACM`, no `--group-add` — so this item defines that pattern, and `+kvm` is the model
        to copy. And `--device` resolves at `docker run`, so a board plugged in *after* the booth starts
        will not appear; hotplug would need `--device-cgroup-rule` plus a `/dev` bind, which is a far
        bigger hammer than `+kvm` and should be a separate decision, not smuggled in here.
        Rejected for now: **Wokwi** (`wokwi-cli`), which is the visual breadboard people actually mean by
        "Arduino simulator" — it is a hosted service needing `WOKWI_CLI_TOKEN`, so it would be the only
        catalog entry that stops working offline. Revisit only as an explicitly-labelled opt-in.
      - **RISC-V / cross-compile + QEMU** — `gcc-riscv64-linux-gnu` + `qemu-user-static` +
        `qemu-system-riscv64`, all apt on every arch. Cheapest of the six and the broadest: build for
        another architecture and actually run the result.
      - **FPGA / HDL** — `yosys`, `nextpnr`, `verilator`, `iverilog`, `gtkwave`, all apt and fully
        offline. Simulation *is* the emulator here, and GTKWave is the `cb-desktop-icon.sh` payload.
      - **Zephyr + Renode** — the general embedded whole-SoC emulator (scriptable, headless, .deb plus a
        portable tarball, hundreds of Cortex-M and RISC-V boards, official `arduino-cli` integration for
        the Nano 33 BLE). Note it has **no AVR support**, so it does not cover the classic Uno.
      - **Retro consoles** — `gbdk-2020` + `mgba`, `cc65` + `fceux`. Tiny SDK, real emulator with a
        window, immediate visible payoff; belongs in `templates/education/` rather than `tools/`.
      Out of scope permanently: iOS/macOS (Apple's licence forbids Xcode off Apple hardware) and Windows
      desktop apps.

---

## Code Extensions
- [x] Add code extensions for each supported setup. Surveyed all 32 language templates: 24 had one, 8 did
      not. crystal, elm, julia, nim, rescript, roc and swift gained curated extensions (all ids verified on
      both registries); fsharp had one that had never worked. `dotnet` still has no `vscode-ext` of its own —
      its setup is reachable only via `csharp+vscode-ext`, and is Marketplace-only anyway, so it is covered
      by the code-server gap item below rather than being a separate hole. Remaining candidates would be
      languages outside `templates/languages/` (e.g. Racket via `education/drracket`).
      The arbitrary escape hatch now exists (`install code-extension <id>` / `code-ext-pkg`), so this item
      is only about *curated* coverage: a user shouldn't need to know a marketplace id to get a working
      editor for a language the catalog already installs. New ids must be checked against Open VSX
      (`curl -s -o /dev/null -w '%{http_code}' https://open-vsx.org/api/<pub>/<name>`) — code-server does
      not query the Microsoft Marketplace, and the publisher frequently differs between the two.
- [ ] code-server has no C#, C/C++, IntelliCode, or Lombok extension. Four curated ids are Marketplace-only,
      so Open VSX has nothing to resolve and code-server users go without. They are now scoped with
      `install_vscode_extensions` (explicit, and no longer a warning on every code-server build), but that
      only documents the gap — it doesn't close it. Each needs its own decision, and each substitute must be
      verified on Open VSX first:
      - `ms-dotnettools.csharp` (`dotnet-code-extension`) — candidate: the community rebuild
        `muhammad-sammy.csharp`. Weigh trusting a third-party rebuild of a Microsoft extension.
      - `ms-vscode.cpptools` (`gcc-code-extension`) — `clang-code-extension` already installs
        `llvm-vs-code-extensions.vscode-clangd`, which is on both registries; possibly just point
        code-server users at that rather than duplicating it.
      - `visualstudioexptteam.vscodeintellicode` (`java-code-extension`) — AI completion polish, not
        language support. Probably fine to leave code-server without it permanently.
      - `vscjava.vscode-lombok` (`java-code-extension`) — never published to Open VSX, so Lombok annotations
        go unresolved in code-server. `redhat.java` still works; whether that is acceptable depends on how
        much Lombok the Java examples use.
- [ ] A failed extension install is invisible. `libs/code-extension-source.sh`'s `install_extensions` logs
      `⚠ Failed to install` and returns 0, so the build passes and the booth comes up without the
      extension — which is how the `JakeBecker.elixir-ls` bug survived unnoticed. The new
      `code-extension--install.sh` is strict, but the 33 curated setups are not. Making them strict is not
      obviously right: they are auto-selected, so one dead id would break every build that touches that
      language. A middle path (summarise misses at the end of the build, or a `booth doctor` check) is
      probably the answer. Note a wrong id does not always *fail*: `elixir-lsp.elixir-ls` resolves on the
      Marketplace to a deprecated stub, so the check has to be "did I get the right package", not just
      "did something install".
- [ ] `install code-extension` requires every editor in the image to accept the id, so a
      Marketplace-only or Open-VSX-only id fails the build on an image carrying both editors. Real
      variants ship exactly one editor, so nothing hits this today — but the curated setups solved the
      same problem with per-editor calls, and the arbitrary path has no equivalent. Either relax to
      "installed into at least one editor" or give the Boothfile a per-editor form
      (`install code-extension --vscode <id>` / `--codeserver <id>`).
- [ ] `setup vscode` fails on a bare base variant. `vscode--setup.sh` installs Jupyter and a Bash kernel
      with `pip` (line 66), and the base image ships no python at all — the build dies with
      `pip: command not found` after VS Code is already installed. The desktop variants never hit it
      because `xfce--setup.sh:31` runs `python--setup.sh` itself first, so the dependency is real but
      invisible. Either declare it (guard + a clear "run `setup python` first" message) or have the
      script install python itself, the way xfce does.
- [ ] The QEMU deferral is a no-op. `install_extensions` prints "deferring extension install to first
      launch" under `/dev/.buildkit_qemu_emulator` and returns — but nothing ever installs them later.
      Only `codeserver--setup.sh`'s launcher has a deferred path, and its list is hardcoded to
      `ms-toolsai.jupyter` + `ms-python.python`. So an arm64 cross-build silently ships without any
      language extensions. Fix shape: have `install_extensions` append its ids to a manifest
      (e.g. `/usr/local/share/code-server/.extensions-deferred`) that the launcher drains on first launch.

---

## Notebook Kernels
Add or expand support for additional Jupyter Notebook kernels:

- [ ] **PySpark** – Run Python code interacting with Apache Spark.
- [ ] **TensorFlow / PyTorch kernels** – Preloaded for machine learning frameworks.
- [ ] **IRkernel** – R language kernel, popular for data analysis and statistics.
- [ ] **Julia (IJulia)** – High-performance computing and numerical analysis.
- [ ] **SageMath** – Symbolic mathematics with the SageMath system.
- [ ] **Octave** – MATLAB-like numerical computing.
- [ ] **IHaskell** – Interactive Haskell programming.
- [ ] **C++ (xeus-cling)** – Interactive C++ kernel.
- [ ] **Node.js (IJavascript)** – Run JavaScript in Jupyter.
- [ ] **Ruby (IRuby)** – Enable Ruby scripting.
- [ ] **SQL** – Execute SQL queries directly within notebooks.
- [ ] **MATLAB** – Integrate MATLAB code execution.
- [ ] **Fortran** – Support for scientific computing with Fortran.

