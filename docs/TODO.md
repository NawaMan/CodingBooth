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
      commit `Boothfile` + `config.toml` + `.generated`; a `Justfile` when the sample has in-booth
      `build`/`run`/`test` (wrap the scripts; in-booth sample tests call `just <recipe>`);
      `.cb-tests/tags.txt` + a smoke test on an unused
      `CB_PORT` (they are allocated in steps of 10 — grep the existing ones); a README in the sibling
      house shape (what it demonstrates → Run → What's inside, leading with `just --list`); then the three catalog surfaces
      (`EXAMPLES.md`, `docs/EXAMPLES_ADVANTAGES.md` prose *and* table) and a `docs/CHANGELOG.md` entry.
      Open questions: how far it should push on proving the example works. `pocketbase-example` shipped a
      cheap `go version` smoke test matching its siblings, with the real proof done by hand at authoring
      time (build, serve, curl) — worth deciding whether the skill mandates the deeper `inBooth-*` shape
      `go-example` uses, or keeps the cheap default and just *requires* the hand-proof be reported.
- [ ] **`--profile=dev` (the `=` form) is silently ignored — and the implicit `default` profile then
      applies.** Not specific to profiles: no booth flag accepts `--flag=value` (`--port=9500` is
      ignored the same way, verified 2026-09-21), so the arg is skipped without a word. With profiles
      it bites harder: a typo'd `=` form quietly runs whatever `default--config.toml` says.
      Approach: `parseFlag` in `cli/src/pkg/booth/profile/profile.go` and the `switch arg` in
      `parseArgs` (`initialize_app_context.go`) both match the literal `--profile`. Cheapest: reject any
      `--profile=…` with an error pointing at `--profile <name>`; better: normalise `--x=v` → `--x v`
      once, up front, for every flag that takes a value.
      Open questions: reject vs accept, and whether to do it CLI-wide — a global change to how args are
      read, so it needs a look at flags whose values may legitimately contain `=` (`--build-arg K=V`,
      `-e K=V`, everything after `--`). Documented in `docs/BOOTH_PROFILES.md` meanwhile.
- [ ] **`{profile}` placeholder for `--name`** — a profile does not change the container name, so two
      profiles of one project only stay apart via the derived-name auto-suffix (`proj`, `proj-12000`),
      which says nothing about *which* profile is which. `name = "{project}-{profile}"` in a base
      config would fix that without an overlay per profile.
      Approach: `ResolveNamePlaceholders` in `cli/src/pkg/booth/resolve_name.go` already expands
      `{port}`/`{project}`/`{variant}` from `ctx`; `ctx.Profiles()` has the resolved names. Join with
      `-` for `--profile a,b`; expand to empty (and trim the dangling separator) when none is selected.
      Open questions: that empty case — `{project}-{profile}` with no profile should probably be plain
      `{project}`, not `proj-`. Also `booth stop`/`exec`/`shell` resolve by folder name and never read
      config, so a profile-derived name still needs to be passed to them explicitly (same limitation as
      `name` in `config.toml` today).
- [ ] **Profile merge decisions left open.** (a) `egress-allowlist` in an overlay currently *replaces*
      the base list while `run-args`/`build-args`/`common-args` union — so a profile that wants to
      *add* one host silently drops the rest. Fail-closed here (a shorter list only narrows egress),
      but surprising. Pinned as replace by `TestMergeProfileToml_EgressAllowlistReplacesNotMerges`, and
      `TestMergeProfileToml_EveryListKeyHasADeclaredRule` forces a decision for any new list key.
      Approach if unioned: add it to the `md.IsDefined` cases in `MergeProfileToml`
      (`cli/src/pkg/appctx/app_config_merge.go`) — `mergeSemicolonList` is typed for the docker-arg
      lists, so this one needs a small `[]string` variant of it (`dedupDockerArgs` itself is fine:
      host names never match a paired flag) — then move it between the two sets in that test.
      Open question: whether union is right at all — for an allowlist, "replace" is also how a profile
      would *tighten* a base list, which union can't express.
      (b) `booth profile list` was in the original design and never built;
      users currently `ls .booth/*--config.toml`. `profile.Discover` already returns everything it
      would print.
      (c) The profile collision check (`profile.FindCollisions`, called from `checkProfileCollisions`
      in `cli/src/pkg/booth/init/initialize_app_context.go`) covers `-e`, `-l`, `--build-arg`, `-v`
      target and `-p` host/container port. Other docker flags in `run-args` — `--cpus`, `--memory`,
      `--network`, `--user`, `--name`, … — are still just concatenated and Docker's last one wins, so
      an overlay can still silently override a base `--cpus`. Extending it means a table of which
      flags are single-valued (collide on the flag name) versus repeatable (`--add-host`, `--device`,
      `--cap-add` legitimately repeat); a wrong table entry is a false error, so add flags one at a
      time. Left as is: within one config, booth still silently keeps the first bind mount per target
      (`filterMissingVolumeMountItems` in `booth.go`) — that is deliberate, for templates listing one
      mount per platform for the same target — and a repeated `-e` in a single file is Docker's.
- [ ] ...

## Features
- [ ] **Extend `--egress` to DNS: today it filters HTTP(S) only, so data can still leave in DNS
      queries.** Not a bug — DNS is let out on purpose (`cli/src/pkg/booth/egress_setup.go:455-456`,
      documented in `docs/implementations/EGRESS.md`), and egress was built as an HTTP(S) host
      allowlist, not a no-exfiltration boundary. The consequence: code in the booth can tunnel data
      in query names to an authoritative server it controls (or via any public resolver), past an
      allowlist that otherwise holds.
      Why extend it: `--egress` is what we tell people to use before letting an AI agent or an
      untrusted dependency loose, and that use reads as "nothing leaves but the allowlist". For the
      interview case it backs *Lockdown mode* below, so DNS does not stay open beside it.
      Simplest approach: under egress no booth process needs DNS — clients send `CONNECT host:443`
      and Envoy (UID 101) resolves. So allow 53 *and* Docker's embedded `127.0.0.11` (on `lo`, so
      today's `-o lo` ACCEPT lets it through) only for UID 101, reject for everyone else. Also: there
      are no `ip6tables` rules at all — check whether the egress net can get IPv6, and deny-all it.
      Fuller approach, if names must resolve in the booth: pin DNS to a resolver we run in the egress sidecar (beside Envoy, its own UID) that
      only answers names on the allowlist and refuses the rest; point the booth's `resolv.conf` at
      it; replace the two `--dport 53` ACCEPTs with an accept to that resolver only, plus an
      owner-match for the resolver's upstream lookups. A booth that names its own `--dns` keeps it
      only through the same resolver.
      Open questions: which resolver (dnsmasq vs Envoy's DNS filter vs CoreDNS) given image size;
      how wildcard allowlist entries (`*.example.com`) map to DNS rules; what Envoy's own upstream
      resolution uses once 53 is closed; whether `egress-policy-file` (raw Envoy RBAC) users get
      the DNS pin too or must list names twice.
- [ ] **Session replay — watch afterwards how a booth session was worked.** Record a session so it
      can be played back as one timeline: the code as it changed, the terminals, the screen, and the
      AI agent's conversation. Use case: AI-allowed interviews on CodingBoothSaas (how the candidate
      steered Claude, checked its work, fixed things by hand matters more than the final diff);
      also teaching (review a student's path, not just the result).
      Layers, cheapest first — each useful alone:
      - **Code snapshots.** A daemon commits the workspace every ~10s and on change into a hidden
        repo *outside* it (`git --git-dir=/var/cb-replay --work-tree=~/code`), so the user's own git
        history is untouched. Replay = slider over commits with the diff at each step.
      - **Terminals.** Record each Console UI tmux pane (`tmux pipe-pane`) or wrap the shell in
        `asciinema rec`; asciinema-player plays it in a browser.
      - **Screen (desktop variants).** On XFCE the whole session is one X display, so
        `ffmpeg -f x11grab` at a low frame rate is a full video of editor + terminal + browser. The
        TigerVNC server is also the clipboard boundary (`SendCutText`/`AcceptCutText`,
        `variants/base/setups/xfce--setup.sh`): log what crosses it — paste-in from outside is an
        interview signal, copy-out is the leak.
      - **Agent transcript.** Claude Code already writes every session to
        `~/.claude/projects/<path>/<session>.jsonl` (prompts, replies, tool calls + results,
        timestamps). Raise `cleanupPeriodDays` (default 30) so it survives. Candidate-proof copy:
        OpenTelemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_LOG_USER_PROMPTS=1`) forced through
        the root-owned managed settings, exported to a collector outside the container — verify how
        much tool detail the OTel events carry before relying on it.
      - **Keystroke-level editor** (later, hardest): a code-server extension logging
        `onDidChangeTextDocument` + cursor events.
      Approach: booth side is a setup + startup hook (`variants/base/setups/`, a template under
      `templates/` to turn it on), recorders running as **root** from the startup hook and writing to
      a root-only dir — the user is `coder` without sudo and must not delete or edit the record
      (every web/VNC process runs as `coder`, so a recorder that does too is one `pkill` away).
      Collected on stop alongside the save-back. The review page (one timeline: snapshots +
      terminals/screen + transcript lined up by time) and storage are CodingBoothSaas work.
      Open questions: privacy/consent notice to the user being recorded; storage size (low-fps
      x11grab ≈ some hundred MB/hour — measure); whether snapshots should skip `node_modules`,
      `target/` etc. via the workspace `.gitignore`; one combined format or per-layer files the
      review page aligns.
- [ ] **Lockdown mode — make leaking a booth's code harder (not impossible). Deferred 2026-10-30.**
      One switch for a "use it, don't take it" booth — the CodingBoothSaas interview case, on the
      **XFCE** variant. Goal is *harder*, not *impossible*: screenshots and retyping always remain,
      and the candidate is expected to be watched (or replayed — see *Session replay*).
      Why it has value on XFCE (and little on a web IDE): with a web IDE (code-server, Console UI)
      file contents themselves reach the user's browser — devtools, `base64` in a pane, a `/dump`
      route in their own app behind the port proxy — so no flag closes it. On XFCE the editor,
      terminal and the browser that tests the web app all run *inside* the desktop; the user's
      browser only receives pixels and the clipboard. So the port proxy is not needed for a web-app
      exercise there, and closing the remaining file routes leaves just screen + clipboard.
      Pieces:
      - `--no-port-proxy` (one flag): drop the nginx `/proxy/<port>/` locations
        (`variants/base/web-ttyd-split/nginx.conf.template`,
        `variants/base/setups/booth-web-preview/nginx*.conf.template`) and pass code-server
        `--disable-proxy` — the codeserver variant's nginx forwards `/proxy/` to code-server's own
        proxy, and `/absproxy/` reaches it directly, so both places. Not `--no-proxy`: that reads as
        "bypass the egress proxy" (`NO_PROXY`).
      - Clipboard at the VNC boundary (`variants/base/setups/xfce--setup.sh`): TigerVNC
        `SendCutText=0` blocks copy-out while paste-in still works; or keep it on and log what
        crosses (paste-in is an interview signal, copy-out is the leak).
      - `--lockdown` sets those and checks the rest: requires `--egress` (ideally with the DNS
        extension above), forces `--no-sudo`, refuses `--dind`, the host-escape consent set
        (`cli/src/pkg/booth/host_escape_consent.go`), home-folder credential mounts in `run-args`,
        extra `--expose`/`--port`, and a `coder` UID of 101 (Envoy's — it would bypass the
        firewall). Refuse variants whose browser channel can't be narrowed (notebook; base/codeserver
        get only the port-proxy part).
      Limits to write into `docs/BOOTH_SECURITY.md`: every web/VNC process runs as `coder`, so the
      user can restart VNC or nginx with other options — fine while watched (it drops the
      interviewer's view), not tamper-proof unattended; text copied out of what is on screen and
      `api.anthropic.com` with the user's own key (Files API) both stay open.
      Open questions: what else the desktop variant's nginx serves besides noVNC; whether
      `CB_LOCKDOWN` is read at start or baked at build (it must not be user-settable inside);
      a `tests/basic/` case that tries each route and expects it closed.
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
      - **KDE desktop icon positions** — the one desktop the icon-persistence extensions skip.
        XFCE and LXQt ship `+desktop-icons-cache` / `+desktop-icons-shared`; KDE has no route,
        and the reason is worth not re-deriving. Plasma keeps the whole desktop layout in
        `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, which KConfig rewrites by rename.
        Measured, all three obvious routes fail: a file bind mount rejects the rename with
        `EBUSY` (so every save is silently lost); a symlink into a mounted dir is replaced by
        the first save when its target starts empty — and the target *must* start empty,
        because Plasma has not written the file yet when startup hooks run; and copy-in +
        mirror-back is worse than nothing, since Plasma regenerates the layout at session start
        and the mirror then overwrites the good saved copy with the regenerated one.
        `--persist-home` works (it keeps the whole home, so nothing is regenerated).
        A real fix likely means `kde--setup.sh` teaching Plasma to keep the layout elsewhere —
        an image change, not a template one.
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
- [ ] **A Rust desktop-app recipe (`@rust-desktop`) and a Rust-aware `booth just-init`** — from P6 in
      `docs/TODO-0.80.0.md`. Nine Rust desktop-app projects each assembled the same selection and the same
      Justfile by hand. Recipes as a feature need more design first (2026-10-11), so this is parked until
      then.
      Approach:
      - *Recipe:* `rust+targets:wasm32-unknown-unknown+gui-deps+cargo-pkg:--locked,trunk`, `gh`, on
        desktop-xfce, selectable as `--select @rust-desktop/claude-code+…`. The `@a/b` combining already
        works (`OpenExternalSelect` in `cli/src/pkg/boothinit/selection/recipe.go`).
      - *just-init:* keep the generic starter (`cli/src/pkg/justinit/Justfile`, kept byte-identical to
        `docs/just/Justfile` by `TestStarterMatchesDocs`). When `Cargo.toml` is present, append a Rust
        block: `build`/`test`/`run`/`clippy` as `{{run-in-booth}} cargo …`, plus `ci` (`cargo xtask ci`)
        when an `xtask/` crate or a `.cargo/config.toml` `xtask` alias exists, and `web`
        (`trunk serve --address 0.0.0.0`) when `Trunk.toml` exists. It also runs on create and on the
        first configure, so detection applies there too.
      What the 2026-10-11 research found:
      - **There are no built-in recipes.** A bare `@name` resolves only from the project's own
        `.booth/recipes/` (`readRecipeRef`, and `expandRecipeSelection` in `cli/src/cmd/codingbooth/config.go`).
        A catalog recipe means a second lookup, for example `<templates>/recipes/<name>.recipe` after the
        project's copy, a Recipes-tab listing, and a place under catalog versioning (cb-version, manifest,
        release check).
      - **A recipe can't pick a variant.** The selection language has no variant syntax, and the `xfce`
        template only does `setup xfce`. The options are a variant line in the recipe language, a
        template or extension that sets the `variant` scalar, or documenting `--variant desktop-xfce`.
      - **There's no trunk template.** `cargo-pkg:--locked,trunk` covers it, but the compile is slow.
      - **`run` depends on P5.** `exec` has no `DISPLAY`, so a GUI `run` either waits for P5
        (`DISPLAY=:1` on desktop images, and `exec --run` waiting for the desktop) or gets an interim
        `DISPLAY=${DISPLAY:-:1}` wrapper.
      Open questions: what built-in recipes look like in general (location, listing, versioning) before
      adding the first one; how a recipe chooses a variant; whether P5 lands first.
- [?] **Support setup scripts copied from a newer CodingBooth (`booth vendor`)**, from P7 in
      `docs/TODO-0.80.0.md`. Low priority: it matters once many projects pin older versions. Projects
      pinned to 0.79.0 needed newer setup scripts, so three were copied into `.booth/setups/` by hand.
      Nothing records where they came from. Once a release catches up they keep overriding the image's
      own scripts without a word, because `.booth/setups/` comes first on `PATH`
      (`cli/src/pkg/boothfile/compiler.go`, `ProjectSetupsPath`). A 0.79.0 `booth config` also rejects
      the newer extensions (`rust+targets`, `rust+gui-deps`) with a bare `unknown extension`.
      Approach:
      - `booth vendor <setup> [--from <version>]` (default: latest release) fetches the script at that
        release tag and writes it to `.booth/setups/` with a header such as
        `# cb-vendored-from: CodingBooth 0.81.0 (variants/base/setups/rust--setup.sh) sha256=…`. It
        warns about the `cb-has-*` / `libs/` helpers the script uses, since a newer script can need a
        newer helper.
      - At Boothfile compile time, a vendored copy whose release is the same as or older than the
        booth's own version gets a "safe to delete" warning. A sha256 mismatch shows it was edited
        after vendoring. A copy with no header is the project's own script, so it gets no warning.
      - `unknown extension` / `unknown template` (`selection/resolver.go`) says the name isn't in
        this version's catalog but is in a newer release (latest: X). The release workflow
        publishes `build/catalog-manifest.tsv` as an asset, fetched once and cached. With no network
        it falls back to an offline "may need a newer CodingBooth".
      What the 2026-10-11 research found:
      - **`cb-version` and the manifest landed after the `0.79.0` tag.** 0.79.0 scripts have no version
        header, and only `templates.zip` is a release asset today.
      - **A project-local extension can't attach to a stock parent** (`template/merge.go`), so making
        `rust+targets` selectable under an old pin means overriding the whole `rust` template
        locally.
      - **It can't help a project whose binary stays at 0.79.0.** It helps from the next pin on, or
        when the binary is newer than the image.
      Open questions: whether `booth vendor` also copies whole template folders (so newer extensions
      become selectable) or only scripts; an exact "added in X" would need a `since` column in the
      manifest rather than only "latest has it". Suggested worktree: `worktree/vendor-scripts`.
- [ ] ...

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
- [ ] **Desktop templates on `base` build a desktop that never starts.** Selecting `xfce` / `lxqt`
      (or `i3`) on the `base` variant installs the desktop into the image while the booth still
      opens the Console UI — by design, so `start-desktop` can bring it up later, but it costs image
      size silently. `booth config` could say so when a desktop template is picked on `base`.

## Problems
- [ ] **The host-escape warning judges only POSIX mount sources, so a Windows host gets none of it.**
      `dangerousMount` (`cli/src/pkg/booth/host_escape_consent.go`) returns "not a host path" for
      anything that does not start with `/`, which on Windows is every real mount a user writes:
      `-v C:\Users\me\.ssh:/x` and `-v C:\:/host` start a booth with no warning and no question,
      while the same booth on Linux stops and asks. The POSIX half now works on every host (it used
      to be judged with `filepath.Clean`, which rewrote `/etc` as `\etc` and matched nothing), but
      the Windows half needs its own list: the user profile and its dotfiles, `C:\Windows`,
      `C:\ProgramData`, a bare drive root, and the `\\.\pipe\docker_engine` named pipe for the
      engine socket. `docs/BOOTH_SECURITY.md` has to say which of them count as "as root" once
      Docker Desktop's VM is in the middle.
- [ ] **A linked git worktree gets no `.git` mount on a Windows host.** `resolveGitWorktreeMount`
      (`cli/src/pkg/booth/git_worktree.go`) mirrors the main repository's `.git` at the host's own
      absolute path, which only works where that path is also a path a container can hold: a
      Windows gitdir (`C:/proj/.git`) is refused with a warning, so git inside the booth sees a
      `.git` file pointing nowhere. The fix is a translated target — mount the main clone's `.git`
      somewhere mountable and rewrite the worktree's `gitdir`/`commondir` to match — which is more
      than the "same path on both sides" trick the Unix case gets away with.
- [ ] **Open risks from the 0.79.0 catalog sweep (2026-10-03, n−1 rule applied).** Each is a
      guess until the full suite runs on the 26.04 images; drop the line once a run settles it.
      - **Held at the previous major on purpose:** mermaid 11.17.2 (12.1.0 is out), appwrite-server
        1.9.6 (2.3.0 is out; its compose/migration needs a look), ruby 3.4 (4.0.7), erlang OTP 28 (29),
        lua 5.4 (5.5), clang/LLVM 22 (23), go 1.26.8 (1.27.1 only added to suggests), zig 0.16.0
        (0.17.0 is two days old), python 3.14.8 (3.15.0 just cut), conda's python 3.13 (3.14 not
        offered). Revisit each at the next sweep; none of the newer majors has been tried in a booth.
      - **Bumped but not yet built:** python 3.14.8 (default jumps a minor: 3.13 → 3.14 — watch
        packages without 3.14 wheels), zig 0.16.0 (0.15 → 0.16 breaks std APIs; zig-example code may
        need updating), julia 1.13.1, appwrite-cli 28.1.0, hoppscotch 2026.9.0, wails v3.0.0-beta.27, mermaid 11.17.2.
      - **Not checked by the sweep:** greenfoot (no parseable latest), haskell's `recommended`
        (ghcup decides), older entries deep in the go/rust/python/scala/kotlin suggests lists.
