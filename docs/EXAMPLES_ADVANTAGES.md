# What Each Example Demonstrates

Every workspace in [`examples/workspaces/`](../examples/workspaces/) is a runnable booth, and
**isolation is the baseline for all of them** — your project files are mounted, everything else
is contained and ephemeral, and every file you create is owned by your host UID/GID. Isolation is
assumed everywhere and is not repeated below.

What this document catalogs is the *distinctive* advantage each example is built to show off — the
reason you'd reach for that particular example. Many examples demonstrate more than one thing; the
**Primary** line is the headline point and **Secondary** is a strong supporting one.

The advantages, in CodingBooth's own vocabulary:

| Advantage | The point |
|---|---|
| **Reproducibility** | Everyone's build resolves the same toolchain — no dependency drift, no "works on my machine." |
| **Precise version compatibility** | Interdependent versions that *must* agree (compiler ↔ runtime, headers ↔ shared objects). |
| **Batteries-included** | A painful multi-step host setup becomes one `booth` launch. |
| **Host stays clean** | Toolchains and globals live in the booth, never on the host OS. |
| **Pre-baked deps** | Dependencies resolved at *build* time, so the first run does no network round-trip. |
| **Multiple things bundled** | A full multi-service stack (or many tools) in one container. |
| **Try / compare side-by-side** | Run the *same* task across several runtimes/versions in one place, to test or compare them. |
| **Notebook / multi-kernel** | A fiddly Jupyter kernel comes pre-wired for interactive exploration. |
| **Port exposure** | A server inside the booth is auto-forwarded to the host browser. |
| **Credential seeding** | Use host credentials (cloud CLIs, registries) without copying secrets into the repo. |
| **Network egress control** | Restrict what the container is allowed to reach (allowlist / custom Envoy policy). |
| **Nested containers** | Run Docker / Kubernetes inside the booth without exposing the host Docker socket. |
| **Persistence / cache** | State survives restarts via `.booth/cache/` bind-mounts. |
| **Team config sharing** | `.booth/home/**` travels with the repo so everyone gets the same editor/tool config. |
| **Standardize-to-Linux** | Build once inside Linux, get cross-platform binaries that run natively on the host. |

---

## 🔁 Reproducibility — pin versions, kill "works on my machine"

- **apt-example** — `APT_SNAPSHOT` freezes the *entire* Ubuntu archive to a timestamp, so even
  unnamed transitive dependencies stay identical across rebuilds — something a bare version pin
  can't guarantee.
- **clang-example** — pins `LLVM_VERSION=18` plus an apt snapshot, so both the Clang toolchain and
  the system libraries are deterministic. *(Secondary: batteries-included — `install apt
  nlohmann-json3-dev` drops a header-only dep onto the default include path.)*
- **zig-example** — pins `ZIG_VERSION`, which matters because Zig's language and `build.zig` API
  break between fast-moving releases.
- **csharp-example** — pins the .NET SDK channel (`DOTNET_CHANNEL=9.0`) so everyone builds against
  the same SDK.
- **deno-example** — a committed `deno.lock` plus pinned `npm:` packages guarantee identical
  resolved dependencies on every run.
- **django-example**, **flask-example**, **fastapi-example**, **nextjs-example** — pin the
  interpreter/runtime (`python 3.13.12`, `nodejs 22`) alongside pinned framework versions, so the
  whole stack is fixed.

## 🔧 Precise version compatibility — toolchains that *must* agree

- **elixir-example** — `setup elixir --version 1.19.5` installs Elixir together with a compatible
  bundled Erlang/OTP, avoiding BEAM version-mismatch pain.
- **kotlin-example** — a matched Kotlin 2.0.20 compiler on Temurin JDK 21 (compiler and JDK must
  agree), all overridable via build args.
- **android-example** — the Android SDK is four separately versioned pieces (command-line tools, a
  platform, build-tools, and a JDK under them) behind an SDK manager that will not proceed until
  licenses are accepted by hand. All four are pinned build args here, licenses are accepted at image
  build time, and the APK builds with no Gradle and no network — so a green build proves the
  toolchain, not the package mirror.
