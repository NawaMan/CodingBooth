# Podman Support

Status: **experimental.** Docker is the supported container engine. Podman support
is still being developed and **may not have feature parity with Docker** — read
[Known limitations](#known-limitations) before relying on it.

This document has two parts, kept apart on purpose:

1. **[Implemented](#part-1--implemented-phase-1)** — what ships today, as built and
   as verified. Nothing in it is a promise about the future.
2. **[Plan](#part-2--plan-not-implemented)** — what is *not* built: phases 2–6 and
   follow-ups.

Phase 1 (core lifecycle) is implemented. Phases 2–6 are not started.

---

# Part 1 — Implemented (Phase 1)

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
| `booth shell`, `booth exec`, `booth start` | `engine` in the `.booth/config.toml` under `--code`, then `CB_ENGINE`. **Without `--code`, only `CB_ENGINE` is read** (not the current directory's config). |
| `booth list`, `stop`, `restart`, `remove`, `prune`, `home-volume-*`, `message`, `expose list` | `CB_ENGINE` only |

So a booth started with `--engine podman` is stopped with
`CB_ENGINE=podman booth stop` — or set `engine = "podman"` in its config and pass
`--code` where the command has one. Unset, these commands look at Docker and will not
see a Podman booth.

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
`ps`/`inspect`/`exec`/`stop`/`rm`/`restart`/`start`, `volume`, `network`, the container
lookup used to diagnose a port conflict, and the sidecar clean-up done before a run.
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
- **Docker's host check is skipped.** The Linux rootless-Docker / userns-remap refusal
  and the "Docker daemon not reachable" check describe how *Docker* maps the host user,
  so they do not run for Podman.
- **Errors name the engine that failed** (`podman restart failed with exit code 125`).
  Docker's messages are unchanged.
- **`restart` passes `--time`** — `podman restart` has no `--timeout`.
- **Port-conflict help** looks up the container holding a port with the chosen engine;
  the "orphaned docker-proxy" hint is Docker-only.

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
installed, on 2026-09-21:

| Area | Result |
| --- | --- |
| Build the real 55-step `variants/base` image and a full example project (JDK + tool setups) | works |
| `booth` run (foreground and `--daemon`), port mapping, files owned by the host user | works |
| Shut down from inside the booth (`booth--shutdown`) | works |
| `list`, `stop`, `start`, `restart`, `remove` (with `CB_ENGINE=podman`) | work |
| `prune` (nothing stale to prune in the test) | ran without error |
| `exec --name …`, and `exec --run` (creates the booth, runs, tears it down) | work |
| `booth build --engine podman` (real build) | works |
| `--persist-home`: labelled volume created, `coder` can write it, data survives a restart | works |
| `home-volume-list`, and a `home-volume-export` → `home-volume-import` round trip (data read back) | work |
| Interactive `booth shell` (driven through a real pty) | works |
| `message send` reaches the booth | works |
| A restart requested from *inside* a foreground booth (`booth--restart`): the CLI relaunches a fresh container, and a later shutdown ends the CLI | works |
| `--public`: HTTPS answers 302 and plain HTTP 400 — the same as a Docker control run | works (after the low-port fix) |
| `--egress`: proxy and netns sidecars start; an allowlisted host connects, a non-allowlisted one is blocked | works (checked by hand only) |
| Engine selection: flag, config, `CB_ENGINE`, precedence, `booth config --set`, fallback, `--quiet`, invalid value | works |

Automated: Go unit tests (`pkg/appctx/engine_test.go`, `pkg/docker/engine_test.go`,
`pkg/docker/host_check_test.go`, `pkg/booth/podman_userns_test.go`,
`pkg/booth/init/initialize_app_context_engine_test.go`,
`pkg/lifecycle/restart_flag_test.go`), the config-TUI schema guard, and
`tests/dryrun/test036--engine.sh` (15 checks, no engine needs to be installed).
**No CI job runs against Podman** — see Phase 6.

**Not verified on Podman:** the live-port column of `expose list` (still calls `docker`);
rootful Podman; macOS/Windows (`podman machine`); Podman older than 5.x; SELinux hosts
(bind mounts may need `:Z`, which CodingBooth does not add); `--dind` (unsupported).
`--egress`, `--public` and `--persist-home` were checked by hand once and have no
automated Podman test. After `booth stop` on an `--egress` booth the sidecar containers
go away (a moment later, as Podman removes them) but the egress network is left behind.

## Known limitations

- **Docker-in-Docker is not supported.** `--dind`, and anything that needs Docker inside
  the booth (the `dind` tool, `docker-compose`, Appwrite), rely on the `docker:dind`
  sidecar and `DOCKER_HOST`. `--dind` with `--engine podman` is **not blocked** — it will
  try, and is unsupported and untested.
- **`booth expose` tunnels do not work on Podman**, and `expose list` cannot see live
  ports (both still call `docker`).
- **Lifecycle commands do not take `--engine`** (table above), and each looks at one
  engine only, so there is no combined view of Docker and Podman booths.
- **No live build-progress line.** The single status line shown by `--silence-build`
  parses BuildKit's output format; on Podman the build output is captured and shown only
  on failure, like Docker's but without the live line.
- **The release pipeline, `tests/wrapper/` and CI are Docker-only.** Images are built
  and published with Docker/buildx.
- **Separate image stores.** Podman cannot see images Docker built or pulled, and the
  reverse; `--pull=never` runs need the image in the engine you chose.
- The silent-build failure banner still reads "❌ Docker build failed!" (the error that
  follows names the right engine).

## Where it lives (for maintainers)

| Piece | Location |
| --- | --- |
| Resolution + fallback + warnings | `cli/src/pkg/appctx/engine.go` (`ResolveEngineValue`, `ResolveEngineForPath`) |
| `engine` setting, accessor | `AppConfig.Engine` (`CB_ENGINE`), `AppContext.Engine()` |
| `--engine` parsing and validation | `pkg/booth/init/initialize_app_context.go`; `cmd/codingbooth/build.go` for `build` |
| Engine on every call | `DockerFlags.Engine` / `binary()` in `pkg/docker/docker.go` |
| `--format docker` | `needsPodmanBuildFormat` in `pkg/docker/docker.go`, `docker_build.go` |
| `--userns=keep-id`, low-port sysctl | `podmanUserNamespaceArgs`, `podmanLowPortArgs` in `pkg/booth/booth.go`; `exportUserNamespaceArgs` in `pkg/lifecycle/home_volume.go` |
| Host check skip | `HostCheckOptions.Engine` in `pkg/docker/host_check.go` |
| Commands without a context | `resolveLifecycleEngine` in `pkg/lifecycle/lifecycle.go` |
| TUI field | `engine` in `pkg/boothinit/tui/configfields.go` |

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

See [Part 1](#part-1--implemented-phase-1). It delivered slightly less than planned in
one place: the plan said `stop`/`restart`/`rm` would accept `--engine`; they follow
`CB_ENGINE` instead (see follow-ups).

## Phase 2 — `booth expose` on Podman

Route `tcp_tunnel.go`'s direct `docker exec … socat` call, and `expose list`'s
`docker port` lookup, through the chosen engine.

**User-visible:** `booth expose` (port tunnelling) and `expose list` work on a
Podman-run booth.

## Phase 3 — Build progress on Podman

`build_progress.go` parses BuildKit's `#N` progress format; Buildah's output differs.
Adapt or add a parser so `--silence-build` shows a live status line on Podman.

**User-visible:** `booth build` / `config` on Podman shows live progress.

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

## Follow-ups to Phase 1 (unscheduled)

- Let `list`/`stop`/`start`/`restart`/`remove`/`prune` see Podman booths without
  `CB_ENGINE` — accept `--engine`, or query both engines and remember which one owns each
  container.
- Refuse or clearly warn on `--dind` when the engine is Podman (Phase 4 covers it fully).
- Verify the paths listed under "Not verified", above all rootful Podman and SELinux
  hosts, and add automated Podman coverage for `--egress`, `--public` and `--persist-home`.
- Print the experimental warning once per invocation, not once per spawned process.
- Make the "❌ Docker build failed!" banner name the engine.

## Open questions

- Should the engine be recorded on the container (a label) so lifecycle commands can find
  the right engine themselves?
- Podman as a *Boothfile compilation target* (emitting Containerfiles / Buildah scripts)
  is a separate, deferred idea — see `docs/plans/Boothfile--improvement.md`.
- Whether the `docker-compose` / Appwrite setups *inside* a booth image need a
  Podman-in-booth variant. That is independent of the host engine.
