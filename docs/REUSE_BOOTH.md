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
| **Variants**, `config.toml` | no | run-args, ports, mounts, cache/shared folders make sense only for a container |

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
`variants/`, `templates/` or the CLI was changed.

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

| | GHA runner | Local `host` |
| --- | --- | --- |
| Boothfile lines | 6 of 9 pass | 6 of 9 pass |
| Checks | 18 of 20 pass | 18 of 20 pass |
| Failures | `install go gopls`, `install go dlv`, `setup go-nb-kernel` | same |
| Cause | `sudo: user 'coder' not found` in `go--install.sh` and `go-nb-kernel--setup.sh` | same |

**Every failure came from the hard-coded `coder` user. Nothing else broke.**

What passed:

- **Tools:** Go 1.25.7 (in login, interactive and zsh shells), Python 3.13.12, code-server,
  Jupyter, the code extensions (installed into code-server's shared extension directory), and the
  base tools (just, lazygit, gpg 2.5.24).
- **The example's own work:** `go test ./...` and `./build.sh`.
- **The `booth-entry` copy's user steps:** the rc profile block, the five startup hooks (tls, go,
  superfile, notebook, 99z), and `GOPATH` under the real home.

### Findings

1. **The `booth-entry` exception is needed, and enough for this example.** The `if` guards
   skipped the container-only blocks cleanly. With only `USER_NAME`, `HOME_DIR` and `CODE_DIR`
   overridable, steps 7, 8, 12, 14 and 15 did their job for a real user.
2. **Install scripts are the bigger `coder` problem.** Stage 1a has to cover the 12 install
   scripts as well as the ~20 setups. Without them, every `*-pkg` extension fails off-booth.
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

### Not covered yet

- Services actually starting (code-server, notebook) from their startup hooks.
- Running the provisioning a second time.
- A real host with systemd. For example, apt's `nginx` package may start nginx on port 80 there.
- The `host`-only guards (11b, 13, the root chown). go-example has no `.booth/home` and no
  `/etc/cb-home`, so these did not change the result.
- Other examples.