- **spring-boot-example** — pinned JDK 21 + Maven 3.9.11 that must line up to build Spring Boot 3.4.
- **systemlib-example** — links real system libraries (libcurl, SQLite) whose headers *and* shared
  objects must both be present for CMake's `find_package`, with the exact library versions pinned by
  an apt snapshot.

## 🔋 Batteries-included — a painful setup becomes one command

- **haskell-example** — the GHC/Cabal/ghcup toolchain. See the honest note in
  [Caveats](#caveats--honesty-notes) below: this one is *not* magically painless; the example
  carries baked-in repair so the next person doesn't have to redo it.
- **rails-example** — Ruby + Postgres + Rails, with Postgres auto-starting so `rails new` works
  immediately.
- **go-example** — `gopls`, `delve`, the GoNB kernel, and code-server all assembled.
- **java-example** — JDK 25, Maven, the JJava kernel, *and* Eclipse + IntelliJ GUIs.
- **octave-example** — Octave + the Calysto kernel + gnuplot, preconfigured.
- **claude-example** — Claude Code CLI preinstalled in a minimal booth.
- **herdr-example** — a niche `herdr` tool plus a pinned clang/LLVM 18 toolchain in one selector.
- **zig-snake-example** — "no Zig installation required" on the host; `zig build run` just works.
- **playwright-example** — Node + Playwright + headless Chromium + VS Code extensions in one command.

## 🧹 Host stays clean — no global/system-wide installs

- **pip-example**, **npm-example**, **bun-example** — global CLIs and lint/test toolchains live in
  the booth, never in host site-packages or the global `node_modules`.
- **homebrew-example** — a large Linuxbrew set (neovim, ffmpeg, postgres, redis, nginx…) with
  nothing touching the host prefix.
- **php-example** — PHP + Composer in one line, no host system-PHP.
- **fsharp-example** — a niche F#/.NET toolchain fully in-container. *(Secondary: the Boothfile sets
  `DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK=1` precisely because the sandbox can't reach NuGet — evidence
  of a locked-down environment.)*
- **angular-example** — the heavy Angular CLI and its ~500-package `node_modules` stay in the booth.

## 📦 Pre-baked deps — offline-fast first run

- **pip-deps-example** — `pip install -r requirements.txt` runs during image *build*.
- **npm-deps-example** — `npm install` at build time; `node_modules` warmed and restored per session.
- **mvn-deps-example** — `mvn dependency:resolve` pre-populates `~/.m2`.
- **wordpress-example** — WordPress core downloaded into `/var/www/html` at build time.
- **playwright-example** / **playwright-polyglot-example** — the pinned Chromium is baked into the
  image, so nothing is downloaded at runtime.

## 🧩 Multiple things bundled — full stack / many tools in one container

- **lamp-example** / **lemp-example** — Apache-or-nginx + PHP + MySQL, all auto-starting, none on the
  host; a workspace-local `*-init` setup seeds the demo DB on boot.
- **mean-example** / **mern-example** / **pern-example** — Mongo/Postgres + Express + Angular/React +
  Node, DB auto-started, both tiers' ports exposed.
- **wordpress-example** — PHP + Apache + MySQL with the `wordpress` DB created on boot.
- **data-example** — an entire analysis workbench: PostgreSQL + DBeaver GUI + JupyterLab + a
  Node/Chart.js dashboard + Python, on an XFCE browser desktop, all wired to one seeded dataset.
- **jetbrain-exmple** — ten JetBrains IDEs plus JDK 24 in one KDE desktop booth.
- **js-example** — Node 20 + Bun + Deno pinned together so `--runtime=bun` swaps runtimes with no
  host setup.

## 🔬 Try / compare things side-by-side

These exist so you can **exercise, test, or compare several things in one place** — the container is
the common ground that makes the comparison fair (identical OS, identical dependencies underneath).

