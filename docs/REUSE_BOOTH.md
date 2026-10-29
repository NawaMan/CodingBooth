# Reusing the Booth Catalog Outside a Booth

> Plan: use CodingBooth's setups to provision a **fresh Ubuntu machine** and a **GitHub Actions
> runner**, not only a booth image.

**Status:** planned, nothing built (2026-10-25). The preparation is done in stages, and each stage
soaks before the next one starts. That way, when we cross the line into actual host and GitHub
Actions (GHA) support, any breakage is in the new code, not in old code that changed at the same
time.

> [!CAUTION]
> **`variants/base/booth-entry` is essential. Touch it with extreme care.** It took a lot of work
> to reach its current state. User/ID alignment is sensitive to interrupts, and every booth on
> every variant starts through it.
>
> - **No moving code out of it, and no new code in it.** The only change allowed is wrapping an
>   existing block in an `if` on [`CB_TARGET`](#the-target-variable-cb_target), so the block is
>   skipped on a target where it does not apply. With `CB_TARGET` unset (`booth`), every block runs
>   exactly as today.
> - Anything beyond that is a **rare exception**. It needs its own explicit approval, and must be
>   the smallest change that keeps `booth` behaviour identical. The known candidates are listed
>   under [Open decisions](#open-decisions).
> - Make the change in a stage of its own (Stage 4). Never fold it into other work.
> - Gate: the complex lifecycle suite, run several times, then a long soak before anything builds
>   on top.

Related: [Understanding Setups](UNDERSTAND_SETUPS.md) · [Setup conventions](BOOTH_SETUP.md) ·
[Catalog versioning](CATALOG_VERSIONING.md) · TODO item *"sync the setup with GitHub action"*.

Back to [README](../README.md)

---

## Table of Contents

- [The two targets](#the-two-targets)
- [What carries over, and what does not](#what-carries-over-and-what-does-not)
- [Where it breaks](#where-it-breaks)
- [Preparation, by risk to today's booths](#preparation-by-risk-to-todays-booths)
- [The target variable, CB_TARGET](#the-target-variable-cb_target)
- [Parameterizing the user home](#parameterizing-the-user-home)
- [Why /opt/codingbooth stays fixed](#why-optcodingbooth-stays-fixed)
- [Stages](#stages)
- [Open decisions](#open-decisions)
- [Experiment results](#experiment-results)

---

## The two targets

**A. Run the booth inside CI. Needs no new code.** Runners already have Docker. A workflow step
installs the `booth` wrapper, builds the project's booth (layers cached with buildx and the GHA
cache), and runs the job's commands through `booth exec`. CI then gets exactly the dev environment.
The cost is the image build on each run.

- Do **not** use the job-level `container:` key. As far as we know, GitHub replaces the image's
  entrypoint, so `booth-entry` never runs: no user/ID alignment and no startup hooks.
- A fresh machine can use path A too: install Docker and `booth`, and it is done.

**B. A native target: compile the selection into a provisioning script.** This is a new command
next to `emit-dockerfile`, something like `booth emit-script --target host|gha`. It would output:

- `sudo …--setup.sh args` for each `setup` and `install` line;
- the template `env` lines, written to `/etc/profile.d/00-cb-host.sh` (host) or to
  `$GITHUB_ENV` / `$GITHUB_PATH` (GHA);
- one run of the `startup.d` hooks as the target user;
- a skip for every setup not classified as host-safe.

B gives a faster CI with no Docker and a truly provisioned machine. The catch is weaker parity: a
different user, possibly a different Ubuntu release, and no isolation.

**Direction:** A for GHA first. It is mostly a doc plus maybe a small composite action, and it
gives parity, which is usually the point. B is the real feature, aimed at a fresh Ubuntu machine,
and starts with a small host-safe set (language runtimes, CLIs), not the whole catalog.

## What carries over, and what does not

| Piece | Reusable? | Notes |
| --- | --- | --- |
| **Setup scripts** | mostly | Plain root bash on Ubuntu, with pinned downloads into `/usr/local/…` |
| **Install scripts** | yes | Thin wrappers over `apt`, `pip`, `npm`, `cargo`, … |
| **Templates** | through B only | Their only output is a Boothfile, which compiles to a Dockerfile only |
| **Variants**, `config.toml` | partly | Each setting needs its own answer; see [Where it breaks](#where-it-breaks), item 10 |

Each setup writes three files. How each one behaves outside a booth:

| Output | Fresh machine | GHA runner |
| --- | --- | --- |
| Profile: `/etc/profile.d/NN-cb-*--profile.sh` | ✅ login shells read it | ❌ each `run:` step uses `bash --noprofile --norc` |
| Starter: `/usr/local/bin/<tool>` | ✅ | ✅ |
| Startup: `/usr/share/startup.d/*` | ⚠️ nothing runs these; inside a booth, `booth-entry` step 14 does | ⚠️ same |

The runner gap already has a fix. Templates repeat every profile export as an `env` line, because
`booth exec` does not read profiles either, and `tests/config/catalog/test137` enforces this. Those
lines map directly onto `$GITHUB_ENV` and `$GITHUB_PATH`.

## Where it breaks

1. **The `coder` user is hard-coded.**
   - 12 setups write to `/home/coder`, and 11 run commands as `coder` (about 20 unique).
   - **12 of the 24 install scripts** run `sudo -u coder` (go, cargo, gem, bun, deno, deno-pkg,
     conda, dotnet, brew, cabal, conan, code-extension). The experiment found this; the earlier
     count looked only at setup scripts.
     Examples: claude-code, codeserver, flutter, homebrew, wails, mongodb, redis.
   - 28 templates (47 lines) use `/home/coder`, mostly in `env` lines.
2. **Ubuntu release.** Base is 26.04, and some setups were adjusted for it (PHP, Erlang). 27
   setups mention a codename or release number. **GHA is not affected:** `runs-on: ubuntu-26.04`
   (and `ubuntu-26.04-arm`) has been generally available since 2026-09-17. Pin that label
   explicitly. `ubuntu-latest` is moving from 24.04 to 26.04 gradually (2026-10-19 to 2026-11-19),
   and will move again at the next LTS.
   Same release does not mean same environment, though. The runner image ships many preinstalled
   tools (Java 25, Python 3.14, …) and its own PATH. Setups may collide with these, or the
   preinstalled copy may shadow the setup's tool, so the GHA smoke run (#5) has to check for it.
3. **Fixed paths.** Setups load helpers from `/opt/codingbooth/setups`, through `$SCRIPT_DIR` or
   `SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}`. Copying the directory to the
   same path on the host solves this.
4. **Templates only compile to a Dockerfile.** `setup`, `install`, `run` and `env` turn into shell
   commands easily. `copy`, `workdir` and `expose` do not.
5. **Services.** Inside a booth, services start from startup hooks because there is no systemd. A
   real machine would want systemd units instead.
6. **Container-only setups.** These make no sense on a host: desktops, `booth-*`, the Console UI,
   and add-ons guarded by `cb-has-*`. `cb-has-vscode.sh` only checks `command -v code`, so on a
   desktop with VS Code installed it would say yes, and install extensions as root.

7. **What `booth-entry` provides is missing.** Outside a container, nothing runs `booth-entry`,
   so it cannot break anything. Its work is simply absent:
   - **Setups depend on these steps.** On host and GHA, `booth-entry` itself runs them. It is
     invoked as root, and its container-only blocks are skipped through `CB_TARGET` guards (prep
     #7). Nothing is re-implemented elsewhere.

     | Step | What it does | Without it |
     | --- | --- | --- |
     | 8 | Adds a block to `~/.bashrc` and `~/.zshrc` that sources `/etc/profile.d/*-cb-*.sh` in **every interactive shell** | Login shells still read `profile.d`, but a terminal window opens a non-login shell, and zsh never reads it. The tools seem missing until the next login, or always under zsh. |
     | 12 | Copies `/etc/cb-home-seed/` into home, no-clobber | 23 setups (aws-cli, gcloud, claude-code, codex, gemini-cli, firebase, …) put their default config there. Without the copy, they start with no defaults. |
     | 12b | Copies `/etc/skel/Desktop` launchers | 7 setups use `/etc/skel`. Only matters on a desktop. |
     | 13 | Copies `/etc/cb-home/` into home, **overwriting** | 1 setup. Skipped on `host` (an `if` guard), so the owner's files are never overwritten. |
     | 14 | Runs the `startup.d` hooks once as the user, after home is ready | 53 setups write a hook, and about 10 of those start a daemon. |
     | 15 | Runs `.booth/startups/` | Project hooks. Matters for GHA. |
     | — | PATH (`/opt/codingbooth/setups`, `~/.local/bin`), `LANG`, `EDITOR`: these come from the base **Dockerfile `ENV`**, not from `booth-entry` | Setup helpers and the user's local bin are missing from PATH. |

   - **Guarded off** on a host or runner, where the user is a real account: `host.docker.internal`,
     low ports, UID/GID alignment (steps 1–5), Cache/Shared file sync (4b, 13b), the Windows fix
     (6), sudo revoke, idle monitor, lifecycle log. Exactly which blocks get a guard is decided
     block by block in Stage 4.
   - **The catch:** `booth-entry` hard-codes `USER_NAME="coder"`, `HOME_DIR=/home/coder` and
     `CODE_DIR=/home/coder/<code>` (lines 207–210), and `booth--as-coder` hard-codes the user too.
     An `if` around a block cannot change who steps 8, 12, 14 and 15 run for. This is the one
     known **rare exception**, and it waits for your decision (see [Open decisions](#open-decisions)).
8. **Setups assume a disposable image.** In a fresh image layer, clobbering is harmless. On a
   real machine it hits whatever the owner already has:
   - about 15 setups `rm -rf` system paths, `/usr/local/go` among them;
   - about 10 overwrite files in `/etc` (the nginx default site, RabbitMQ config, bash completion);
   - 11 use `update-alternatives` or link into `/usr/bin`;
   - 5 run `apt purge`/`remove`.

   A GHA runner is disposable too, so there this matters only on a host.
9. **Setup bodies are not written to be re-run.** [BOOTH_SETUP.md](BOOTH_SETUP.md) asks only the
   generated startup and profile scripts to be idempotent. An image runs each setup once, but a
   host gets re-provisioned. For example, a second run of `go--setup.sh` with the same version
   moves the new tree *inside* the existing `/usr/local/go-<version>` directory instead of
   replacing it.

10. **Run-time settings live outside the Boothfile, and dropping them fails silently.** A booth is
    the Boothfile *plus* `.booth/config.toml`, which `booth run` turns into `docker run` arguments
    and which `booth-entry` reads at start. Replaying the Boothfile alone gives a machine that
    passes its checks and is still not the booth. The experiment found this through xonsh-example
    (its login shell), then found go-example had been "passing" on base while its `config.toml`
    asks for the `xfce` variant. Counts over the 96 examples:

    | Kind | Examples | In a booth | On a host | On GHA |
    | --- | --- | --- | --- | --- |
    | `variant` | 27 (13 xfce, 6 notebook, 5 codeserver, kde, desktop-xfce, terminal) | the image the booth starts from, with that variant's own setups baked in | the variant's setups, replayed like base's; desktops are container-only (item 6) | **always base** (decided): the run is the booth started with `--variant base`; any other variant is reported, not replayed |
    | `-e` env | about 40 lines | env of every process | `profile.d`, except the ones `booth-entry` acts on (below) | `$GITHUB_ENV` |
    | `-v` volumes, `cache-dirs`, `shared-dirs`, `~/…` seeds | 62 / 28 / 2 | persistence, and host config copied in (`~/.npmrc` → `/etc/cb-home-seed/`) | mostly nothing to do: the home persists and the real `~/.npmrc` is already there | `actions/cache` for the caches; the seeds do not apply |
    | `-p`, `port`, `expose` | 26 / 8 | publish container ports to the host | nothing: services listen on the machine itself | nothing |
    | `cmds` | 10 | what the booth runs | the user's own command | the step's `run:` |
    | `dind`, `--device`, `egress`, `engine`, `--platform` | 7 / 2 / 2 / 1 / 1 | container-runtime features | no equivalent; the egress allowlist is a security property that is simply lost | same |

    **What `booth-entry` acts on at run time.** Some `-e` values are not plain environment: they
    change what `booth-entry` does. Today's list is `USER_SHELL` (the login shell, set by
    `+default` shell extensions such as `xonsh+default`), `TZ`, `BOOTH_HOME_SEED*`,
    `BOOTH_HOME_OVERRIDE`, `BOOTH_STARTUP*`, `BOOTH_IDLE_*`, `BOOTH_SUDO`, `BOOTH_LOW_PORTS` and
    `HOST_UID`/`HOST_GID`. On a host each one is a question of whether provisioning may change the
    real account or machine (the login shell, the timezone, sudo), which is item 8's question again.

    **Two consequences:**
    - The emitter (path B) must read `config.toml` too, and classify each setting the way item 6
      classifies setups: replay it, map it (`$GITHUB_ENV`, `actions/cache`), skip it as
      meaningless, or **refuse loudly** (dind, egress). A silent drop is the one option that is not
      allowed.
    - "It works on a host" has to say which part was replayed. The harness now records every
      `config.toml` setting as `DROP` in the report.

    **Decided: GHA is a base booth.** A GHA run is the same as the booth started with
    `--variant base`, never as the variant in `config.toml`. So on GHA the `variant` setting is
    not a silent drop: it is overridden by definition, and the report says so (`BASE` line). The
    reference to compare a GHA run against is `booth --variant base`, not the example's own booth.
    An example whose setups need its variant (a code-server extension, a notebook kernel, a
    desktop app) is then judged by what that setup does on a base booth: skip, or fail. The host
    target is still open.

11. **`APT_SNAPSHOT` assumes the machine is not newer than the pin.** `booth config` stamps the
    Boothfile with `env APT_SNAPSHOT=<date>`, and `apt--install.sh` resolves every package against
    that snapshot. In an image this holds: base is built from a snapshot, and the project's pin is
    the same or later. A live machine has been upgraded past it. On the GHA runner `libcurl4t64`
    was already 8.18.0-1ubuntu2.8, the 2026-10-04 snapshot offers `libcurl4-openssl-dev` only at
    ubuntu2.7, and apt will not pair them or downgrade (systemlib-example). An upgraded host fails
    the same way. To decide, for path B: ignore the pin off-booth (reproducibility then comes
    from the machine, which is the weaker tier the reproducibility stance already describes), or
    pin only packages not yet installed.

Counts in items 8 and 9 come from a grep and are estimates. The Stage 1a test lane replaces them
with real results, and should also run every setup twice.

Checked, and **no** change is needed:

- `SCRIPT_DIR="$(dirname "$0")"` works when a script is called through PATH or by full path.
- `HOME=/root` in 184 setups is correct, because setup bodies run as root.
- `variantProvidedSetups` matters only to the container backend. The host emitter decides on the
  base image's baked-in setups (`tls`, `just`, `lazygit`, …) itself.

## Preparation, by risk to today's booths

| # | Change | Risk | Why |
| --- | --- | --- | --- |
| 1 | **Fresh-host test lane**: run setups in a plain `ubuntu:26.04` container with no `booth-entry`, as a user that is not `coder`; check that each starter runs | **None** | Only adds tests. It is also the tool that shows which setups really break on a host. |
| 1b | **`CB_TARGET` helper** in `setups/libs/`: reads, validates, defaults to `booth`. Nothing branches on it yet. | **None** | New file only. No setup calls it until a later stage needs it. |
| 2 | **`CB_USER_HOME` in setup and install bodies** (about 20 setups + 12 installs), `$HOME` in the profile/startup scripts they generate (see [below](#parameterizing-the-user-home)) | **Low–Medium** | The default stays `/home/coder`, so booths behave the same. The risk is typos in about 20 scripts, each also needing a `cb-version` bump. Use #1 to check them. |
| 3 | **`CB_USER_HOME` in template `env` lines** | **Low** to booths, **High churn** | Every generated Boothfile changes. All examples need `booth config` regenerated (new `.generated`), and every user's booth rebuilds on its next reconfigure. |
| 4 | **Host-compat classification**: host-safe, user-coupled, clobbers host state, not re-runnable, or container-only, kept in a separate data file | **None** | A header in each script would count as an edit to all 332, forcing a version bump and manifest regen on every one. |
| 5 | **GHA smoke run**: one workflow that builds and execs an example booth on a hosted runner | **None** | Shows what path A trips on: no TTY, build caching, the DinD consent flags. |
| 6 | **Split the Boothfile compiler** into parse → IR → Dockerfile backend | **Medium** | It sits at the heart of every build. It is well covered: Go tests, `tests/boothfile`, and a byte-for-byte `emit-dockerfile` comparison of every example and fixture. |
| 7 | **`CB_TARGET` guards in `booth-entry`**: wrap each container-only block in an `if`, so that host and GHA run the same `booth-entry` with those blocks skipped. No code moves out and no new code goes in. | **Medium** | When `CB_TARGET` is unset, every guard is true and every block runs as today. The risk is a guard written wrong, in the most sensitive file there is. The user-name exception is the separate, riskier part. |
| 8 | **Make release-specific setups work on 24.04** | **Medium** | Changes apt and repo logic just tuned for 26.04. **Not needed for GHA**, because runners can pin `ubuntu-26.04`. Only matters if host users on 24.04 must be supported. **Postponed indefinitely.** |

## The target variable, CB_TARGET

One variable tells a setup, and the provisioning steps, **what they are installing into**:

| `CB_TARGET` | Meaning |
| --- | --- |
| *(unset)* or `booth` | A booth image. This is today's behaviour, and it stays the default. |
| `gha` | A GitHub Actions runner: disposable, user `runner`, `run:` steps read no profiles |
| `host` | A real machine someone keeps: owner's files must survive, setups get re-run |

Rules:

- **Unset means `booth`.** No Dockerfile has to set it, so introducing it changes nothing for
  booths and needs no image rebuild.
- **An unknown value is an error, never a guess.** A typo must not silently fall back to `booth`.
- **It names the target, not where the job runs.** Path A (a booth built inside a GHA job) is
  `booth`, even though it runs on GitHub. `GITHUB_ACTIONS=true` therefore does **not** imply
  `gha`, so there is no auto-detection.
- `host` rather than `ubuntu`: the variable says what kind of machine, not which OS. The OS is
  Ubuntu 26.04 for now, and `/etc/os-release` already says so.
- Read it through one shared helper in `setups/libs/` (proposed name `cb-target.sh`), so the
  default and the validation live in one place.
- The name `CB_TARGET` is unused in the tree today.

What branches on it:

- container-only setups call `skip_setup` unless the target is `booth`;
- the default of `CB_USER_HOME`;
- clobbering behaviour: `host` keeps existing files (`/etc` configs, `/usr/local/go`, step 13's
  overwrite becomes no-clobber);
- where exports go: `profile.d` (`booth`, `host`) or `$GITHUB_ENV` / `$GITHUB_PATH` (`gha`).

## Parameterizing the user home

Hard-coded `/home/coder` gives way to the existing catalog idiom, `${VAR:-default}`, which
`SETUP_LIBS_DIR` already uses. The variable is **`CB_USER_HOME`**, not `USER_HOME`:

- `USER_HOME` is JetBrains' own `$USER_HOME$` macro, which `jetbrains-first-run--setup.sh` writes
  into IDE config. Inside an unquoted heredoc, it would expand.
- A generic name could come in from a host environment.
- [BOOTH_SETUP.md](BOOTH_SETUP.md) asks for the `CB_*` prefix.

The fix depends on where the path appears:

| Where | Fix |
| --- | --- |
| **Setup body** (runs as root at build time) | `${CB_USER_HOME:-/home/coder}`. On a host, `sudo` drops env vars, so the emitter must pass it explicitly: `sudo CB_USER_HOME=… x--setup.sh`. |
| **Generated profile/startup scripts** (run as the user) | plain `$HOME`, already right for whoever logs in. Watch the escaping inside unquoted heredocs. |
| **Template `env` lines**, which become Dockerfile `ENV` | `${CB_USER_HOME:-/home/coder}`. Docker's `ENV` supports `:-`, so with the variable unset the value is still `/home/coder`. A **bare** `$HOME` would expand to empty at build time and break PATH, so never use that. |
| **CLI Go code** (26 files) | leave as is. These are paths inside the container (mount targets, connect, worktree mirroring), and the CLI only ever drives containers. |

## Why /opt/codingbooth stays fixed

- `/opt` is the standard place for add-on packages on a real host too. Setups need root anyway,
  and GHA runners have `sudo`, so a host install lives at `/opt/codingbooth` unchanged.
- 143 files under `variants/` reference it. A second knob would double the configurations to test
  (default path vs. relocated path) without enabling anything.
- Revisit if installing **without root** becomes a goal. Much of the plumbing is already
  overridable: `SETUP_LIBS_DIR`, `CB_HAS_VSCODE`.

## Stages

Each stage gets its own proposal and worktree, lands, then soaks before the next one starts.

| Stage | Work | Gate before moving on |
| --- | --- | --- |
| **1a** | #1 test lane + #1b `CB_TARGET` helper + #2 `CB_USER_HOME` in setups **and the 12 install scripts** | Lane passes with `CB_USER_HOME` pointing at another user's home; booths unchanged; soak |
| **1b** | #3 template `env` lines + regenerate examples | Round trip of `booth config` is clean; examples build; soak |
| **2** | #4 classification + #5 GHA smoke run | Evidence of what really breaks; may shrink later stages |
| **3** | #6 compiler IR split | Byte-identical `emit-dockerfile` output for every example and fixture; soak |
| **4** | #7 `CB_TARGET` guards in `booth-entry`, plus the user-name exception if approved | Complex lifecycle suite, run several times because of the race; soak |
| **Feature** | Path A: docs + composite action. Path B: `emit-script --target host\|gha`, on `runs-on: ubuntu-26.04`. | — |

## Open decisions

- [ ] `CB_USER_HOME` as the variable name (proposed).
- [ ] `CB_TARGET` with values `booth` / `gha` / `host` (proposed; `host` rather than `ubuntu`).
- [ ] **Rare exception in `booth-entry`:** host and GHA need steps 8, 12, 14 and 15 to run for the
  real user (`runner`, or the machine's owner) and the real project folder, not for `coder`.
  - Smallest proposed change: `USER_NAME="${CB_USER_NAME:-coder}"` at line 207, plus the same in
    `booth--as-coder`. `HOME_DIR` then follows from it, and `CODE_DIR` gets the same
    `${…:-…}` form.
  - With the variables unset, every value is what it is today.
  - No other part of `booth-entry` changes.
  - The alternative is to skip steps 8, 12, 14 and 15 on non-booth targets, and accept that the
    setups lose profile loading, seeds and startup hooks there.
- [ ] `/opt/codingbooth` stays fixed for now (proposed).
- [ ] Classification as a separate data file (proposed) or as a per-script header.
- [x] Path B targets Ubuntu 26.04: same release as base, and GHA pins `runs-on: ubuntu-26.04`.
  #8 is postponed indefinitely.

## Experiment results

**2026-10-26**, branch `host-provision-exp`, files in `experiments/host-provision/`. Nothing under
`variants/`, `templates/` or the CLI was changed, except the install-script fixes listed below.

### What was run

- `base-provision.sh`: `variants/base/Dockerfile` replayed as a root script.
- `provision-example.sh`: the `go-example` Boothfile replayed. `env` lines went to `profile.d`,
  with `/home/coder` rewritten to the real home.
- A copy of `booth-entry` with only `CB_TARGET` `if` guards, plus the `CB_USER_NAME` /
  `CB_USER_HOME` / `CB_CODE_DIR` exception. It then ran the example's checks as the real user.

It ran on two kinds of machine:

- **GHA:** a real `ubuntu-26.04` runner (run 40273828543), as user `runner` (uid 1001).
- **Locally:** a plain `ubuntu:26.04` container, once as `CB_TARGET=gha` (user `runner`) and
  once as `CB_TARGET=host` (user `owner`, uid 1000).

### Results

**First run** (GHA run 40273828543, and locally):

| | GHA runner | Local `host` |
| --- | --- | --- |
| Boothfile lines | 6 of 9 pass | 6 of 9 pass |
| Checks | 18 of 20 pass | 18 of 20 pass |
| Failures | `install go gopls`, `install go dlv`, `setup go-nb-kernel` | same |
| Cause | `sudo: user 'coder' not found` in `go--install.sh` and `go-nb-kernel--setup.sh` | same |

Every failure came from the hard-coded `coder` user. Nothing else broke.

**After the fix** (commit `ab10f88a`, GHA run 40275899532, and locally):

| | GHA runner | Local `host` |
| --- | --- | --- |
| Boothfile lines | **9 of 9 pass** | **9 of 9 pass** |
| Checks | **20 of 20 pass** | **20 of 20 pass** |

The fix: both scripts read `CB_USER_NAME="${CB_USER_NAME:-coder}"`, and go-nb-kernel also reads
`CB_USER_HOME="${CB_USER_HOME:-/home/${CB_USER_NAME}}"`. Each got a minor `cb-version` bump
(1.0.0 → 1.1.0), and the catalog manifest was regenerated. `provision-example.sh` now passes
`CB_USER_NAME`. One check in the real base image: with the variable unset, `go--install.sh` still
installs into `/home/coder/go/bin`, owned by `coder`. The full container test pass is deferred to
the Stage 1a work.

What passed:

- **Tools:** Go 1.25.7 (in login, interactive and zsh shells), `gopls` and `dlv` in the real
  user's `GOBIN`, Python 3.13.12, code-server, Jupyter with the Go (GoNB) kernel registered, the
  code extensions (installed into code-server's shared extension directory), and the base tools
  (just, lazygit, gpg 2.5.24).
- **The example's own work:** `go test ./...` and `./build.sh`.
- **The `booth-entry` copy's user steps:** the rc profile block, the five startup hooks (tls, go,
  superfile, notebook, 99z), and `GOPATH` under the real home.

**Second example: zig-example** (GHA run 40280112491, a matrix with go-example, and locally as
`host`). It passed on the first try with no catalog change:

| | GHA runner | Local `host` |
| --- | --- | --- |
| Boothfile lines | 1 pass, 1 skip | 1 pass, 1 skip |
| Checks | 8 of 8 pass | 8 of 8 pass |

- The skip is `zig-code-extension`. It skipped itself correctly, because no editor is installed.
- From here on the checks are generic. `check-example.sh` runs the base checks, then every one of
  the example's own `.cb-tests/inBooth-test*.sh`. `BOOTH_CONTAINER_NAME` is set, so the
  example's Justfile runs recipes in place. **38 of the 96 examples** have in-booth tests (the
  other 58 have only `--on-host` tests, or none); an example without them is reported `UNTESTED`.
- go-example's own four in-booth tests also passed on GHA, in a later `bash -l` step: go, gopls,
  dlv and gomodifytags.
- In a later plain step, `zig` resolved to the setup's `/usr/local/bin/zig`, confirming finding 3.
  The runner has no zig of its own.

**Seven more examples** (GHA run 40344941831, a nine-example matrix, and locally as `host`):

| Example | GHA runner | Local `host` | Needed |
| --- | --- | --- | --- |
| bun-example | 13 pass, 1 skip | pass | `bun--install.sh` takes `CB_USER_NAME` |
| deno-example | 10 pass, 1 skip | pass | `deno-pkg--install.sh` takes `CB_USER_NAME` / `CB_USER_HOME` |
| npm-example | 14 pass, 1 skip | pass | one in-booth test did `cd /home/coder/code` |
| pip-example | 16 pass, 1 skip | pass | nothing |
| clang-example | 14 pass, 2 skip | pass | on GHA, the runner's apt sources (finding 8) |
| bash-example | 8 pass | pass | one in-booth test did `cd /home/coder/code` |
| xonsh-example | 8 pass, 1 skip, **1 fail** | **1 fail** | the login shell: open, see finding 9 |

go-example and zig-example passed again in the same run. Every skip is a `*-code-extension` with
no editor installed.

- `bun--install.sh`, `deno--install.sh` and `deno-pkg--install.sh` got the same fix as
  `go--install.sh` (`cb-version` 1.1.0, manifest regenerated). `deno--install.sh` is not used by
  any of these examples.
- Three in-booth tests (bash, npm, xonsh) now `cd "$(dirname "$0")/.."` instead of
  `/home/coder/code`, and the xonsh test looks up `$(id -un)` instead of `coder`. Inside a booth
  both are the same path and user as before. The 16 other `/home/coder/code` mentions are in
  `--on-host` tests, which run their command inside a booth, so they stay.

**Ten more examples** (GHA runs 40364462980 and 40366742712, and locally as `host`), with the
earlier eight in the same matrix. The report now also lists every `config.toml` setting as `DROP`.

| Example | Result, GHA and local `host` | Needed |
| --- | --- | --- |
| csharp-example | pass | nothing |
| goose-lang-example | pass | nothing |
| ocaml-example | pass | nothing |
| php-example | pass | nothing |
| lsp-example | pass, once **flaky** | the `nvim` recipe waits a fixed `sleep 3`; on one cold runner marksman had not attached yet. Not specific to the host |
| apt-example | pass | its snapshot test read `/home/coder/code/.booth/Boothfile`; now the Boothfile beside the test |
| homebrew-example | pass | `homebrew--setup.sh` and `brew--install.sh` take `CB_USER_NAME` (1.1.0); the redis and nginx tests used `base + $$` as a port, past 65535 with a runner's or host's PIDs |
| spring-boot-example | **untested** | provisions cleanly, but has no in-booth tests |
| helix-example | **known not working** | its config comes from `config.toml` `shared-dirs` (Where it breaks, item 10) |
| systemlib-example | **known not working** | its `APT_SNAPSHOT` is older than the machine's installed `libcurl4t64` (item 11) |

**Where the examples stand** (the workflow matrix carries the known-working list):

- **Known working, 15:** go, zig, bun, deno, npm, pip, clang, bash, csharp, goose-lang, lsp,
  ocaml, php, apt, homebrew. That means the Boothfile part: go, bun, npm and pip also have
  `config.toml` settings that were dropped (caches, `cmds`). go-example's `xfce` variant is
  not a drop on GHA: GHA is a base booth by decision (item 10).
- **Known not working, 3:** xonsh (the login shell) and helix (shared config) because of item 10;
  systemlib because of item 11.
- **Untested, 1:** spring-boot.

#### All examples (GHA run 40645215815)

Every example now has in-booth tests: 58 got new ones in this round. The new tests have not been
run in a booth yet, so a failure in one of them can be a test bug; those are marked below. The run
covered 93 examples: all but xonsh, helix and systemlib, which are already known not to work.

| Outcome | Jobs |
| --- | --- |
| Passed | **52** (3 of them with a failed setup line: lamp, lemp, wordpress; see C) |
| Failed | **41** |

Why the 41 failed, grouped by cause (an example can show up under more than one):

| Cause | Examples | Count |
| --- | --- | --- |
| **A. A startup hook hard-codes `/home/coder`.** `claude-code`'s hook makes `/home/coder/.local/bin`, `mongodb`'s makes `/home/coder/.mongodb`. The hook fails with `mkdir: Permission denied`, and `booth-entry` step 14 stops the whole start, so no test ran. In a booth `$HOME` is `/home/coder`, so changing the path to `$HOME` changes nothing there | claude-code: aws, claude, claude-token, dind, egress-envoy, elixir, firebase, gcloud, haskell, herdr, jetbrain, js, kind-app, kind, kotlin, neovim, nodejs, python, rust, server, server-2, zig-snake. mongodb: mean, mern | 24 |
| **B. An install script hard-codes the `coder` user** (`sudo: user 'coder' not found`). The same kind of fix as bun/deno/homebrew. 17 scripts still do this, among them `gem--install.sh`, `cargo--install.sh`, `wails--setup.sh`, `dotnet--install.sh`, `conan--install.sh`, `neovim--setup.sh`, `redis--setup.sh` and `gcloud--setup.sh` | ruby, rails, wails, wails-android (rust as well, after A) | 4 |
| **C. Harness gaps** (the experiment's scripts, not the catalog): the project's own `.booth/setups/` is not on PATH; `run` lines are not replayed (here, a `pip`/`npm` install of the project's dependencies); an example with no Boothfile stops the harness | npm-deps, pip-deps, cache (no Boothfile); lamp, lemp, wordpress and data (local setups) | 3 failed + 4 partial |
| **D. A base booth by decision.** The example needs its variant, as item 10 says. i3 skips without XFCE; `jupyter` comes from the notebook variant; the code-server extension test needs code-server | i3-desktop, tiling, empty (i3); conda (jupyter); lean (test004 vscode-ext) | 5 |
| **E. A `config.toml` run-time setting** (item 10) | n8n (`N8N_INSTANCE_AI_SANDBOX_ENABLED` is a run-args env) | 1 |
| **F. The example itself is stale.** It pins Playwright 1.58.0, which "does not support chromium on ubuntu26.04-x64"; playwright-example pins 1.63.0 and passes. This should fail in a booth as well (not checked) | playwright-polyglot | 1 |
| **G. A new test is probably wrong** (not yet run in a booth) | data (test002 pipes `jupyter --version` into a closed pipe: `BrokenPipeError`), rlang (expects "R scripting front-end" in `Rscript --version`) | 2 |
| **H. Flaky** | lsp (neovim test, the fixed `sleep 3` again) | 1 |

Notes on what this means:
- **A is the largest group, and it is a new kind of problem.** Install scripts were checked for the
  user name; startup hooks were not. Hooks are written by the setups but run at start time as the
  user, so they belong in the same audit. A related point: because one failing hook stops the whole
  start, a single hard-coded path cost 24 examples their whole run.
- A and B are the same fix pattern that is already on the branch (`CB_USER_NAME`, `$HOME`).
  Fixing them would get to the tests of 28 more examples.
- C belongs to the harness and must be fixed there. Project setups must be on PATH, as they are in a
  booth. `run` lines are a real question for path B: it has to replay them, or the project's
  dependencies are missing.
- The summary job in the workflow read the wrong artifact path: upload-artifact keeps the full
  path for two files. So every row said "no report", and the table above was made locally from
  the downloaded artifacts.

#### After fixing A, B and C (GHA run 40746874561)

A: startup hooks use `$HOME`. B: 6 install scripts and `mongodb-start` take `CB_USER_NAME` /
`CB_USER_HOME`. C: the harness replays `run` and `copy` lines and puts the project's
`.booth/setups/` on PATH. Every default is today's value, so a booth sees the same strings.

**83 passed, 10 failed** (was 52 / 41). Every job wrote a report.

| Example | Cause |
| --- | --- |
| i3-desktop, tiling, empty | D: i3 needs XFCE; a base booth by decision |
| conda (3 tests) | D: `jupyter` comes from the notebook variant |
| lean (test004) | D: the code-server extension test needs code-server |
| n8n | E: a `config.toml` run-args env |
| playwright-polyglot | F: the example pins Playwright 1.58.0, which does not support Ubuntu 26.04 |
| data (test002), rlang | G: the new test is probably wrong (not yet run in a booth) |
| wails-android (test002) | **not diagnosed yet**: the APK builds but "'Booth counter' is missing from the APK". It got this far only now, because the wails setup used to fail first |

lsp passed this time (it is still flaky). wails-example now passes.

### Findings

1. **The `booth-entry` exception is needed, and enough for this example.** The `if` guards
   skipped the container-only blocks cleanly. With only `USER_NAME`, `HOME_DIR` and `CODE_DIR`
   overridable, steps 7, 8, 12, 14 and 15 did their job for a real user.
2. **Install scripts are the bigger `coder` problem.** Stage 1a has to cover the 12 install
   scripts as well as the ~20 setups. Without them, every `*-pkg` extension fails off-booth.
   Two of these (`go--install.sh`, `go-nb-kernel--setup.sh`) are already fixed on this branch.
   The pattern is a `CB_USER_NAME` / `CB_USER_HOME` default, with no other change.
3. **Starters beat the runner's preinstalled tools, even without a profile.** The runner ships
   `/usr/bin/go`, `python3`, `node` and `java`. In a later plain step (`bash --noprofile`),
   `go` still resolved to the setup's `/usr/local/bin/go` starter: `/usr/local/bin` comes first
   on the default PATH. Env such as `GOPATH` did not carry over. A step with `shell: bash -l {0}`
   got everything. No conflict with the preinstalled tools was observed.
4. **Base changes a host machine-wide.** `gnupg--setup.sh` puts gpg 2.5 in `/usr/local/bin`,
   shadowing the system's 2.4 for every user. On a runner that is fine; on someone's own machine
   it should be opt-in.
5. **Timing on GHA:** base 2m31s (mostly building gnupg from source), the example 1m07s,
   `booth-entry` plus checks 11s. The whole job took 4m03s.
6. **A harness lesson for the test lane.** With `fs.protected_regular` (the Ubuntu default),
   root cannot write a user-owned file in a sticky directory such as `/tmp`. Reports and logs
   that root and the user both write go under the user's home or the runner's temp directory.
7. **Some example tests cannot see a failed install.** bun-example's and deno-example's tests use
   `bun x cowsay` and `deno run npm:cowsay`, which fetch the package on demand. Both passed while
   `install bun` and `install deno-pkg` had failed. The workflow's plain step now lists the
   installed commands; on GHA `cowsay`, `figlet`, `prettier` and `tsc` are in `/usr/local/bin`
   after `install bun`. `deno-pkg` installs no commands by design (`deno add` writes a
   `deno.json`), in a booth as well.
8. **A GHA runner reads apt through a mirror list.** Its sources are
   `mirror+file:/etc/apt/apt-mirrors.txt` (`azure.archive.ubuntu.com`), and two setups assume the
   image's plain `archive.ubuntu.com`:
   - `apt--install.sh` with `APT_SNAPSHOT`: `--snapshot` redirects only hosts apt knows, so the
     pinned install found no index ("Unable to locate package nlohmann-json3-dev").
   - `clang--setup.sh` recognises Ubuntu's own `clang-N` by `archive.ubuntu.com` in
     `apt-cache madison`. The runner prints `mirror+file:…`, so the script added apt.llvm.org,
     which has no `resolute-18` repo. The broken `.list` it left then failed `apt-get update` in
     cmake and make too.

   `base-provision.sh` now, on `gha` only, rewrites the runner's sources to
   `http://archive.ubuntu.com/ubuntu/`, as in the image. After that, `apt` pinned to
   `snapshot.ubuntu.com` and clang used Ubuntu's repo. On `host` the sources are left alone, so a
   machine with a local mirror has the same problem; the setups' archive checks are the place to
   fix it for good.
9. **A login shell is a run-time setting, so nothing applies it off-booth.** xonsh-example gets
   `USER_SHELL=/usr/local/bin/xonsh` from `config.toml` run-args, and `booth-entry` applies it in
   the user steps (1–5b). The harness does not replay `config.toml`, and the guarded copy skips
   those steps on `gha` and `host`. That is deliberate: changing a real user's login shell is the
   clobbering that "Where it breaks" item 8 is about. xonsh itself works (`xonsh hello.xsh` passed).
   To decide: whether the feature offers a login-shell change, opt-in, on `host`. This turned out
   to be one case of a whole category: see [Where it breaks](#where-it-breaks), item 10.
10. **Example tests carry booth assumptions of their own.** Five in-booth tests failed for reasons
    in the test, not in the setup: a hard-coded `/home/coder/code` (bash, npm, xonsh, apt), the
    user `coder` (xonsh), and a port computed from the PID (homebrew). Each fix keeps the same value
    inside a booth. A test lane that runs examples off-booth will keep finding these, so it is
    worth a lint: no `/home/coder` or `coder` in `inBooth-*` tests.

### Not covered yet

- Services actually starting (code-server, notebook) from their startup hooks.
- Running the provisioning a second time.
- A real host with systemd. For example, apt's `nginx` package may start nginx on port 80 there.
- The `host`-only guards (11b, 13, the root chown). go-example has no `.booth/home` and no
  `/etc/cb-home`, so these did not change the result.
- The other 77 examples, in particular ones with `copy` lines (rust-example), a `variant`,
  desktops or services.
- `config.toml` settings: none are replayed (Where it breaks, item 10).