- [ ] **Desktop variants' clipboard still needs noVNC's manual side panel.** Investigated
      2026-09-23 while looking at browser-UI friction (see `docs/implementations/DESKTOP_NOVNC.md`'s
      "Clipboard Not Working" section). Two separate blockers, confirmed by inspecting a built
      `desktop-xfce` image:
      - The vendored noVNC was **1.3.0** (Ubuntu 24.04's `novnc` apt package, from 2021) — five
        majors behind current stable (1.7.0). The base moved to Ubuntu 26.04 on 2026-09-29, whose
        `novnc` is **1.6.0**; re-check both blockers against it before acting on this item. Its `app/ui.js`/`core/rfb.js` have only the manual
        clipboard-panel flow (`clipboardSend`/`clipboardReceive`/`clipboardPasteFrom` wired to a
        textarea + button), no `navigator.clipboard` code at all.
      - Real automatic clipboard sync (noVNC PR #1993, `navigator.clipboard` auto-sync when the
        browser grants permission) merged to noVNC's `master` branch in Oct 2025 but is **not in
        any tagged release**, including the current 1.7.0 — a noVNC maintainer said on the PR it
        "should not be released until we have an idea on how to bring Safari and Firefox in to
        the fold." So there is no stable, pinnable noVNC version with this feature yet, only a
        moving, explicitly-not-ready `master` snapshot — vendoring that would fight this repo's
        pinned/reproducible-build stance.
      Approach: revisit once noVNC actually tags a release containing PR #1993, then vendor that
      pinned version in `variants/base/setups/xfce--setup.sh` (and the kde/lxqt/wayland
      equivalents) instead of apt's stale package. Bumping to the current 1.7.0 apt-free is a
      separate, smaller, lower-risk task worth doing on its own merits regardless of clipboard.
      Open questions: whether to self-host a noVNC tarball per variant (reproducibility) vs. track
      upstream apt; whether Firefox/Safari being permanently second-class here is acceptable.
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
      Enforcement shipped too: `tests/config/catalog/test93-booth-files-are-clean.sh` fails on any committed
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
- [ ] **`firefox+managed-policies` leaves Firefox without a bookmarks toolbar.** Its
      `DisableTelemetry` policy (`variants/base/setups/firefox-managed-policies--setup.sh`) stops
      Firefox 157 creating its bookmarks database on first start: `places.sqlite` gets only the root
      and `menu` folders — no `toolbar`, `unfiled`, `mobile` or `tags`. Found 2026-10-10 by bisecting the
      four policies one by one; deterministic, a 75 s wait does not finish it, a restart does not
      repair it. Removing `DisableTelemetry` alone fixes it.
      Why: every `+managed-policies` user has a toolbar the policy forces visible but nothing can be
      saved to, and `firefox+bookmarks-seed` cannot import into it — so `browser-shared-example`
      drops `+managed-policies` from Firefox for now.
      Approach: replace the `DisableTelemetry` policy with the telemetry prefs it stands for, set
      through the `Preferences` policy (`toolkit.telemetry.*`, `datareporting.*`), then check the
      database is complete and the seed imports — the probe: on the host, count
      `moz_bookmarks` rows with `fk IS NULL` in the profile's `places.sqlite` (6 is complete). Then put `+managed-policies` back in
      `browser-shared-example`.
      Open questions: whether the prefs route disables as much as the policy does; whether a newer
      Firefox fixes it first.
- [ ] **Chromium does not start in a booth: "No usable sandbox".** On the 0.80.0 XFCE image
      `chromium-browser` (Debian Bookworm build, `variants/base/setups/chromium-browser--setup.sh`)
      exits at once — the container has no unprivileged user namespaces for its sandbox, and the
      launcher has no fallback. Chrome on the same image starts. Found 2026-10-10; it also kept a
      `chromium+bookmarks-seed` from shipping, since it could not be shown to work.
      Approach: compare with `google-chrome--setup.sh`'s launcher and the `chromium-sandbox`
      package; failing that, a `--no-sandbox` launcher flag, stated as the tradeoff it is. A
      `tests/complex/boothfile/test-boothfile-chromium` that actually opens a page would catch it.
      Then add `chromium+bookmarks-seed` (a copy of Chrome's — same `~/.chrome-data`, same format).
      Open questions: is `--no-sandbox` acceptable inside a booth, which is already the isolation
      boundary?
- [ ] **Setups resolve "latest" through the unauthenticated GitHub API, which CI rate-limits.**
      51 setups in `variants/base/setups/` run `curl https://api.github.com/repos/<o>/<r>/releases/latest`
      with no token. That API allows 60 requests an hour per IP, and shared GitHub runners share IPs,
      so a complex shard that installs a few such tools can hit the limit. The likely case:
      `boothfile/test-boothfile-cmake` failed twice in release run 39367607965 (build step, ~5s, no
      output kept), passed locally and passed on the next run. Unconfirmed, because the log drops the
      build output.
      Approach: resolve the version the way `codeserver--setup.sh` already does, by following the
      `https://github.com/<o>/<r>/releases/latest` redirect and reading the tag from the `Location`.
      That page is not rate-limited like the API. Put it in one shared helper rather than 51 copies.
      Each touched setup needs a `cb-version` bump and a manifest regen (catalog versioning).
      Open questions: also honour `GITHUB_TOKEN` when set (it helps CI, but a token must never be
      baked into an image layer)? Should the complex runner keep the failing build's output, so the
      next flake shows its real cause?
- [x] `remove`/`stop`/`start`/`restart` parse flags after positional names, using the registered flag definitions. They also accept explicit `--engine` selection.
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

## Data modes (after 0.81.0)

One extension per data item (`+config`, `+history`, `+bookmarks`, `+pkg-cache`, `+data`, …), with
where it lives — bind / seed / cache / shared / volume — chosen as its value (`neovim+config:shared`).

Plan, inventory and phases: **[TODO-data.md](TODO-data.md)**.

- [ ] Implement (planned after the 0.81.0 release)

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
- [ ] `ocaml` — experimental: prebuilt compiler and tools ship; `ocaml-example` exercises them, no `tests/` suite; local source builds are never automatic.
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
- [ ] code-server has no C#, C/C++, or IntelliCode extension. Three curated ids are Marketplace-only,
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
      `vscjava.vscode-lombok` (`java-code-extension`) was on this list too, but isn't actually a gap:
      never published to Open VSX, but `redhat.java` (installed for both editors) has shipped built-in,
      default-on Lombok support since v1.9 — it applies its own bundled lombok.jar to any project that
      declares Lombok as a dependency, no separate extension required. See the comment in
      `java-code-extension--setup.sh`.
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