- **playwright-polyglot-example** — the *same* Playwright script written in JavaScript, Python, Java,
  C#/.NET, and Go, all bundled in one booth driving the same browser. Pick a language and compare the
  binding side-by-side; the four official bindings are all pinned to the same Playwright version so
  they share one pre-baked Chromium instead of each downloading its own.
- **all-java-example** — seven JDKs (8, 9, 17, 21, 23, 24, 25) plus Maven/Gradle/jbang and per-JDK
  IJava kernels in one container. `jenv local 21` switches the active JDK per project, so you can
  build and test the *same* code across Java versions to check compatibility — impractical to
  co-install on a host.
- *(Related: **js-example** bundles three JS runtimes and **jetbrain-exmple** ten IDEs for the same
  try-them-all reason.)*

## 📓 Notebook / multi-kernel — fiddly kernels made trivial

Each ships a Jupyter kernel whose installation is notoriously painful:

- **python-example** (ipykernel), **nodejs-example** (tslab JS/TS), **ruby-example** (IRuby),
  **rlang-example** (IRkernel), **rust-example** (evcxr — famously hard to build), **octave-example**
  (Calysto). Most also seed host credentials read-only and keep the host clean as secondary points.

## 🌐 Port exposure / server dev

- **server-example** — a Python `http.server` on 8080 auto-forwarded to the host browser (the
  canonical demo).
- **server-example-2** — the same, but `port = "NEXT:10000"` auto-picks the next free host port for
  conflict-free forwarding. *(Secondary: persists shell history + settings cache across restarts.)*
- **react-example** — Vite bound to `0.0.0.0` with port 5173 mapped to the host.
- *(Also strongly present in fastapi, nextjs, js, and every full-stack example above.)*

## 🔐 Credential seeding — host creds without secrets in the repo

- **aws-example** — mounts `~/.aws` read-only via `cb-home-seed`; a committed
  `.booth/home/.aws/config` pins the profile/region while secrets stay on the host.
- **gcloud-example** — mounts `~/.config/gcloud`, notably *read-write* — a documented tradeoff, since
  gcloud's SQLite state needs write/WAL access.
- **firebase-example** — mounts `firebase-tools.json` read-only so the `firebase` CLI works with no
  creds stored in the repo.

## 🛡️ Network egress control / security

- **egress-allowlist-extra-example** — `egress = true` enforces a domain allowlist (Envoy + iptables),
  merging a base file with an extra `egress-allowlist`; everything else is blocked.
- **egress-envoy-example** — the advanced path: a hand-authored custom Envoy RBAC policy file as the
  allowlist source, with direct-connect bypass firewalled.

## 🐳 Nested containers — Docker / Kubernetes without exposing the host socket

- **dind-example** — `dind = true` runs a Docker daemon sidecar; the host Docker socket is never
  shared, and all state vanishes on teardown.
- **kind-example** — a real Kubernetes cluster (KinD on DinD) fully inside the booth, NodePorts
  pre-mapped to the host.
- **kind-app-example** — a real microservices app (React + Go API + Go export + Postgres) deployed to
  a KinD cluster. *(Secondary: bakes a heavy, identical team toolchain — kubectl, kind, Go, Bun,
  Jupyter, AWS CLI.)*

## 💾 Persistence / cache across restarts

- **cache-example** — `cache-files`/`cache-dirs` bind-mount app data and shell history into the
  gitignored `.booth/cache/`, so state written in one session survives exit and restart.
- *(Also secondary in rust-example's cargo-registry mount and server-example-2's settings cache.)*

## 👥 Team config sharing (`.booth/home`)

- **neovim-example** — `.booth/home/.config/nvim/init.lua` is copied into the booth at startup, so
  everyone on the team gets the identical Neovim setup automatically.

## 🌍 Standardize-to-Linux / cross-platform parity

- **go-example** and **zig-snake-example** — cross-compile from the one Linux booth to
  linux/macOS/windows across amd64/arm64; the resulting binaries run natively on the host with no
  host toolchain installed.

## ⚪ Minimal / scaffold

