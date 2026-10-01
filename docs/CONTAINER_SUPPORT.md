# Apple Container Support

Status: **experimental.** Docker is the supported container engine; Podman is
experimental too (see [PODMAN_SUPPORT.md](PODMAN_SUPPORT.md)). This document covers
**Apple container** — Apple's [`container`](https://github.com/apple/container) runtime,
the macOS-native one that runs each Linux container in its own lightweight VM — which
CodingBooth calls the **`apple`** engine.

It has two parts, kept apart on purpose:

1. **[Implemented](#part-1--implemented-tiers-01)** — what ships today, as built and as
   verified.
2. **[Plan](#part-2--plan-not-implemented)** — what is not built yet, in the order to
   build it.

Tier 0 (the go/no-go spike) and Tier 1 (a minimum usable booth) are done. Tiers 2–4 are
the plan.

## Decisions

| Question | Decision |
| --- | --- |
| Engine value | **`apple`**. The CLI it runs is `container`, but `container` is *not* an engine value — `--engine container` is rejected. Docs and help call it "Apple container". |
| Discovery when no engine is chosen | **Show all** — `booth list` and friends will query every installed engine. Not built yet: [Tier 2, item 8](#tier-2--everyday-parity). |
| Default engine | Unchanged: `docker`. `apple` is never picked implicitly. |
| Status | Experimental, with the same unconditional stderr warning Podman gets. |

---

# Part 1 — Implemented (Tiers 0–1)

## Choosing the engine

`engine` is an ordinary setting, resolved like it is for Podman.

| Way | Example |
| --- | --- |
| CLI flag | `booth --engine apple` (also `booth build --engine apple`) |
| Environment | `CB_ENGINE=apple booth` |
| Project config | `engine = "apple"` in `.booth/config.toml` |
| Config TUI / CLI | `booth config` ("Container Engine" field), or `booth config . --no-tui --set engine=apple` |

Values are `docker`, `podman` and `apple` (case-insensitive). Anything else — including
the binary name `container` — is rejected:
`❌ invalid engine "container" (supported: docker, podman, apple)`.

Choosing `apple` prints, on stderr and not hidden by `--quiet`:

```
Warning: --engine apple (Apple container) is experimental and may not have full Docker feature parity yet. See docs/CONTAINER_SUPPORT.md.
```

**For `list`, `stop`, `start`, `restart`, `remove`, `prune`, `shell`, `exec`, set
`CB_ENGINE=apple`** (or `engine = "apple"` in the project's config and pass `--code`).
Until [item 8](#tier-2--everyday-parity) lands, the both-engines lookup only covers Docker
and Podman, so without it those commands will not see Apple container booths.

From inside a booth, `BOOTH_ENGINE=apple`.

## How it works

Apple container's CLI is not Docker-compatible, so a binary swap (how Podman works) is not
enough. Every engine call already goes through `docker.Docker` / `docker.DockerOutput`;
when the engine is `apple`, those hand the Docker-style call to
`cli/src/pkg/docker/apple_engine.go`, which rewrites it. Call sites are unchanged.

| Docker call | On Apple container |
| --- | --- |
| `ps [-a] [--filter …] [--format …]` | `container ls --all --format json`, filtered and formatted in Go. Filters: `name` (regex, with or without Docker's leading `/`), `id`, `label`, `status`; any other filter is an error. |
| `inspect [--format …] <name>` | `container inspect`, reshaped into the Docker fields the CLI reads (`Name`, `State.Status`, `Config.Labels`, `NetworkSettings.Ports`, `HostConfig.PortBindings`, …) so `{{json .}}` and `{{index .Config.Labels "…"}}` work as before. A stopped container's state reads `exited`, as in Docker. |
| `port <name>` | Built from `inspect`'s published ports: `10000/tcp -> 127.0.0.1:10077`. |
| `image inspect` / `pull` | `container image inspect` / `container image pull`. |
| `volume ls` | `container volume list --format json`, filtered and formatted in Go. Other `volume` subcommands pass through. |
| `stop --timeout N` | `container stop --time N` |
| `start -ai` | `container start -a -i` |
| `restart` | `container stop`, then `container start` (there is no `container restart`). |
| `run` | Flag by flag, up to the image (the image and command are untouched): see below. `--progress none` is added, since the image is already local by then. |
| `build` | `container build`, with Docker's `--pull=false` dropped and `--pull=true` sent as the bare `--pull` switch. `FROM` a local-only tag resolves from Apple container's own image store. |
| `exec`, `rm`, `kill`, `logs`, `volume create/rm` | Passed through — the flags the CLI uses are the same. |

`run` flags:

- **Passed through:** `-i -t -d --rm --name -e --env-file -v --mount -w -p --label -u
  --network --entrypoint --cap-add --cap-drop --shm-size --tmpfs --platform --dns …`
- **Dropped:** the two the CLI adds itself — `--add-host host.docker.internal:host-gateway`
  and `--pull=never` / `--pull=missing`.
- **Refused**, with `❌ <flag> is not supported on engine apple (Apple container)`:
  `--privileged`, `--device`, `--device-cgroup-rule`, `--pid`, `--ipc`, `--userns`,
  `--sysctl`, `--security-opt`, `--group-add`, `--gpus`, `--restart`, `--hostname`,
  `--add-host` (other than the one above), `--pull=always`. These come from user run-args;
  they fail loudly rather than being dropped.
- **Refused up front:** `--dind` and `--egress`, before anything is written or started.

`--dryrun` and `--verbose` print the real `container …` command lines, and user-facing hints
name the binary (`container stop <name>`).

Not affected by the engine: the Linux rootless/userns-remap host check (Docker only), and
Podman's `--userns=keep-id` and low-port sysctl (Podman only).

## Spike findings (Tier 0)

Checked by hand against `container` 1.5.0 on macOS 26 (Apple Silicon), running the
published `base` image through the booth entrypoint:

- **Bind-mounted code (virtiofs) works.** Files `coder` writes land on the host owned by the
  host user. Git (no "dubious ownership") and `sudo` work. The UID/GID the guest *reports*
  for mounted files is unstable (it flips between `0:0` and the host UID), but writes
  succeed either way, because the host side performs them as the host user.
- **Port publishing works** (`-p 127.0.0.1:<host>:10000`).
- **The host is reachable at the network gateway**, `192.168.64.1`.
  `host.docker.internal` does not resolve (see [Known limitations](#known-limitations)).
- **Labels, published ports, state and gateway** are all in `ls` / `inspect` JSON.

## Verification status

- **Go unit tests:** `cli/src/pkg/docker/apple_engine_test.go` (run-flag translation and
  refusals, lifecycle rewrites, `ps`/`inspect`/`port`/`volume ls`/`image inspect` rendering
  against fixture JSON taken from real output, and a fake `container` binary on `PATH` for
  the full `DockerOutput` path); engine resolution in `appctx/engine_test.go` and
  `booth/init/initialize_app_context_engine_test.go`.
- **Dryrun:** `tests/dryrun/test042--engine-apple.sh`.
- **By hand, end to end** on `container` 1.5.0 / macOS 26: a `--daemon --keep-alive` booth
  started, showed in `booth list` (with `CB_ENGINE=apple`), served its UI on the published
  port, ran `booth exec`, survived `restart`, `stop`, `start --daemon`, `stop -f`, and was
  removed; a one-shot `booth -- <command>` ran as `coder` in the mounted folder and was
  cleaned up by `--rm`; `examples/workspaces/empty-example` built its Boothfile image with
  `container build` (from a local-only base tag) and ran a command in it.
- **Interactive, in a real terminal:** `booth --engine apple` in the foreground (the
  default run mode, with a TTY) started `examples/workspaces/empty-example` and worked.
- **No CI**: Apple container needs Apple Silicon and macOS 26.

Not verified yet: `booth shell`, a real image pull through the "not found locally" path,
the `--silence-build` progress line, and `booth build` (the subcommand; the Boothfile build
`booth` runs itself is verified).

## Known limitations

- **Booths are invisible to `list` etc. unless `CB_ENGINE=apple`** — item 8.
- **`host.docker.internal` does not resolve inside the booth.** Use `192.168.64.1`. The
  booth still receives `BOOTH_HOST_NAME=host.docker.internal` — item 9.
- **Separate image store.** Images built or pulled with Docker are not visible. A locally
  built image can be copied across:
  `docker save <image> -o image.tar && container image load -i image.tar`.
- **`--persist-home`, `booth expose`, `--public`, desktop variants, and single-file bind
  mounts are untested.** `--public` probably fails: its TLS proxy binds `:80`, and there is
  no sysctl to let `coder` bind low ports.
- **`--dind` and `--egress` are not supported.**

## Where it lives (for maintainers)

| What | Where |
| --- | --- |
| Engine value, alias rules, warning | `cli/src/pkg/appctx/engine.go` |
| `--dind` / `--egress` refusal | `resolveEngineConfig` in `cli/src/pkg/booth/init/initialize_app_context.go` |
| Engine → binary (`apple` → `container`) | `docker.EngineBinary` in `cli/src/pkg/docker/docker.go` |
| Call translation and JSON rendering | `cli/src/pkg/docker/apple_engine.go` |
| Hook into the executor | top of `Docker` / `DockerOutput` (`docker.go`), `DockerBuild` (`docker_build.go`) |

---

# Part 2 — Plan (not implemented)

Features in the order to build them. Each tier builds on the one before; Tiers 0 and 1 are
done and kept here for the record.

### Tier 0 — Go/no-go spike ✅

| # | Item | Result |
| --- | --- | --- |
| 0 | Run the published `base` image by hand through the booth entrypoint | Go — see [Spike findings](#spike-findings-tier-0). |

### Tier 1 — Minimum usable booth ✅

| # | Item | Result |
| --- | --- | --- |
| 1 | Engine selection (`apple`), warning, `BOOTH_ENGINE` | Done |
| 2 | Query adapter (JSON, filtered in Go) | Done |
| 3 | Run-argument translation | Done |
| 4 | `booth` run, interactive and detached, with `-p` | Done |
| 5 | `booth shell` / `booth exec` | Done (`exec` verified; `shell` not verified by hand) |
| 6 | `stop` / `start` / `restart` / `remove` / `prune` | Done |
| 7 | Image present/pull check | Done (pull path not verified by hand) |

### Tier 2 — Everyday parity

| # | Item | Feasibility | Notes |
| --- | --- | --- | --- |
| 8 | Show booths from all engines: extend the multi-engine lookup (`appctx.ResolveEnginesForPath`) from two engines to three, with the `ENGINE` column and per-booth routing | Medium | Per-booth routing already exists; the "exists on both" error becomes an N-way check. |
| 9 | Host gateway: make `host.docker.internal` resolve | Medium | Read the gateway from `inspect` (default `192.168.64.1`) and add an `/etc/hosts` entry at startup (needs the entrypoint), or pass the IP in `BOOTH_HOST_NAME`. |
| 10 | Home volume (`--persist-home`, `home-volume-*`) | Likely | `volume create --label` and `volume list` JSON are already handled; the named-volume mount itself is untested. |
| 11 | `booth expose` tunnel and `expose list` | Likely | `port` is emulated and `exec -i` works; untested end to end. |
| 12 | Port-conflict diagnosis | Likely | Goes through the emulated `ps` now; untested. |
| 13 | `booth build` | Medium | The Boothfile build during `booth` works (`--pull` translated). Left: the `booth build` subcommand, and the `--silence-build` progress line against real `container build` output (it prints BuildKit's `#N` lines, which the Docker parser reads). |
| 14 | GUI variants (`codeserver`, `desktop-*`, `notebook`) | Likely | Ports only — needs checking. Desktops use `--shm-size`, which is supported. |

### Tier 3 — Hard or blocked

| # | Item | Feasibility | Notes |
| --- | --- | --- | --- |
| 15 | `--egress` | Uncertain | `--cap-add NET_ADMIN` exists, but it also needs user networks (macOS 26+), name resolution between containers, and item 9. |
| 16 | `booth build --push` / multi-arch | Possible | `container image push`; multi-arch via repeated `--arch`. |
| 17 | `--dind` | **Blocked as built** | The sidecar needs `--privileged`. Candidates: `--publish-socket` to forward a host engine's socket, or `--virtualization`. |
| 18 | Host-escape flags | Not supported | Refused (see [How it works](#how-it-works)). |
| 19 | `--public` | Uncertain | Needs a way to bind `:80` as `coder`. |

### Tier 4 — Hardening

| # | Item | Notes |
| --- | --- | --- |
| 20 | Verify the gaps above by hand | `booth shell`, image pull, `--silence-build`, `booth build`. |
| 21 | Complex test for the lifecycle | Skip unless `container` is installed and running; manual only. |
