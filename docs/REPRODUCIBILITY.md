# Reproducibility

> How repeatable is a CodingBooth environment — and how to make it byte-for-byte reproducible when you need it.

CodingBooth makes it easy to describe an environment in a `Boothfile` and rebuild it anywhere. But "rebuilds from the same Boothfile" and "produces the same bytes" are **two different guarantees**, and it is important to be honest about which one you are getting.

This document explains the difference, why rebuilds can drift, and the three tiers of reproducibility you can choose from — ending with the one approach that is *guaranteed*: build the image once and reuse the stored image.

Back to [README](../README.md)

---

## Table of Contents

- [TL;DR](#tldr)
- [Two Kinds of "Reproducible"](#two-kinds-of-reproducible)
- [Why Rebuilds Drift](#why-rebuilds-drift)
- [The Three Tiers](#the-three-tiers)
- [Tier 1 — Pin Versions (Convenience)](#tier-1--pin-versions-convenience)
- [Tier 2 — Freeze the Resolution (Better)](#tier-2--freeze-the-resolution-better)
- [Tier 3 — Store the Image (Guaranteed)](#tier-3--store-the-image-guaranteed)
- [Choosing a Tier](#choosing-a-tier)
- [FAQ](#faq)

---

## TL;DR

- A `Boothfile` is a **recipe**. A built image is the **guarantee**.
- The same `Boothfile` always produces the same **tag** (instruction-level repeatability) — but **not necessarily the same bytes** on a later rebuild.
- For **guaranteed, byte-for-byte reproducibility**, run [`booth build`](BOOTH_BUILD.md) **once**, store the resulting image (by tag or digest), and reuse *that image* — do not rebuild.
- Pinning versions (`install pip django==5.0.1`) helps, but only freezes the *top-level* package, not its dependency tree.

---

## Two Kinds of "Reproducible"

| | What it means | What guarantees it |
|---|---|---|
| **Instruction-level repeatability** | The same inputs produce the same *build recipe* (same tag, cache hits). | The content-hash tag — same `Boothfile` + build args + variant + version → same tag. |
| **Artifact-level reproducibility** | A rebuild produces the *same bytes* — every package, every transitive dependency, identical. | Only a **stored image**. |

CodingBooth's content-based tagging (see [Content-Based Tagging](BOOTH_BUILD.md#content-based-tagging)) gives you the first one. It is excellent for caching and for skip-if-exists, and it means two machines with identical `.booth/` directories compute the same tag. But a matching tag does **not** prove the bytes underneath are identical — because the *recipe* can resolve to different bytes at different times.

---

## Why Rebuilds Drift

Even with a fixed `Boothfile`, three things can change between builds:

### 1. Transitive dependencies float

Pinning a package version pins only what *you* named. `django==5.0.1` has an immutable manifest, but that manifest declares its own dependencies as **ranges**, e.g. `asgiref>=3.8,<4.0`. The resolver fills that range with the *newest matching version at build time*:

- Build today → `asgiref 3.8.1`
- A compatible `asgiref 3.8.2` is published next month
- Rebuild later → `asgiref 3.8.2`

Same `django==5.0.1`, different tree. Nothing about Django changed — a new, compatible dependency appeared and the resolver took it.

### 2. apt packages move

Ubuntu/Debian mirrors keep only the **current** version of each package in their index and garbage-collect old ones. So:

- `apt-get install qrencode=4.1.1-1build2` works today.
- After Ubuntu publishes `4.1.1-1build3` (e.g. a security rebuild), that exact pin **fails the build** — the old version is gone from the mirror.

So apt version pins are *ephemeral*, and any un-pinned apt package simply tracks "latest at build time." (See [Tier 2](#tier-2--freeze-the-resolution-better) for the fix.)

### 3. The base image moves

`FROM ubuntu:24.04` is a moving tag — it points at the latest 24.04 build, which changes as patches land. Only a digest (`ubuntu:24.04@sha256:…`) is fixed.

None of this is unique to CodingBooth — it is how package ecosystems and Docker work. The point is to know which leaks apply to you and how to close them.

---

## The Three Tiers

| Tier | What you do | What you get |
|---|---|---|
| **1 — Convenience** | Pin top-level versions: `install pip django==5.0.1` | Top-level pinned; transitive tree floats; rebuilds *approximately* reproducible. Great for dev tools. |
| **2 — Better** | Add an apt snapshot, use lock-aware installers (`go`, `cargo --locked`), pin the base image digest, install app deps from your project's lockfile. | Rebuilds *closely* reproducible. |
| **3 — Guaranteed** | [`booth build`](BOOTH_BUILD.md) once → store the image → reuse it by digest. | **Byte-for-byte identical, forever.** |

Most users want Tier 1 for the tools they install into the booth, and Tier 3 for anything that truly must not change (CI base images, audited environments, long-lived deployments). Tier 2 is for when you want rebuilds to be close without committing to storing an image.

---

## Tier 1 — Pin Versions (Convenience)

Add an explicit version to any `install` line. The syntax is the package manager's native one — CodingBooth passes it straight through:

| Manager(s) | Pin syntax | Example |
|---|---|---|
| `pip`, `uv` | `==` | `install pip django==5.0.1` |
| `npm`, `yarn`, `bun` | `@` | `install npm typescript@5.4.5` |
| `go` | `@` (required) | `install go golang.org/x/tools/gopls@v0.16.1` |
| `conda` | `=` | `install conda numpy=1.26.4` |
| `conan` | `/` | `install conan boost/1.83.0` |
| `gem` | `:` | `install gem rails:7.1.3` |
| `cabal` | `-` | `install cabal hlint-3.8` |
| `pecl` | `-` | `install pecl redis-6.0.2` |
| `deno`, `deno-pkg` | `@` | `install deno-pkg npm:cowsay@1.6.0` |
| `cargo`, `hex`, `luarocks` | `@` | `install cargo ripgrep@14.1.0` |
| `brew` | `@` (versioned formulae only) | `install brew node@20` |
| `apt` | `=` | `install apt htop=3.0.5-7` |

Notes:

- **`cargo`, `hex`, and `luarocks`** use a CodingBooth-normalized `name@version` form, translated to each tool's native flag/argument under the hood. A token with no `@` installs the latest version, exactly as before.
- **`brew`** can only pin to versioned formulae that Homebrew ships (`node@20`, `postgresql@15`); arbitrary version pinning is not supported by Homebrew.
- Language registries (PyPI, npm, crates.io, the Go proxy, Hackage, hex.pm, RubyGems) are **immutable** — a pinned version stays installable indefinitely, so no snapshot is needed. (`conda`, `luarocks`, and `pecl` have weaker delete guarantees.)
- **`apt` is the exception:** the live archive keeps only the *current* version in its pool, so an `apt` pin like `htop=3.0.5-7` stops resolving once a newer build lands. A bare `=` pin is therefore convenience/documentation only — to make `apt` actually reproducible, combine it with an `APT_SNAPSHOT` (Tier 2 below), which `booth config` sets for you.

**What Tier 1 does and does not give you:** it freezes the *top-level* package. The transitive tree still floats (see [Why Rebuilds Drift](#why-rebuilds-drift)). For installing **dev tools** (`gopls`, `ripgrep`, `black`, `typescript`) this is usually all you need — you care about the tool's version, not its dependency tree. For **application libraries** your code imports, use your project's lockfile instead of listing them here.

---

## Tier 2 — Freeze the Resolution (Better)

When you want rebuilds to stay close without storing an image, freeze the *resolution*, not just the request.

### apt — pin the snapshot, not the package

The reliable way to make apt reproducible is to freeze the entire archive at a point in time using Ubuntu's snapshot service, then every apt operation resolves against that frozen index — top-level packages, transitive dependencies, and even packages you never pinned.

**Built in: `install apt` + `APT_SNAPSHOT`.** The `install apt` manager reads an `APT_SNAPSHOT` environment variable. When it is set (a UTC snapshot id like `20260601T000000Z`), the script passes `--snapshot` to apt so the install resolves against that frozen archive; when it is unset, apt resolves against the live archive. `booth config` stamps the **configuration date** into the generated Boothfile so you don't have to:

```
# .booth/Boothfile (generated by `booth config`)
env APT_SNAPSHOT=20260601T000000Z

install apt qrencode imagemagick
```

The base image is Ubuntu 24.04, where `--snapshot` is auto-supported (no apt config needed). The date is captured once at config time and baked in literally — it is **not** recomputed on each build, so rebuilds stay frozen until you re-run `booth config`. To pin a specific snapshot instead of "today", set `CB_APT_SNAPSHOT=<id>` when running `booth config`, or edit the `env APT_SNAPSHOT=` line directly.

- **Pin the date, not each package.** With a frozen index, `install apt qrencode imagemagick` (no version pins) is already deterministic. Explicit `pkg=version` pins then act only as documentation and as a tripwire that fails loudly if a snapshot bump changes the version.
- **Trade-off:** a frozen snapshot stops receiving security updates until you bump the date — which is the correct behaviour, since updates become a deliberate, reviewable change rather than silent drift.

**Global alternative: freeze the whole build.** `APT_SNAPSHOT` only covers `install apt` lines. To freeze *every* apt operation in a custom setup script too, point the apt sources at the snapshot once at build time. On Ubuntu 24.04 (deb822 format) this rewrites `/etc/apt/sources.list.d/ubuntu.sources`:

```bash
# In a custom setup script, run at build time as root.
# Pick a recent timestamp once, then reuse it verbatim on every rebuild.
SNAPSHOT="20260601T030000Z"
sed -i -E \
  "s|https?://(archive\|security)\.ubuntu\.com/ubuntu|https://snapshot.ubuntu.com/ubuntu/${SNAPSHOT}|g" \
  /etc/apt/sources.list.d/ubuntu.sources
```

- **Ubuntu needs no expiry override.** Ubuntu archive `Release` files carry no `Valid-Until` field, so snapshot pins do not need `Acquire::Check-Valid-Until=false` (that is a Debian-only requirement).

### Lock the whole tree — commit a lockfile

Tier 1 freezes only the top-level request; the transitive tree still floats. To freeze the *whole resolved tree*, let the booth resolve the packages once, **export the resolution into a lockfile, commit it to your repo, and on every rebuild install *from the lockfile*** through the ecosystem's deterministic installer (`npm ci`, `pip install -r … --require-hashes`, `cargo … --locked`) — instead of from loose `install pkg@version` lines.

Whether that scheme actually buys you reproducibility depends on the manager. They fall into three groups.

#### Group A — the lockfile scheme works

These have a faithful lockfile *and* a deterministic replay, backed by an immutable registry. Commit the lock and the tree is frozen — no change of tooling required. (`go` is the one that needs no extra step at all; the rest need an explicit freeze + a replay flag.)

| Manager | Freeze | Replay |
|---|---|---|
| `pip` | `pip freeze` / pip-tools `--generate-hashes` | `pip install -r … --require-hashes` |
| `uv` | `uv lock` | `uv sync` / `uv pip sync` |
| `npm` | `package-lock.json` (auto) | `npm ci` |
| `yarn` | `yarn.lock` (auto) | `yarn install --immutable` |
| `bun` | `bun.lock` (auto) | `bun install --frozen-lockfile` |
| `go` | `go.mod` + `go.sum` (auto) | deterministic by design — nothing to add |
| `cargo` | `Cargo.lock` (auto) | `cargo … --locked` |
| `deno`, `deno-pkg` | `deno.lock` (auto) | `deno … --frozen` |
| `conda` | `conda list --explicit` | `conda create --file …` (same platform; cross-platform → conda-lock) |
| `cabal` | `cabal freeze` + `--index-state` | freeze file honored |

`cargo` is the one case where you can request whole-tree locking straight from a CodingBooth `install` line: any leading-dash flag is passed through to `cargo install`, so `install cargo --locked ripgrep@14.1.0` builds against the crate's published `Cargo.lock`. It is opt-in because a crate that ships no `Cargo.lock` (or a stale one) makes `--locked` fail the build.

#### Group B — works, but only by switching tools (not transparent)

These ecosystems have a strong lockfile — but **not on the command the `install` line runs**, so CodingBooth cannot turn it on for you. `install gem` and `install hex` produce **global tools** (a `rails` binary, a `mix phx.new` task); the lockfile (`Gemfile.lock`, `mix.lock`) locks **project libraries** — a *different deliverable*. Engaging it means authoring a manifest and consuming dependencies from it, which is a workflow change, not a flag.

| Manager | Lock lives in | `install` runs | Reproducible only if you… |
|---|---|---|---|
| `gem` | Bundler `Gemfile.lock` | `gem install` (global gem) | adopt a `Gemfile` + `bundle install` |
| `hex` | Mix `mix.lock` | `mix archive.install` (global archive) | adopt a Mix project + `mix deps.get` |
| `conan` | `conan.lock` (revision-pinned) | `conan download` (cache prefetch) | drive a `conanfile` + `conan install --lockfile` |

#### Group C — a committed lockfile cannot help

| Manager | Why |
|---|---|
| `luarocks` | No robust lockfile and no deterministic replay; rocks can be replaced. |
| `brew` | Homebrew is rolling-release — a `Brewfile.lock.json` records state it cannot reinstall later (old bottles are garbage-collected, formulae move). |
| `pecl` | No package tree — extensions compile against the system PHP and libraries. Reproducibility here is the apt snapshot + base image, not a PECL lock. |

> **Reproducible, to a degree — not perfectly.** Even Group A is only as solid as the things outside your control. A committed lockfile reproduces the tree *as long as* the registry still serves the exact artifacts you locked and the maintainer has not re-published or yanked a version under you. A hash-locked lockfile (`--require-hashes`, `npm ci`, `go.sum`) turns that into a loud tripwire — a swapped artifact fails the build instead of silently installing something different — but it still cannot *recreate* a version that was deleted, and it does not freeze packages that build from source (native extensions compile against whatever toolchain and system libraries happen to be present). So a committed lockfile gives you *strong, honest* reproducibility that holds when maintainers do their job — not a perfect one. When byte-for-byte reproducibility is a hard requirement, do not rely on re-resolving from a lockfile at all: [build the image once and reuse it](#tier-3--store-the-image-guaranteed) (Tier 3) is the only thing that freezes every byte regardless of what any registry or maintainer does later.

> **Global tools vs. project libraries.** These `install` lines install *global* tools into the booth, but lockfiles are *project*-shaped. The commit-a-lockfile scheme is a clean fit when what you are locking is your project's own library dependencies — which is why those belong in your project's lockfile, installed via the deterministic installer above, rather than enumerated as `install` lines. For genuinely global CLI tools (`gopls`, `ripgrep`, `black`) only some managers model "lock the global set" cleanly.

### Pin the base image digest

Pin the CodingBooth/base image by digest rather than a floating tag so the starting point does not move underneath you.

Tier 2 gets you close, but it is still a *rebuild* — and a rebuild is only ever as reproducible as the weakest unpinned link in it. For a hard guarantee, use Tier 3.

---

## Tier 3 — Store the Image (Guaranteed)

The only thing that freezes **every byte** — base image, every apt package, every transitive dependency, every layer — is a **built image**. A Docker image is content-addressable by digest (`@sha256:…`); once built and stored, it cannot drift because nothing is re-resolved.

This is the recommended path whenever reproducibility genuinely matters.

```bash
# Build once and push to a registry.
docker login ghcr.io
./booth build --push ghcr.io/myteam --name my-env --tag v1.0
# ✅ Pushed: ghcr.io/myteam/my-env:v1.0

# Capture the immutable digest.
docker buildx imagetools inspect ghcr.io/myteam/my-env:v1.0 --format '{{.Manifest.Digest}}'
# sha256:1a2b3c…

# Everyone — teammates, CI, production — reuses that exact image instead of rebuilding.
./booth run --image ghcr.io/myteam/my-env@sha256:1a2b3c…
```

- **Reuse, don't rebuild.** The whole point is that the stored image *is* the lock. Rebuilding from the `Boothfile` re-opens every drift source in [Why Rebuilds Drift](#why-rebuilds-drift); reusing the stored image closes all of them.
- **Reference by digest** (`@sha256:…`), not just a tag — a tag can be re-pushed, a digest cannot.
- This is how CodingBooth turns a convenient recipe into a hard guarantee: [`booth build`](BOOTH_BUILD.md) → store → reuse.

---

## Choosing a Tier

| If you are… | Use |
|---|---|
| Installing dev tools into a booth | **Tier 1** — pin the tool versions, done. |
| Sharing an environment with a team and want rebuilds to stay close | **Tier 2** — snapshot apt, lock where possible, pin the base digest. |
| Running CI, deploying, or auditing — anything that must not change | **Tier 3** — [`booth build`](BOOTH_BUILD.md) once, store, reuse by digest. |

These compose: a Tier 3 image built from a Tier 1/Tier 2 `Boothfile` is both reproducible *and* documents exactly how it was made.

---

## FAQ

**The same Boothfile gives the same tag — isn't that reproducible?**
It is *instruction-level* repeatable (same recipe, same cache key). It is not *artifact-level* reproducible: the recipe can resolve to different bytes on a later rebuild. Only a stored image guarantees identical bytes.

**If I pin `pkg@version`, how can the tree change?**
The package's manifest is immutable, but it declares its dependencies as *ranges*. The resolver picks the newest version satisfying each range at build time, so the tree drifts as new compatible dependencies are published. A pin freezes the top; a lockfile freezes the resolution.

**Do language packages need an apt-style snapshot?**
No. PyPI, npm, crates.io, the Go proxy, Hackage, hex.pm, and RubyGems are immutable — old versions stay installable forever, so a version pin is durable on its own. apt is the exception because its mirror discards old versions, which is why it needs a snapshot.

**What's the single most reliable thing I can do?**
Build the image once with [`booth build`](BOOTH_BUILD.md), store it, and reuse it by digest. Everything else is an approximation of that.