- **empty-example** — a near-blank Boothfile: a clean, reproducible base to build any workspace on
  from scratch.

---

## Quick reference

| Example | Primary advantage |
|---|---|
| all-java-example | Try / compare side-by-side (7 JDKs) |
| android-example | Precise version compatibility |
| angular-example | Host stays clean |
| apt-example | Reproducibility (archive snapshot) |
| aws-example | Credential seeding |
| bun-example | Host stays clean |
| cache-example | Persistence / cache |
| clang-example | Reproducibility |
| claude-example | Batteries-included |
| conda-example | Batteries-included (data-science stack) |
| csharp-example | Reproducibility (pinned SDK) |
| data-example | Multiple things bundled |
| deno-example | Reproducibility (lockfile) |
| django-example | Reproducibility |
| dind-example | Nested containers |
| egress-allowlist-extra-example | Network egress control |
| egress-envoy-example | Network egress control (custom policy) |
| elixir-example | Precise version compatibility |
| empty-example | Minimal scaffold |
| fastapi-example | Port exposure |
| firebase-example | Credential seeding |
| flask-example | Reproducibility |
| fsharp-example | Host stays clean |
| gcloud-example | Credential seeding |
| go-example | Batteries-included / Standardize-to-Linux |
| haskell-example | Batteries-included (with baked-in repair) |
| herdr-example | Batteries-included |
| homebrew-example | Host stays clean |
| java-example | Batteries-included |
| jetbrain-exmple | Multiple things bundled (10 IDEs) |
| js-example | Port exposure / try runtimes side-by-side |
| kind-example | Nested containers (Kubernetes) |
| kind-app-example | Nested containers (microservices) |
| kotlin-example | Precise version compatibility |
| lamp-example | Multiple things bundled |
| lemp-example | Multiple things bundled |
| mean-example | Multiple things bundled |
| mern-example | Multiple things bundled |
| mvn-deps-example | Pre-baked deps |
| neovim-example | Team config sharing |
| nextjs-example | Port exposure |
| nodejs-example | Notebook / multi-kernel |
| npm-example | Host stays clean |
| npm-deps-example | Pre-baked deps |
| octave-example | Batteries-included / notebook |
| pern-example | Multiple things bundled |
| php-example | Host stays clean |
| pip-example | Host stays clean |
| pip-deps-example | Pre-baked deps |
| playwright-example | Batteries-included / pre-baked Chromium |
| playwright-polyglot-example | Try / compare side-by-side (5 languages) |
| python-example | Notebook / multi-kernel |
| rails-example | Batteries-included |
| react-example | Port exposure |
| rlang-example | Notebook / multi-kernel |
| ruby-example | Notebook / multi-kernel |
| rust-example | Notebook / multi-kernel (evcxr) |
| server-example | Port exposure |
| server-example-2 | Port exposure (auto-pick free port) |
| spring-boot-example | Precise version compatibility |
| systemlib-example | Precise version compatibility |
| vaadin-example | Batteries-included |
| wordpress-example | Pre-baked deps / multiple things bundled |
| zig-example | Reproducibility |
| zig-snake-example | Batteries-included / Standardize-to-Linux |

---

## Caveats / honesty notes

- **haskell-example is not effortless — and that's the point.** GHCup markets a one-line install,
  and on a normal desktop with an interactive terminal it *is* easy. But a **reproducible,
  non-interactive, minimal-image** install is a different beast: in this example `ghcup` bootstrapped
  only itself (not GHC or Cabal), and a wrapper shim hit infinite recursion. The Boothfile therefore
  carries explicit repair blocks (`ghcup install/set ghc/cabal recommended`, a rewritten `hswrap`).
  So the honest framing is: **the pain is real for the reproducible/headless case; CodingBooth
  absorbs it once so the next person just runs `booth`.** Claims of "it just works" describe the
  interactive happy path on an already-provisioned machine — not the same task.
- **jetbrain-exmple** has a typo in its directory name (`exmple`) and no per-component README table
  beyond its title.
