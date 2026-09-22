# Podman Support

Status: **experimental.** Docker is the supported container engine. Podman support
is still being developed and **may not have feature parity with Docker** — read
[Known limitations](#known-limitations) before relying on it.

This document has two parts, kept apart on purpose:

1. **[Implemented](#part-1--implemented-phases-13)** — what ships today, as built and
   as verified. Nothing in it is a promise about the future.
2. **[Plan](#part-2--plan-not-implemented)** — what is *not* built: phases 4–6 and
   follow-ups.

Phases 1 (core lifecycle), 2 (`booth expose`) and 3 (build progress) are implemented.
Phases 4–6 are not started.

---

# Part 1 — Implemented (Phases 1–3)

## Choosing the engine

`engine` is an ordinary setting, resolved like `--sudo` or `--egress-mode`.

| Way | Example |
| --- | --- |
| CLI flag | `booth --engine podman` (also `booth build --engine podman`) |
| Environment | `CB_ENGINE=podman booth` |
| Project config | `engine = "podman"` in `.booth/config.toml` |
| Config TUI / CLI | `booth config` (a "Container Engine" field), or `booth config . --no-tui --set engine=podman` |

Values are `docker` and `podman` (case-insensitive). Anything else is rejected:
`❌ invalid engine "nerdctl" (supported: docker, podman)`.

**Precedence** is the usual one: `--engine` > `.booth/config.toml` > `CB_ENGINE` > default.

### Which engine each command uses

Only `booth` (run) and `booth build` take `--engine`. The other commands do not build
the full application context, so they cannot see the flag:

| Command | Engine comes from |
| --- | --- |
| `booth` (run), `booth build` | `--engine` > config.toml > `CB_ENGINE` > default |
| `booth list`, `stop`, `start`, `restart`, `remove`, `prune`, `message`, `expose list` | **Both engines** when none is chosen (see below). If `CB_ENGINE` is set — or, for `start`, `engine` in the `.booth/config.toml` under `--code` — only that engine. |
| `booth shell`, `booth exec` | `engine` in the `.booth/config.toml` under `--code`, then `CB_ENGINE`, then Docker. **Without `--code`, only `CB_ENGINE` is read** (not the current directory's config). |
| `booth home-volume-*` | `CB_ENGINE` only |

### Finding booths on either engine

When you have not chosen an engine and **both `docker` and `podman` are installed**, the
commands in the first row ask both and show one list. Each booth is remembered with the
engine that owns it, and `stop`, `start`, `restart`, `remove`, `prune` and `expose list`
act on that engine — so `booth stop mybooth` stops a Podman booth without any
`CB_ENGINE`.

- `booth list` adds an `ENGINE` column, only in this both-engines case; with one engine
  the output is exactly what it was.
- Setting `CB_ENGINE` (or `engine =` in config) to either value narrows every one of
  these commands to that engine. This is also how you choose when a name exists on both:
  `Error: booth "web" exists on both docker and podman. Set CB_ENGINE=<engine> to choose one.`
- If one engine cannot be queried (for example the Docker daemon is not running) a
  `Warning: could not list docker booths: …` goes to stderr and the other engine's
  booths are still used. It is an error only when every engine fails.
- With only one of the two installed, that one is used, as before.

`booth shell`, `booth exec` and `home-volume-*` are not part of this: `shell`/`exec`
can create a booth (`--run`) and so need one definite engine, and a home volume lives in
one engine's store. For a Podman booth use `CB_ENGINE=podman booth shell`.

### When you choose nothing

The default is `docker`, so nothing changes for existing users. One narrow exception:
if the engine was never set (no flag, config or env) **and `docker` is not on `PATH`
but `podman` is**, CodingBooth uses `podman` and says so once:

```
⚠️  docker not found — using podman instead (experimental; --engine docker to force)
```

`--quiet` hides that line. An explicit choice is never overridden. If neither binary is
found, the run fails the way it always did (the engine command is not found).

### Experimental warning

Whenever `podman` is chosen explicitly, this is printed to stderr and is **not**
hidden by `--quiet`:

```
Warning: --engine podman is experimental and may not have full Docker feature parity yet. See docs/PODMAN_SUPPORT.md.
```

A command that spawns other `booth` processes (for example `exec --run`) can print it
more than once. `--help`, `docs/BOOTH_RUN.md` and the README say the same.

## What runs on the chosen engine

Every engine call the CLI makes goes through the selected binary — `run`, `build`,
`ps`/`inspect`/`exec`/`stop`/`rm`/`restart`/`start`/`port`, `volume`, `network`, the
container lookup used to diagnose a port conflict, and the sidecar clean-up done before
a run. That includes the `<engine> exec -i … socat` that carries each `booth--expose`
tunnel connection, and the `<engine> port` lookup behind `booth expose list`.
`--dryrun` and `--verbose` print the real `podman …` command line.

## Podman-specific behavior

These are applied automatically when the engine is Podman.

- **Builds pass `--format docker`.** Buildah's default OCI image format silently
  ignores the Dockerfile `SHELL` directive (`SHELL is not supported for OCI image
  format … will be ignored`). Every shipped Dockerfile sets `SHELL ["/bin/bash","-o",
  "pipefail",…]`, so without this every `RUN` step failed with
  `set: Illegal option -o pipefail`. Docker builds are unchanged.
- **Rootless runs add `--userns=keep-id --user root`** (when the CLI is not run as
  root). Rootless Podman maps your host user to container *root*, so the `coder`
  user could not write bind-mounted files or `.booth/.tmp` — where the shutdown and
  restart markers live — and a booth could not shut down. `keep-id` maps your host UID
  to the same UID inside; `--user root` lets `booth-entry` start as root to align
  `coder`, exactly as under Docker. Container-root here is an unprivileged
  subordinate UID, not host root. Rootful Podman and Docker get neither flag.
- **Low ports are allowed for `coder`** (`--sysctl net.ipv4.ip_unprivileged_port_start=0`).
  Docker sets this in every container; Podman leaves it at 1024, so the `--public`
  TLS proxy (Caddy wants `:80`) and any app a user runs on `:80`/`:443` failed with
  "permission denied". It is skipped for `--dind` / `--egress`, where the booth joins
  another container's network namespace and Podman cannot set it.
- **`home-volume-export` keeps your UID** (`--userns=keep-id` on its helper container).
  Without it the helper ran as an unprivileged subordinate UID and could not write the
  backup file.
- **BuildKit-only behavior is skipped.** `--progress=auto` and the BuildKit probe are
  Docker-only; Podman prints its own `STEP n/m` output.
- **`--silence-build` actually silences a Podman build.** Buildah's `STEP n/m:` headers
  and every `RUN` step's own output land on *stdout*, not stderr — confirmed against a
  real `podman build` — while only registry-pull chatter and the final error go to
  stderr. The silent build path used to capture stderr only (a BuildKit-shaped
  assumption), so a Podman booth build printed every `STEP`/`RUN` line live regardless
  of `--silence-build`; that was a correctness bug, not just a missing live-progress
  line, and is now fixed: both streams are captured on Podman and shown only on
  failure, exactly like Docker's silent path. `build_progress.go` also gained a
  Buildah-format parser (`STEP n/m: …`, `--> …`, `COMMIT …`), so the same one-line
  ticking status a Docker build shows now renders on Podman too. The two format
  parsers are kept separate rather than shared, since the two engines' plain output
  shapes have little in common beyond both being line-oriented.
- **Docker's host check is skipped.** The Linux rootless-Docker / userns-remap refusal
  and the "Docker daemon not reachable" check describe how *Docker* maps the host user,
  so they do not run for Podman.
- **Errors name the engine that failed** (`podman restart failed with exit code 125`).
  Docker's messages are unchanged.
- **`restart` passes `--time`** — `podman restart` has no `--timeout`.
- **Port-conflict help** looks up the container holding a port with the chosen engine;
  the "orphaned docker-proxy" hint is Docker-only.
- **User-facing hints name the real engine**, not always Docker: the daemon-mode "stop
  with" line, the DinD "stop && network rm" line, the DinD-not-ready "check: … logs"
  line, the `--persist-home` "reclaim space" line, and the silent-build "❌ … build
  failed!" banner all read `podman` on a Podman booth.
- **`--dind` warns instead of trying silently.** `docker:dind` has no Podman equivalent
  yet (Phase 4), so `--dind` with `--engine podman` prints `Warning: --dind has no
  Podman support yet and will likely fail …` and then tries anyway, rather than failing
  confusingly with no explanation.

### Host prerequisites for rootless Podman

Rootless Podman needs `/etc/subuid` and `/etc/subgid` entries for your user, or image
layers cannot be unpacked (`potentially insufficient UIDs or GIDs available`):

```bash
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$USER"
podman system migrate
```

Pick ranges that do not overlap another user's. This does not affect a Docker daemon
that has no `userns-remap`. If you ran a development build from before the `keep-id` fix under
rootless Podman, the project directory may be left owned by a subordinate UID and show as
`999:999`; restore it with `podman unshare chown 0:0 <project-dir>`.

## Verification status

Verified by hand on **Linux, rootless Podman 5.4.2** (crun, pasta), with Docker also
installed, on 2026-09-21 (Phase 1), again for Phase 2, and again on 2026-09-22 for
Phase 3:

| Area | Result |
| --- | --- |
| Build the real 55-step `variants/base` image and a full example project (JDK + tool setups) | works |
| `booth` run (foreground and `--daemon`), port mapping, files owned by the host user | works |
| Shut down from inside the booth (`booth--shutdown`) | works |
| `list`, `stop`, `start`, `restart`, `remove` (with `CB_ENGINE=podman`) | work |
| With no `CB_ENGINE` and both engines installed: `booth list` shows a Docker and a Podman booth side by side (`ENGINE` column), `booth expose list` finds a Podman booth, and `booth stop <name>` stops a Podman booth and a Docker booth, each on its own engine | works |
| `prune` (nothing stale to prune in the test) | ran without error |
| `exec --name …`, and `exec --run` (creates the booth, runs, tears it down) | work |
| `booth build --engine podman` (real build) | works |
| `--persist-home`: labelled volume created, `coder` can write it, data survives a restart | works |
| `home-volume-list`, and a `home-volume-export` → `home-volume-import` round trip (data read back) | work |
| Interactive `booth shell` (driven through a real pty) | works |
| `message send` reaches the booth | works |
| A restart requested from *inside* a foreground booth (`booth--restart`): the CLI relaunches a fresh container, and a later shutdown ends the CLI | works |
| `--public`: HTTPS answers 302 and plain HTTP 400 — the same as a Docker control run | works (after the low-port fix) |
| `booth--expose 8080 18080` inside a foreground booth: the host opens `localhost:18080`, a `curl` through it gets the response (HTTP 200, repeated requests), and `booth expose list` (with `CB_ENGINE=podman`) shows the tunnel as live | works |
| `--egress`: proxy and netns sidecars start; an allowlisted host connects, a non-allowlisted one is blocked | works (checked by hand only) |
| Engine selection: flag, config, `CB_ENGINE`, precedence, `booth config --set`, fallback, `--quiet`, invalid value | works |
| `booth build --engine podman --silence-build` on the JDK + lazygit + vscode-ext example (10 real build steps): before the fix, the run's captured stdout showed the leaked `STEP`/`RUN` output live; after the fix, stdout carries only the final `Built: …` line and stderr only the experimental warning — the same 10 `STEP` lines still appear (confirmed on the same build without `--silence-build`, redirected to stderr by the pre-existing BuildKit-compat shim), proving the silent path now genuinely hides them rather than the build simply having nothing to print | works |

Automated: Go unit tests (`pkg/appctx/engine_test.go`, `pkg/docker/engine_test.go`,
`pkg/docker/host_check_test.go`, `pkg/docker/docker_build_test.go`,
`pkg/docker/build_progress_test.go`,
`pkg/booth/podman_userns_test.go`, `pkg/booth/booth_test.go`,
`pkg/booth/init/initialize_app_context_engine_test.go`,
`pkg/lifecycle/restart_flag_test.go`, `pkg/lifecycle/engines_test.go`), the config-TUI schema guard, and
`tests/dryrun/test036--engine.sh` (15 checks, no engine needs to be installed).
Two of those drive a real engine rather than a stubbed flag:
`TestDockerBuild_Silent_FailureNamesEngine` (a real failing `podman build`) and
`TestDockerBuild_Silent_PodmanStdoutIsActuallySilenced` (a real successful `podman
build`, asserting a distinctive `RUN echo` marker never reaches either captured stream).
**No CI job runs against Podman** — see Phase 6.

**Not verified on Podman:** rootful Podman; macOS/Windows (`podman machine`); Podman older than 5.x; SELinux hosts
(bind mounts may need `:Z`, which CodingBooth does not add); `--dind` (unsupported).
`--egress`, `--public` and `--persist-home` were checked by hand once and have no
automated Podman test. After `booth stop` on an `--egress` booth the sidecar containers
go away (a moment later, as Podman removes them) but the egress network is left behind.

The unverified items are **not done yet**; they are tracked, to be done incrementally, under
[Remaining verification](#remaining-verification-incremental) in Part 2.

## Known limitations

- **Docker-in-Docker is not supported.** `--dind`, and anything that needs Docker inside
  the booth (the `dind` tool, `docker-compose`, Appwrite), rely on the `docker:dind`
  sidecar and `DOCKER_HOST`. `--dind` with `--engine podman` is **not blocked** — it
  prints `Warning: --dind has no Podman support yet and will likely fail …` to stderr
  (unconditional, like the experimental-engine warning) and then tries anyway; it is
  unsupported and untested.
- **Tunnels need the booth running in the foreground**, exactly as under Docker
  ([BOOTH_EXPOSE.md](BOOTH_EXPOSE.md)). `booth--expose` inside the booth needs no engine
  setting: the host-side CLI that started the booth already knows it.
- **Lifecycle commands do not take `--engine`** (table above); choose with `CB_ENGINE`.
  `booth shell`, `booth exec` and `home-volume-*` look at one engine only and need
  `CB_ENGINE=podman` for a Podman booth.
- **Podman's live build-progress line only understands Buildah's plain-text format.**
  If a future Buildah version changes its `STEP n/m:` / `-->` / `COMMIT` wording, the
  parser in `build_progress.go` falls silently back to no live line (same as an
  unrecognized format does today) rather than erroring — the build itself is
  unaffected either way.
- **The release pipeline, `tests/wrapper/` and CI are Docker-only.** Images are built
  and published with Docker/buildx.
- **Separate image stores.** Podman cannot see images Docker built or pulled, and the
  reverse; `--pull=never` runs need the image in the engine you chose.

## Where it lives (for maintainers)

| Piece | Location |
| --- | --- |
| Resolution + fallback + warnings | `cli/src/pkg/appctx/engine.go` (`ResolveEngineValue`, `ResolveEngineForPath`) |
| `engine` setting, accessor | `AppConfig.Engine` (`CB_ENGINE`), `AppContext.Engine()` |
| `--engine` parsing and validation | `pkg/booth/init/initialize_app_context.go`; `cmd/codingbooth/build.go` for `build` |
| Engine on every call | `DockerFlags.Engine` / `binary()` in `pkg/docker/docker.go` |
| `--format docker` | `needsPodmanBuildFormat` in `pkg/docker/docker.go`, `docker_build.go` |
| `--userns=keep-id`, low-port sysctl | `podmanUserNamespaceArgs`, `podmanLowPortArgs` in `pkg/booth/booth.go`; `exportUserNamespaceArgs` in `pkg/lifecycle/home_volume.go` |
| `booth--expose` tunnel exec | `tunnelExecCommand` in `pkg/booth/tcp_tunnel.go` |
| `expose list` live ports | `readLivePorts` in `pkg/lifecycle/expose.go` |
| Host check skip | `HostCheckOptions.Engine` in `pkg/docker/host_check.go` |
| Commands without a context | `resolveLifecycleEngine` / `resolveLifecycleEngines` in `pkg/lifecycle/lifecycle.go` |
| Both-engine lookup | `ResolveEnginesForPath` in `pkg/appctx/engine.go`; `managedContainersAcross`, `managedContainer.Engine`, `ambiguousEngineError` in `pkg/lifecycle/lifecycle.go` |
| TUI field | `engine` in `pkg/boothinit/tui/configfields.go` |
| `--dind` + Podman warning | `resolveEngineConfig` in `pkg/booth/init/initialize_app_context.go` |
| Engine-named user hints (`stop`, DinD `stop`/`network rm`/`logs`, `--persist-home` reclaim) | `engineOrDocker` in `pkg/booth/booth.go`, used from `runAsDaemon`, `printHomeVolumeWarning`, and `waitForDindReady` in `dind_setup.go` |
| Engine-named build-failure banner | `DockerBuild` in `pkg/docker/docker_build.go` (`flags.binary()`) |
| Silent-build stream capture per engine (both stdout+stderr on Podman) | `DockerBuild` in `pkg/docker/docker_build.go` |
| Buildah-format live progress parser | `parsePodman`, `podmanStepRe`/`podmanCacheRe`/`podmanCommitRe` in `pkg/docker/build_progress.go` |

---

# Part 2 — Plan (not implemented)

Everything below is **not built**. Each phase is meant to end in something a user can
run and see.

## Why this is feasible

The CLI only shells out to the `docker` binary (no Engine API or Go SDK dependency), and
almost every call already goes through one package, `cli/src/pkg/docker/`. What differs
between the engines is mostly CLI-flag compatibility, Buildah's build behavior, rootless
user-namespace mapping, and nested containers.

## Phase 1 — done

See [Part 1](#part-1--implemented-phases-13). It delivered slightly less than planned in
one place: the plan said `stop`/`restart`/`rm` would accept `--engine`; they follow
`CB_ENGINE` instead — and, when none is set, look at both engines (see
[Finding booths on either engine](#finding-booths-on-either-engine)).

## Phase 2 — done

See [Part 1](#part-1--implemented-phases-13). `tcp_tunnel.go`'s `exec` call and
`expose list`'s `port` lookup now use the chosen engine.

## Phase 3 — done

See [Part 1](#part-1--implemented-phases-13). Delivered more than planned: the plan
assumed only a missing live-progress line, but Buildah's `STEP`/`RUN` output turned out
to land on stdout, which the silent build path never captured — so `--silence-build` did
not actually silence a Podman build at all. Both are fixed: `build_progress.go` gained a
Buildah-format parser, and `docker_build.go` now captures Podman's stdout too.

## Phase 4 — Docker-in-Docker parity (design first)

The `docker:dind` sidecar with `DOCKER_HOST=tcp://localhost:2375`
(`dind_setup.go`, `docs/implementations/DIND.md`) has no drop-in Podman equivalent —
Podman is daemonless and rootless by default. This phase starts with a design decision
before any code.

**User-visible:** the `dind` tool, `docker-compose` and Appwrite either work under a
Podman-run booth, or fail with a clear "not supported with Podman yet" message instead
of trying and failing confusingly.

## Phase 5 — Release pipeline on Podman

Podman/Buildah equivalents (`podman build --platform`, `podman manifest`) for
`build/docker-build.sh`'s buildx multi-arch build and push.

**User-visible:** maintainers can publish multi-arch images with Podman.

## Phase 6 — Test and CI parity

A Podman variant of `tests/wrapper/` (nested `dockerd` has no Podman analogue) and a CI
job that runs the existing suites against Podman.

**User-visible:** a CI check that backs "Podman is supported" instead of "should work".

## Remaining verification (incremental)

Not done. Each item is picked up on its own, and moves into the verification table in
Part 1 only once it has actually been run:

- [ ] **Rootful Podman** — run, build, lifecycle and `--public` with the CLI as root (the
  `--userns=keep-id` and low-port logic assume this case needs neither; unproven).
- [ ] **macOS and Windows** (`podman machine`) — nothing has been run there, including how
  the `euid` check behaves.
- [ ] **SELinux hosts** — bind mounts may need `:Z`, which CodingBooth does not add.
- [ ] **Podman older than 5.x** — only 5.4.2 has been tried; decide and document a minimum
  version.

## Follow-ups to Phase 1 (unscheduled)

- Let `shell`, `exec` and `home-volume-*` find a booth on either engine too (they can
  create booths or hold engine-local volumes, so they need a rule for which engine wins).
- Add automated Podman coverage for `--egress` and `--public`.
- Print the experimental warning once per invocation, not once per spawned process.

## Open questions

- Podman as a *Boothfile compilation target* (emitting Containerfiles / Buildah scripts)
  is a separate, deferred idea — see `docs/plans/Boothfile--improvement.md`.
- Whether the `docker-compose` / Appwrite setups *inside* a booth image need a
  Podman-in-booth variant. That is independent of the host engine.
