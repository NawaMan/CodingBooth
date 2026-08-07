# CodingBooth Examples

> Grab a ready-to-run workspace, start it with one command, then take it apart to build your own.

CodingBooth ships a catalog of **example workspaces** — complete, runnable projects, each with its
environment already declared in a `.booth/` folder. They are the fastest way to see CodingBooth
working, and the easiest way to learn how a booth is configured: the whole environment is usually a
handful of lines you can read in one sitting.

Back to [README](README.md)

---

## Table of Contents

- [Getting Started](#getting-started)
- [Finding What's Available](#finding-whats-available)
- [The Catalog](#the-catalog)
- [Three That Show the Range](#three-that-show-the-range)
- [Version Pinning in Examples](#version-pinning-in-examples)
- [Known Imperfections](#known-imperfections)
- [Where to Go Next](#where-to-go-next)

---

## Getting Started

### 1. Install CodingBooth

You need **Docker**, **Bash** or **Zsh**, and **curl**. Linux, macOS, and Windows are all supported,
on x86-64 and ARM64.

```bash
curl -fsSL https://codingbooth.io/install.sh | bash
```

That drops a `booth` wrapper script in the current directory, downloads the matching binary, and
wires up your shell so `booth` works from anywhere inside the project.

Because the installer touches your shell configuration, `booth` will not be on the `PATH` of
terminals you already have open. Open a new one, or reload your profile:

```bash
source ~/.bashrc      # bash
source ~/.zshrc       # zsh
```

For the full install/uninstall reference — shell function, wrapper, binary, `.booth/`, lock file,
and shared cache — see **[booth install](docs/BOOTH_INSTALL.md)**.

### 2. Take an example and run it

Three commands, start to finish:

```bash
booth example list                   # see what's available
booth example try <name> <folder>    # copy one into <folder>
cd <folder>
booth                                # start it
```

That bare `booth` at the end is the whole ceremony. It reads the project's `.booth/` folder, builds
or fetches the right image, and brings the environment up. Unless the example runs in command mode,
open **http://localhost:10000** in your browser to reach the UI.

A concrete run:

```bash
booth example try python ./my-python-project
cd ./my-python-project
booth
```

Examples are packaged as zip archives alongside each CodingBooth release, so the one you download
always matches the binary you are running. For the command's full flag reference, see
**[booth example](docs/BOOTH_EXAMPLE.md)**.

---

## Finding What's Available

**`booth example list` is the authoritative answer.** It fetches the list published with the exact
version you have installed:

```bash
booth example list
```

The catalog grows between releases, so treat the list in this document as a *snapshot* — accurate
for the release it shipped with, and likely to have gained entries since. When the two disagree,
believe the command.

---

## The Catalog

Every entry below is available as `booth example try <name> <folder>`. The grouping is editorial,
for readability — `booth example list` itself prints a flat alphabetical list.

### Languages & runtimes

`all-java` · `bun` · `clang` · `csharp` · `deno` · `elixir` · `fsharp` · `go` · `haskell` · `java` ·
`js` · `kotlin` · `nodejs` · `octave` · `php` · `python` · `rlang` · `ruby` · `rust` · `zig` ·
`zig-snake`

### Mobile

`android`

### Web frameworks & full stacks

`angular` · `django` · `fastapi` · `flask` · `lamp` · `lemp` · `mean` · `mern` · `nextjs` · `pern` ·
`pocketbase` · `rails` · `react` · `spring-boot` · `vaadin` · `wordpress`

### Data & notebooks

`conda` · `data`

### Containers & Kubernetes

`dind` · `kind` · `kind-app`

### Cloud & services

`aws` · `firebase` · `gcloud` · `server`

### Dependencies, caching & system packages

`apt` · `cache` · `homebrew` · `mvn-deps` · `npm` · `npm-deps` · `pip` · `pip-deps` · `systemlib`

### Testing & browsers

`browser-shared` · `playwright` · `playwright-polyglot`

### Editors & AI tooling

`claude` · `herdr` · `neovim`

### Security & network isolation

`egress-allowlist-extra` · `egress-envoy`

### Starting points

`demo` · `empty`

`empty` is the bare minimum — just the wrapper and a blank config, a good base for your own project.
`demo` is the opposite: a full showcase with notebooks and a sample app.

> For what each one is actually *demonstrating* — grouped by the problem it solves rather than by
> technology — see **[What Each Example Demonstrates](docs/EXAMPLES_ADVANTAGES.md)**.

---

## Three That Show the Range

These three are deliberately far apart: a single language runtime, a full graphical workbench, and
an entire Kubernetes cluster. All three start the same way.

### `elixir` — getting a version pairing right

A minimal Elixir program with a palindrome checker. It is small, but it earns its place: Elixir runs
on the Erlang BEAM VM, and every Elixir release only supports a specific window of OTP versions.
Pair them wrong by hand and you get cryptic BEAM load errors or a build that refuses to compile — a
classic first-day time sink.

```bash
booth example try elixir ./my-elixir
cd ./my-elixir && booth
```

The booth brings Elixir with a known-compatible Erlang/OTP already paired. Pin a different Elixir
with the `ELIXIR_VERSION` build arg and you get a matching OTP along with it.

### `data` — a whole workbench, with GUIs

A single booth that stands up an entire graphical data-analysis stack. It seeds a Postgres `demo`
database with a small `sales` table, then exposes that one dataset through four lenses at once:

- **DBeaver** — a real graphical SQL client, pre-wired to the database
- **JupyterLab** — a notebook that charts it with matplotlib
- **Sales Explorer** — a small Node/Express dashboard with Chart.js filters
- **PostgreSQL** — the database itself

```bash
booth example try data ./my-data
cd ./my-data && booth
```

It opens as an XFCE desktop in your browser, with DBeaver already on it. Postgres, DBeaver, Python,
and Node never touch your host — and the whole workbench goes away when you stop the booth.

### `kind` — a Kubernetes cluster you can be careless with

At the heavy end: a full Kubernetes cluster running inside the booth, via
[KinD](https://kind.sigs.k8s.io/) on Docker-in-Docker. Control plane, nodes, and pods are all nested
inside the container.

```bash
booth example try kind ./my-kind
cd ./my-kind && booth
# then, inside the booth:
./start-cluster.sh
./deploy-app.sh
```

The sample nginx app lands on NodePort 30080, reachable from your host browser. You never installed
kind, kubectl, or a container runtime on your own machine — so deleting the cluster means stopping
the booth. No lingering `~/.kube` config, no orphaned Docker networks, no wondering later why your
laptop is running eight etcd pods.

---

## Version Pinning in Examples

The examples exist to be taken apart. Once one is running, open its `.booth/` folder and read it —
that is the entire environment. The line you will most often want to change is a version.

A booth pins versions through the `setup` and `install` directives in its Boothfile, usually fed by
a build arg so the example can be re-pinned without editing the recipe:

```
arg  GO_VERSION=1.25.7
setup go ${GO_VERSION}
install go golang.org/x/tools/gopls@latest
```

How much that buys you differs per tool, and it is worth knowing which tier you are in before you
rely on a pin. What follows is a survey of every setup script in `variants/base/setups/`, accurate
as of **v0.66.0**. For the reproducibility model these tiers feed into — and why an image digest,
not a Boothfile, is the only true lock — see **[Reproducibility](docs/REPRODUCIBILITY.md)**.

### Tier 1 — Exact pin

The version string selects the exact artifact, almost always a versioned release download. This is
the strongest guarantee a setup script offers on its own.

**Positional argument** (`setup go 1.25.7`):

`bun` · `claude-code` · `codex` · `dbeaver` · `deno` · `bluej` · `freeplane` · `gemini-cli` ·
`go` · `gradle` · `greenfoot` · `jdk` · `jetbrains` · `julia` · `mermaid` · `mvn` · `neovim` ·
`obsidian` · `plantuml` · `python`

**`--version` flag** (`setup elixir --version 1.19.5`):

`act` · `aider` · `ansible` · `aws-cdk` · `aws-cli` · `aws-sam-cli` · `buf` · `clojure` · `cmake` ·
`crystal` · `cypress` · `direnv` · `dive` · `duckdb` · `elixir` · `elm` · `exercism` · `fzf` ·
`goose` · `grok` · `helm` · `herdr` · `just` · `k3d` · `k9s` · `kafka` · `kind` · `kotlin` ·
`kubectl` · `kustomize` · `lazydocker` · `lazygit` · `make` (source-build mode) · `mkcert` · `nim` ·
`oh-my-pi` · `ollama` · `opencode` · `playwright` · `pulumi` · `puppeteer` · `rescript` · `roc` ·
`sbt` · `scala` · `stern` · `swift` · `terraform` · `vhs` · `zig`

Some take more than one knob: `haskell` (`--ghc-version`, `--cabal-version`), `dotnet`
(`--sdk-version` for an exact SDK), `kind` (`--kind-version`, `--kubectl-version`).

**apt exact-pin** — `azure-cli`, `gcloud`, `redis`, `rabbitmq`, `fpc`. These do install the exact
version you name (`pkg=version`), but the pin is *ephemeral*: Ubuntu and vendor mirrors garbage-collect
superseded versions, so a pin that works today can fail to resolve months later. `fpc` additionally
falls back to an unpinned install if the pinned one is unavailable.

### Tier 2 — Series-level pin

The knob narrows the install to a series; the exact build still floats to whatever is newest in that
series at build time.

| Setup | What the version means |
|---|---|
| `nodejs` | The **major**; resolves to that major's newest release at build time |
| `ruby` | Major.minor; rbenv picks the newest patch |
| `erlang` | Truncated to the major (only OTP 25, 26, 27 accepted) |
| `gcc`, `clang`, `php`, `postgresql`, `lua` | Becomes a package *name* — `gcc-14`, `clang-18`, `php8.3-*`, `postgresql-16` |
| `mongodb` | Picks the repo series, then installs `mongodb-org` unpinned |
| `conda` | The Python X.Y for the environment |
| `dotnet --channel` | A release channel, not a build |
| `selenium --chrome-version` | A Chrome channel name (`Stable`, …) |

Also note the defaults that are *channels* rather than versions — leave them alone and you are not
pinned at all: `rust` → `stable`, `haskell` → `recommended`, `roc` → `alpha4-rolling`, and
`bun` / `deno` / `dbeaver` / `claude-code` / `gh` → `latest`.

### Tier 3 — No version knob

These install whatever is current when the image is built. Pinning them means pinning the *image*
(build once, reuse by digest) rather than the recipe.

- **Editors & apps** — `vscode`, `codeserver`, `notebook`, `nbgrader`, `conan`, `firebase`,
  `gh-copilot`, `antigravity`, `cursor`, `warp`, `remotion`, `scratch`, `excalidraw`, `cloudbeaver`
  (its version comes from the `COPY --from=dbeaver/cloudbeaver:<tag>` in the Dockerfile, not the
  setup)
- **Browsers** — `firefox`, `chromium-browser`, `google-chrome`
- **Services** — `mysql`, `sqlite`, `nginx`, `apache`, `openssh` / `opensshd`
- **Desktop & GUI** — `kde`, `lxqt`, `xfce`, `wayland`, `gimp`, `inkscape`, `libreoffice`,
  `drracket`, `thonny`, `octave`, `r-rscript`
- **Container tooling** — `dind`, `docker-compose`, `docker-buildx`, `homebrew`, `kubectx`
- **All 41 `*-code-extension--setup.sh`** — VS Code extensions install at marketplace latest; no
  `@version` anywhere in them
- **14 of 17 `*-nb-kernel--setup.sh`** — for example `ipykernel>=6` and
  `cargo install --locked evcxr_jupyter`

Three near-misses worth knowing:

- **`eclipse`** *is* pinnable, but only through the `REL` environment variable (default `2026-03`) —
  not an argument, and not reachable from a template.
- **`cursor`** has no version to pin: Cursor's download URLs embed a build commit, not a plain
  version, so there is no URL to construct from `3.13.25` alone. `CURSOR_TRACK` picks the release
  track (`stable` or `latest`) instead, and `setup cursor --deb-url <url>` installs one exact build
  if you resolve it yourself.
- Three notebook kernels pin via environment variable rather than argument: `java-ijava` /
  `java-nb-kernel` (`IJAVA_VERSION`), `java-jjava` (`JJAVA_VERSION`), and `scala-nb-kernel`
  (`ALMOND_VERSION`, `SCALA_VERSION`).

### Package installs — all pin

Every one of the 20 `install <manager> …` targets passes a version through in the manager's native
syntax, so `install pip requests==2.32.3` and friends work as written:

`apt` (`pkg=ver`, plus `APT_SNAPSHOT` to freeze the whole archive) · `pip` / `uv` (`==`) ·
`npm` / `yarn` / `bun` (`@`) · `go` (`pkg@ver`) · `cargo` · `hex` · `luarocks` (all `name@ver`) ·
`dotnet` tools (`tool@ver`) · `gem` · `deno` / `deno-pkg` · `conda` · `cabal` · `pecl` · `brew` ·
`code-extension` (`publisher.name@version`)

`apt` is the one to reach for when you want more than a top-level pin: a version pin fixes only the
package you named, while `APT_SNAPSHOT` freezes the entire archive index to a timestamp, so
unnamed transitive dependencies stay identical across rebuilds too. The `apt` example demonstrates
exactly this.

### Reaching the knob from `booth config`

A setup's version argument is only useful if a template passes something to it. Every setup that
accepts one now does — `booth config --select terraform:1.9.8` reaches
`setup terraform --version 1.9.8` — with four deliberate exceptions:

- **`firebase`** takes `--node-version`, which picks the Node used to *run* `firebase-tools`, not a
  Firebase version. Exposing it as "the Firebase version" would be a lie.
- **`lxqt`, `wayland`, `xfce`** take a positional Python version that they forward straight to
  `python--setup.sh`. It is the Python template's knob, already exposed there; a second copy on a
  desktop template would be two controls for one value.
- **`dotnet`** exposes `DOTNET_CHANNEL` (a series) but not `--sdk-version` (an exact SDK). The script
  takes one or the other, and a parameter list has no way to say "either/or" — passing both with one
  left blank breaks the argument parser.
- **`conda`'s Python version** is exposed on `tools/conda` but not on the
  `languages/python` conda extension, where the name would collide with the python template's own
  `PYTHON_VERSION`.

### Does leaving it blank get you the latest?

The intent is that not naming a version means "give me the current release". That holds for most
setups but **not all**, and the exceptions are worth knowing before you rely on the default.

**Yes — resolved fresh at build time (~55 setups).** Anything whose default is `latest` asks the
upstream release API or package repo at build time: `act`, `aws-cli`, `azure-cli`, `cmake`,
`elixir`, `exercism`, `gcloud`, `gh`, `helm`, `k9s`, `kotlin`, `kubectl`, `lazygit`, `mongodb`,
`ollama`, `postgresql`, `pulumi`, `redis`, `rescript`, `sbt`, `terraform`, and the rest of the
GitHub-release family.

**Yes, within a channel.** `rust` → `stable`, `neovim` → `stable`, `haskell` → `recommended`,
`selenium` → `Stable`, `cursor` → the `stable` track, `make` → the distro package, `roc` →
`alpha4-rolling`. Each tracks its channel's newest.

**No — these carry a hardcoded version that ages until someone bumps it:**

`bluej` · `elm` · `freeplane` · `go` · `gradle` · `greenfoot` · `julia` · `kind` · `mermaid` ·
`mvn` · `obsidian` · `plantuml` · `python` · `scala` · `swift` · `zig`, plus `jetbrains`
(2025.2.3) and `eclipse` (`REL=2026-03`).

And these default to a hardcoded *series*, then take the newest build inside it: `clang` (18),
`conda` (3.12), `dotnet` (9.0), `erlang` (27), `gcc` (13), `jdk` (21), `lua` (5.4), `nodejs` (20),
`php` (8.3), `ruby` (3.3).

Two things soften this in practice. First, most people arrive through `booth config`, and a
template's `default` — not the script's — is what lands in the Boothfile; several templates are
kept fresher than the script they call (`go` template 1.25.7 vs script 1.25.3, `jdk` 25 vs 21,
`nodejs` 22 vs 20). Second, a hardcoded default is at least *stable*: two people running the same
Boothfile a year apart get the same toolchain, which is the whole point of a booth.

But it does rot, and the honest reading is that "latest by default" is a goal the catalog
approaches rather than reaches. What is left, and why, is spelled out below.

---

## Known Imperfections

Everything in this section is a real limitation, kept here rather than smoothed over. None of it
blocks normal use; all of it is worth knowing before you depend on a default.

### `latest` and reproducibility pull in opposite directions

A default of `latest` means the same Boothfile builds a different toolchain next month. A hardcoded
default means it does not, but goes stale and eventually 404s. There is no setting that gives you
both — **the only real lock is the built image**, reused by digest. See
[Reproducibility](docs/REPRODUCIBILITY.md). Treat a `latest` default as "I have not decided yet",
and pin explicitly the moment the version matters.

### Defaults that still do not track

- **Cannot resolve `latest` at all** — no upstream endpoint is wired up: `bluej`, `elm`,
  `freeplane`, `go`, `gradle`, `greenfoot`, `julia`, `kind`, `mermaid`, `mvn`, `obsidian`,
  `plantuml`, `python`, `scala`, `swift`, `zig`, `jetbrains`, `eclipse`. Naming a version works
  fine; only the *default* is frozen.
- **`elm` deliberately stays pinned.** It resolves `latest` through npm's dist-tag, and elm's
  `latest` currently points at `0.19.2-0` — a *prerelease*. Tracking it would silently move users
  onto an unreleased compiler, so `0.19.1` stands.
- **`scala` deliberately stays pinned.** Its releases come from the `lampepfl/dotty` repo, whose
  GitHub "latest release" is the LTS line (`3.3.8`) rather than the newest (`3.5.x`). Wiring
  `latest` up would *downgrade* the default, so it is not wired up.
- **Series defaults are a judgement call, not an oversight.** `jdk` 21 over 25, `nodejs` 20 over
  22, `php` 8.3 — these track the newest build *within* a deliberately chosen series, because
  jumping a major is the kind of thing that should be opt-in.

### The default lives in two places

A setup's default and its template's default are separate values, and they drift: `go` is 1.25.3 in
the script and 1.25.7 in the template; `jdk` is 21 versus 25; `nodejs` 20 versus 22. Which one you
get depends on whether you ran `booth config` or hand-wrote `setup go`. Nothing keeps them in sync,
and there is no guard that would notice.

### `latest` puts the network on the build path

Setups that resolve `latest` call an upstream API at build time. Unauthenticated GitHub API calls
are rate-limited to 60/hour per IP, so a busy CI host can fail to resolve. `elixir`, `exercism` and
`kotlin` fall back to their pinned constant with a warning rather than failing the build; **most of
the other ~50 `latest` setups do not** — they will fail the build instead. That is pre-existing
behaviour, not something this catalog introduced, but it is a real failure mode.

### apt pins are ephemeral

`azure-cli`, `gcloud`, `redis`, `rabbitmq` and `fpc` pin with `pkg=version`, which is exact *today*.
Ubuntu and vendor mirrors garbage-collect superseded versions, so a pin that builds now can stop
resolving in a few months. `APT_SNAPSHOT` is the durable answer; a bare version pin is not.
`fpc` additionally falls back to an unpinned install when the pinned one is unavailable — quiet, and
easy to miss.

### Two families have no pinning at all

All 41 `*-code-extension--setup.sh` install VS Code extensions at marketplace latest, with no
`@version` anywhere. 14 of the 17 `*-nb-kernel--setup.sh` are similarly unpinned. Both are
reachable through `booth config` but neither offers a version knob, so a booth's editor tooling and
notebook kernels drift even when its language toolchain does not.

### Four knobs stay unexposed on purpose

`firebase`, the desktop templates, `dotnet --sdk-version`, and the conda extension — each for a
reason given in [Reaching the knob from `booth config`](#reaching-the-knob-from-booth-config)
above. They are choices, not gaps, but they are still knobs you cannot turn from the TUI.

### `mvn`'s default has already rotted

`mvn`'s hardcoded 3.9.11 is gone from Apache's primary CDN. The setup still works only because it
falls back to `archive.apache.org`. It is the clearest evidence that a frozen default is a
maintenance debt with a due date — and nothing currently warns when one comes due.

---

## Where to Go Next

Once an example is running, open its `.booth/` folder and read it. Change a version, add a `setup`,
run `booth` again — and you have configured your own project the same way the example was
configured. That is really the argument: not that these particular workspaces are useful to you, but
that *your* project could start the same way — one folder in the repo, one command, and everyone who
clones it gets the environment you meant them to have.

- **[booth example](docs/BOOTH_EXAMPLE.md)** — the command's full flag reference
- **[What Each Example Demonstrates](docs/EXAMPLES_ADVANTAGES.md)** — every workspace, grouped by the
  problem it solves
- **[Booth Setup Guide](docs/BOOTH_SETUP.md)** — how setup scripts are written, and how to add your own
- **[Booth Customization](docs/BOOTH_CUSTOMIZATION.md)** — setup scripts, install scripts, templates, recipes
- **[Reproducibility](docs/REPRODUCIBILITY.md)** — what a pin does and does not guarantee
- **[booth config](docs/BOOTH_CONFIG.md)** — template-driven scaffolding, the other way to start a project
