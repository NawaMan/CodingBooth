# TODO

This is where dreams begin. ✨  
A list of upcoming ideas, improvements, and future goals for the CodingBooth launcher.

Status markers: `[ ]` open · `[x]` done · `[~]` partial · `[-]` rejected/abandoned ·
`[?]` **to relook later** — still has value, but the direction is unclear or it is not a priority yet.
A `[?]` item is parked on purpose: don't merge it, don't delete it, and don't re-propose it as new.

**Open items now live on the todos board** (CodingBooth project). They moved there on 2026-11-11,
each with the full text it had here. This file keeps the done record, the parked notes, and design
context; add new open work to the board.

---

## Code Features

## Features
- [x] Add TESTS, add TESTS, add TESTS, add TESTS!!!
- [-] Remove CVEs for docker images -- give up (most found in core pages like python, nodejs, etc)
- [x] Try to not have "user-land" setup print anthing (unless error) -- nodejs-example
- [x] Improve Docker-in-Docker (DinD) integration — ideally without relying on a sidecar container.
- [x] Add Kubernetes (K8s) support.
- [-] Rename “variant” to “interface” for clarity: -- NOTE: `variant` is good.
- [x] Add desktop icons for IDEs (e.g., VS Code, JetBrains IDEs).
- [-] Simplify adding Jupyter Notebooks to desktop environments (auto-add like VS Code).
- [X] Install jpterm - for all variants. https://github.com/davidbrochart/jpterm
- [-] Install yazi CLI file browser - for all variants. https://lindevs.com/install-yazi-on-ubuntu
- [x] Change to use JJava instead of IJava. https://github.com/dflib/jjava
- [X] Add template repository.
- [x] Firebase example / home-seed placeholder — `setup firebase` startup now
      re-applies host `firebase-tools.json` when the dest is missing, empty, or only
      `{}` (firebase-tools' unauthenticated stub). Real in-container logins are left
      alone. Credential extension remains a single-file seed mount; no new global
      home-seed mode.
- [x] Report container with the same name exists better. Also suggest how to remove the container.
- [x] **Persist browser bookmarks & history** — largely done (see [BOOTH_SHARED.md](BOOTH_SHARED.md)).
      - Local full profiles: `+profile-cache` (cache; Chrome/Chromium → `~/.chrome-data`) and
        `--persist-home`.
      - Team/git: `.booth/shared/` + `+bookmarks-shared` / `+settings-shared` / `+extensions-shared`
        for Chrome, Chromium, Firefox; drivers need jars **and** `drivers.xml` registry.
      Deliberate non-goal: sharing History SQLite via git (personal noise, bad merges).

- [x] **i3 on KDE.** `i3--setup.sh` covers XFCE and LXQt; Plasma 5.27 can run another window
      manager in place of KWin (`KDEWM`), but plasmashell's desktop, panel and pop-ups need several
      i3 rules, and results are uneven. Worth trying behind the same `start-i3` / `stop-i3`.
      -- Tiling on KDE done another way: the `bismuth` template (a KWin script, so KWin and
      plasmashell stay untouched) with `start-bismuth` / `stop-bismuth`. i3-as-KDEWM not pursued.
      -- On Ubuntu 26.04 (Plasma 6, no kwin-bismuth) this became the `krohnkite` template
      (`start-krohnkite` / `stop-krohnkite`); the `setup bismuth*` shims to it were later removed.
- [x] **A sway (Wayland tiling) option.** i3 is X11-only; sway reads nearly the same config and is
      what wayvnc was built for. It would replace labwc rather than live inside a desktop, so it is
      closer to a variant (or a `wayland` alternative) than an `i3` extension. The i3 Help tab and
      Ctrl+Alt twins would carry over.
      -- Done as the `sway` template: `start-wayland` reads the compositor from
      `/opt/codingbooth/wayland-compositor` (`WAYLAND_COMPOSITOR=labwc` overrides for a run).

## Problems
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

- [x] `remove`/`stop`/`start`/`restart` parse flags after positional names, using the registered flag definitions. They also accept explicit `--engine` selection.

---

## Parked — to relook later

Work that exists outside `main` and still has value, but is blocked on an undecided question or simply
isn't a priority. Audited 2026-07-25. Everything *not* listed here was checked and is already in `main`
— see the note at the end.

- [x] **A `templates/frameworks/` tier (django, spring)** — **Settled 2026-10-05:** a top-level
      `frameworks/` category, not extensions on a language, because a framework does not pin its
      runtime (React on nodejs / bun / deno; Spring Boot on java / kotlin). Shipped editor-only:
      react, vue, angular, svelte, tailwind, spring-boot, django. Scaffolding / dev-server autostart
      is the open follow-up. The stash notes below are kept for history.
      `stash@{0}`, from the since-deleted
      `feature/BoothDesign` worktree (Feb 2026).
      Most of the stash is dead: it is written in the old `spec.toml` format, and `main` has **zero**
      `spec.toml` files (the format is now `template.toml` + `*--extension.toml`). Its go, java, python, and
      maven specs are all superseded — maven now lives as
      `templates/languages/java/maven--extension.toml`.
      The one idea that did *not* land: a **framework** category. `main` has `languages`, `tools`,
      `ides`, `middlewares`, `desktops` (browsers live here), `ai-tools`, `education` — but no framework tier, so
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

## Data modes (0.83.0 line)

One extension per data item (`+config`, `+history`, `+bookmarks`, `+pkg-cache`, `+data`, …), with
where it lives — bind / seed / cache / shared / volume — chosen as its value (`neovim+config:shared`).

Plan, inventory and phases: **[TODO-data.md](TODO-data.md)**.

Tracked on the todos board as #199 (CodingBooth project).

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
- [x] `clang`
- [x] `cmake`
- [x] `conda`
- [x] `deno`
- [x] `docker` (dind)
- [x] `dotnet`
- [x] `elixir`
- [x] `erlang`
- [x] `gcc`
- [x] `gcloud`
- [x] `go`
- [x] `haskell`
- [x] `julia`
- [x] `k3d`
- [x] `k9s`
- [x] `kafka`
- [x] `kind`
- [x] `kotlin`
- [x] `kubectl`
- [x] `kubectx` + `kubens`
- [x] `lua`
- [x] `make`
- [x] `mongodb`
- [x] `mysql`
- [x] `nodejs`
- [x] `ocaml` — experimental: prebuilt compiler and tools ship; `ocaml-example` exercises them, no `tests/` suite; local source builds are never automatic.
- [x] `php`
- [x] `postgres`
- [x] `rabbitmq`
- [x] `roc`
- [x] `r-rscript`
- [x] `ruby`
- [x] `rust`
- [x] `sbt`
- [x] `scala`
- [x] `swift`
- [x] `zig`
- [x] `terraform`
- [x] `helm`
- [x] `aws-sam-cli`
- [x] `aws-cdk`
- [x] `gh-copilot`

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

---

## Notebook Kernels
Add or expand support for additional Jupyter Notebook kernels:

- [x] **IRkernel** – R language kernel, popular for data analysis and statistics.
- [x] **Octave** – MATLAB-like numerical computing.
- [x] **IHaskell** – Interactive Haskell programming.
- [x] **C++ (xeus-cling)** – Interactive C++ kernel.
- [x] **Node.js (IJavascript)** – Run JavaScript in Jupyter.
- [x] **Ruby (IRuby)** – Enable Ruby scripting.

