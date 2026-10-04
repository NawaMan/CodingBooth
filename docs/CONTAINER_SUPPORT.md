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

Tier 0 (the go/no-go spike) and Tier 1 (a minimum usable booth) are done, and so is most of
Tier 2. The rest of Tiers 2–4 is the plan.

## Decisions

| Question | Decision |
| --- | --- |
| Engine value | **`apple`**. The CLI it runs is `container`, but `container` is *not* an engine value — `--engine container` is rejected. Docs and help call it "Apple container". |
| Discovery when no engine is chosen | **Show all** — `booth list` and friends query every installed engine. See [Finding booths](#finding-booths). |
| Default engine | **`apple` first** when Apple container is installed and its service is running, then `docker`, then `podman`. See [When you choose nothing](#when-you-choose-nothing). |
| Status | Experimental, with the same unconditional stderr warning Podman gets. |
| `--dind` / `--egress` | **Not supported, deferred.** Refused on `apple`; with no engine chosen such a run goes to Docker or Podman. See [Not supported](#not-supported---dind-and---egress). |

---

# Part 1 — Implemented (Tiers 0–1, most of Tier 2)

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

### When you choose nothing

With no flag, no `CB_ENGINE` and no `engine =` in the config, the engine is picked in this
order:

1. **`apple`**, when `container` is on `PATH` **and** its service is running
   (`container system status`). A run picked this way prints, on stderr and hidden by
   `--quiet`:
   ```
   ℹ️  Using Apple container (experimental; --engine docker to force Docker). See docs/CONTAINER_SUPPORT.md.
   ```
2. **`docker`**, when it is on `PATH`.
3. **`podman`**, when it is on `PATH` (with Podman's own one-line notice).
4. **`apple`** again when `container` is the only engine installed but its service is
   stopped, so the error you see is Apple container's own (start it with
   `container system start`).
5. Otherwise `docker`, and the run fails because no engine is installed.

An installed but **stopped** Apple container is passed over (step 1), so a Mac that also has
Docker keeps working on Docker until `container system start`.

A run with **`--dind` or `--egress`** skips step 1: Apple container cannot start the sidecars
they need, so the run goes to Docker (or Podman) instead of being refused. With an explicit
`--engine apple` they are still refused.

Things to know when Apple container becomes your default:

- **Separate image store.** Images built or pulled with Docker are not visible, so the first
  run of each image pulls or rebuilds it.
- **A Docker booth is not reused.** `booth` in a project whose booth is running on Docker
  starts a second one on Apple container. `booth list` shows both (with an `ENGINE`
  column); pass `--engine docker` (or set `engine = "docker"` in the project's config) to keep
  a project on Docker.
- **Test suites pin `CB_ENGINE=docker`** (`tests/common--source.sh` and the suite runners),
  so their results do not depend on what is installed. Set `CB_ENGINE=apple` to run a
  suite on Apple container on purpose.

### Experimental warning

Choosing `apple` explicitly prints, on stderr and not hidden by `--quiet`:

```
Warning: --engine apple (Apple container) is experimental and may not have full Docker feature parity yet. See docs/CONTAINER_SUPPORT.md.
```

From inside a booth, `BOOTH_ENGINE=apple`.

## Finding booths

With no engine chosen (no `CB_ENGINE`, no `engine =` in the config), `list`, `stop`, `start`,
`restart`, `remove`, `prune`, `message`, `expose list`, `shell` and `exec` query **every
installed engine** — `docker`, `podman`, and `apple` when the `container` binary is on
`PATH` — and act on the engine that owns the booth. `booth list` then adds an `ENGINE` column. A name that exists on more than
one engine is refused (`booth "web" exists on apple, docker and podman. Set CB_ENGINE=<engine>
to choose one.`).

An installed Apple container whose service is not started (`container system start`) is skipped
**without a warning**: it holds no running booths, and a Docker user who merely has `container`
installed should not see a warning on every `booth list`. Once the service is up, a failure to
list it is reported like any other engine's.

**`shell` and `exec`** find the booth the same way (by name, or by `--code`), and run on the
engine that owns it. With `--run`, a booth that exists nowhere is created by `booth run` on the
[default engine](#when-you-choose-nothing), and they connect to it on whichever engine it landed.

## Sizing the booth's VM (`--vm-memory`, `--vm-cpus`, `--vm-shm-size`)

### In short

On a Mac with **Apple container**, every booth runs in its own small virtual machine (VM), and
that VM has a fixed amount of memory:

- **A Linux desktop booth gets 4 GB by itself.** KDE, XFCE, LXQt and Wayland ask for it — no
  setting needed.
- **Every other booth gets Apple container's default, 1 GB.** Enough for a terminal or a code
  server; raise it for anything heavy.
- **You can choose the amount** with `--vm-memory`, `CB_VM_MEMORY`, `vm-memory` in
  `.booth/config.toml`, the Config TUI, or the `vm-memory` template.

This only concerns **Apple container**. With Docker Desktop or Podman — on a Mac or anywhere
else — a booth simply shares the engine's memory, there is no per-booth VM, and all of these
settings are ignored (with a one-line note).

### What happens by default

| Booth | Memory | CPUs | `/dev/shm` |
| --- | --- | --- | --- |
| Desktop variant (`desktop-kde`, `desktop-xfce`, `desktop-lxqt`, `desktop-wayland`), or an image built `FROM` one | **4 GB** — the image asks for it | 4 | 1 GB |
| Any other booth | 1 GB (Apple container's default) | 4 | Apple container's default |

When a desktop gets its 4 GB this way, the run says so:

```
ℹ️  Giving the booth's VM 4g of memory, the minimum the desktop-kde image asks for (--vm-memory to change).
```

### Choosing the amount

Any one of these — they follow the usual precedence, **flag > `config.toml` > environment
variable**:

| Way | Example | Scope |
| --- | --- | --- |
| Command-line flag | `booth --vm-memory 8g` | this run |
| Project config | `vm-memory = "8g"` in `.booth/config.toml` | this project |
| Environment variable | `CB_VM_MEMORY=8g booth` | this shell |
| Config TUI | **VM Memory** field in `booth config` | writes `config.toml` |
| Template | `booth config --select vm-memory:8g` (category **Booth VM (macOS)**) | writes `config.toml` |

Sizes are written like `512m`, `4g`, `4096m` or `2048mb`; an invalid value stops the run with a
clear message before anything starts. An explicit value always wins over the 4 GB a desktop asks
for — higher or lower.

**Below the minimum.** Setting less than an image asks for is allowed (you may know your
workload), but the run warns, because a desktop starved of memory makes the whole VM thrash —
the browser shows *Reconnecting to the booth…*, then *Booth stopped*, and even `container exec`
hangs:

```
Warning: vm-memory 2g is below the 4g this image needs (desktop-kde); the booth may stop responding.
```

**How much is enough?** A KDE desktop with Firefox, VS Code and a terminal open peaked at about
2.1 GB, so 4 GB leaves headroom. Heavier work — large builds, several browsers — wants 8 GB.

### CPUs and shared memory

Same mechanism, same ways to set them:

| Setting | Flag | Env | `config.toml` | Template | Default on Apple container |
| --- | --- | --- | --- | --- | --- |
| CPUs | `--vm-cpus 6` | `CB_VM_CPUS` | `vm-cpus = "6"` | `--select vm-cpus:6` | 4 |
| `/dev/shm` | `--vm-shm-size 2g` | `CB_VM_SHM_SIZE` | `vm-shm-size = "2g"` | `--select vm-shm-size:2g` | 1 GB for desktops |

`/dev/shm` is shared memory that browsers, Electron apps and desktops use heavily. On Apple
container it comes **out of the VM's memory**, so keep it well below `vm-memory`.

### For image authors: asking for a minimum

An image declares the memory its booths need with a label; the desktop variants carry:

```dockerfile
LABEL com.codingbooth.vm-memory-min="4g"
```

Images built `FROM` a labelled image inherit it, so a project's Boothfile on a desktop variant
gets the same 4 GB. Any image may set it. On engine `apple` the CLI reads it before starting and
uses it when no `vm-memory` is set; Docker and Podman ignore it. A desktop image built before the
label existed gets this warning instead of the automatic 4 GB:

```
Warning: the desktop-kde variant on Apple container gets its VM's default 1 GB of memory, which a desktop outgrows (KDE uses ~700 MB idle). Add --vm-memory 4g.
```

### Background

Apple container's defaults come from `container system property list` (`[container]`:
`memory = "1gb"`, `cpus = 4`); container 1.5.0 can list them but not change them, so CodingBooth
sizes each booth's VM instead. The settings become `container run --memory / --cpus /
--shm-size`.

Verified on container 1.5.0 / macOS 26:

- `--vm-memory 4g --vm-cpus 6` gave a 4096 MB, 6-CPU VM (`free` 4047 MB, `nproc` 6 inside).
- A KDE booth with no setting got 4096 MB from the label, and stayed up for two minutes with
  Firefox, VS Code and Konsole open and a viewer connected (peak 2.1 GB used, no
  out-of-memory kills).
- An image built `FROM` a labelled KDE image got 4096 MB too; `--vm-memory 2g` kept 2048 MB, with
  the warning.

## Single-file mounts

Apple container (`container` 1.5.0) has a mount bug: **mounting a single file drops the mount of
the folder that directly contains it**, when that folder is mounted too. The folder then goes
missing in the container — or, when another mount shows the same content, silently loses its
`:ro`. Mounting a file from a folder that is *not* itself mounted (even one deeper inside a
mounted folder) is fine.

CodingBooth hit this itself: it mounts the project's `booth` wrapper read-only over the project
folder, and the wrapper lives directly in that folder — so every project with a wrapper got an
empty `/home/coder/code`. On engine `apple` the wrapper is now mounted from a copy kept outside the
project, at `$XDG_CACHE_HOME/codingbooth/apple-wrappers/<project>/booth` (`~/.cache/…` when unset),
refreshed on every run and still read-only.

For any other mount of this shape — usually a `-v` in your `run-args` — the run prints a warning
naming the file and the folder it would lose:

```
Warning: Apple container drops a folder's mount when a file directly in it is mounted too: …
```

Mount the file from another folder to avoid it.

## Reaching the host

Apple container has no `--add-host`, so `host.docker.internal` is not provided by the engine.
The CLI reads the IPv4 gateway of Apple container's `default` network (`container network
inspect default`; `192.168.64.1` if it cannot be read, and always under `--dryrun`) and passes it
twice:

- `BOOTH_HOST_GATEWAY=<gateway>` — `booth-entry` adds `<gateway> host.docker.internal` to
  `/etc/hosts` when the name does not already resolve. Docker and Podman never get this variable,
  so there it is a no-op.
- `BOOTH_HOST_NAME=<gateway>` — the address itself, which works even on an image whose
  `booth-entry` predates the mapping.

So `curl http://host.docker.internal:<port>` works in a booth built from this version on, and
`$BOOTH_HOST_NAME` works on any image. A booth attached to another network with a `--network`
run-arg still gets the `default` network's gateway.

## Ports below 1024 (`--apple-low-ports`)

Docker lets any user in a container open ports below 1024: it sets the kernel's
`net.ipv4.ip_unprivileged_port_start` to `0` in every container. Apple container leaves it at
`1024`, so in an Apple container booth `coder` gets `Permission denied` on `:80` and `:443`.
That includes `--public`, whose TLS proxy (Caddy) binds `:80`, and any app you run there.

CodingBooth does not change that on its own. You ask for it, per booth:

```bash
booth --engine apple --apple-low-ports            # this run
```

or `apple-low-ports = true` in `.booth/config.toml`, or `CB_APPLE_LOW_PORTS=true`. With
`--public` and without the flag, the run warns (`Add --apple-low-ports`); the proxy then
fails to start, as it would anywhere `:80` is not allowed.

**What it grants: `NET_BIND_SERVICE` only** — the Linux permission to open ports below 1024,
and nothing else. Apple container booths already hold it in their permission set; the flag
hands it to `coder`. Nothing is added to the run (no `--cap-add`), `coder` stays a normal user,
and even `sudo` inside the booth cannot raise anything new. The kernel limit itself is not
changed: that needs `SYS_ADMIN`, which is far broader, and which `container exec` sessions
would get back even if it were dropped at startup.

How it reaches `coder`'s processes:

- The CLI passes `BOOTH_LOW_PORTS=true` and labels the booth `cb.apple-low-ports=true`.
- `booth-entry` (root) writes the root-owned marker `/run/booth-low-ports`, and starts every
  `coder` process — startup hooks (where Caddy starts), user startups, the main command — through
  `booth--as-coder`. With the marker, that switches to `coder` with `setpriv` and hands down
  `NET_BIND_SERVICE` as an *ambient* capability, which children inherit (`runuser` would drop
  it). Without the marker it is exactly the `runuser` call `booth-entry` made before, so Docker
  and Podman booths are unchanged.
- `booth shell` and `booth exec` on a labelled booth start the session as root through the same
  helper (or plain `runuser` on an image that predates it).

A raw `container exec` from the host does not go through the helper, so it gets no low ports —
the safe direction. On Docker and Podman the flag is ignored with a one-line note: low ports
already work there. Like the `/etc/hosts` mapping, it needs an image with the current
`booth-entry`.

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
| `push` (`booth build --push`) | `container image push`. The failure hint says `container registry login <host>`. |
| Registry on this machine | `pull`/`push` of a `localhost`, `127.0.0.0/8` or `::1` registry add `--scheme http`: Docker always uses plain HTTP there, Apple container defaults to HTTPS (and fails with `bad protocol version`). |
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

- **Bind-mounted code (virtiofs) works** — though, found later, not alongside a single-file mount
  from the same folder; see [Single-file mounts](#single-file-mounts). Files `coder` writes land on the host owned by the
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

- **By hand, Tier 2** (same machine), with no `CB_ENGINE` set unless noted:
  - `booth list` showed an Apple container booth in the `ENGINE` column next to Docker.
  - `restart`, `stop`, `start --daemon`, `remove --force` and `prune --yes` found it and acted on
    `apple`. `remove` also deleted its home volume.
  - `booth shell` and `booth exec` (with `CB_ENGINE=apple`) worked.
  - Inside the booth, `getent hosts host.docker.internal` gave `192.168.64.1`, and a connection
    to it reached the host.
  - `--persist-home`: a file in `/home/coder` survived deleting and recreating the booth, owned by
    `coder`. `home-volume-list` showed the volume.
  - `booth--expose 8080 18092`: the host read the in-booth server through the tunnel, and
    `booth expose list` showed both the published port and the tunnel.
  - `booth build` built a `.booth/Dockerfile` with `container build`. The `--dockerfile` path
    built one too.
  - `--variant notebook --version 0.79.0`, not present locally, was pulled and started, and its UI
    answered on the published port.
  - A second booth on an already-published port failed with Apple container's
    `Address already in use` error. Docker gives its own raw error for the same case; the
    friendlier port diagnosis exists only for `--dind`, which `apple` does not support.

- **By hand, `--apple-low-ports`** (same machine, image with this `booth-entry`):
  - Without the flag `coder` got `Permission denied` on `:80` and `:443`; with it both opened,
    `coder` held `NET_BIND_SERVICE` and no `SYS_ADMIN`.
  - `booth exec` and `booth shell` sessions in a flagged booth could open `:80`; in a plain
    booth they could not. `sudo` in a flagged booth still had no `SYS_ADMIN`.
  - `--public` with the flag served HTTPS (Caddy's sign-in redirect); without it the run warned
    and Caddy failed with `listen tcp :80: bind: permission denied`.

Not verified yet: the `--silence-build` progress line (it only draws on a terminal), and the
`codeserver` and `desktop-*` variants.

## Not supported: `--dind` and `--egress`

**Decision: not done for now.** Both are deferred until each gets its own design; everything else
on Apple container works without them.

**What happens instead**

- `--engine apple` (or `engine = "apple"`) with `--dind` or `--egress` is **refused up front**,
  before anything is written or started:
  `❌ --dind is not supported on engine apple (Apple container) yet`.
- With **no engine chosen**, a `--dind` / `--egress` run skips Apple container and goes to Docker
  (or Podman) by itself, so those projects keep working on a Mac that has Docker too.

**Why** — both are built on a sidecar container whose network namespace the booth joins
(`--network container:<sidecar>`): the booth reaches the DinD daemon on `localhost`, and egress
filtering sits invisibly in the booth's network path. Each Apple container is its own VM, so there
is no namespace to share; both need a different design, not a port.

**What a later design can build on** — checked by hand on container 1.5.0, not implemented:

- *`--dind`:* a `docker:dind` sidecar runs under Apple container with `--cap-add ALL`, once
  `/proc/sys` is remounted read-write before `dockerd` starts (otherwise it dies setting
  `ip_forward`). Another container on the same user network drove it at `tcp://<sidecar-ip>:2375`
  and ran an inner `nginx`. Containers on a user network cannot find each other by name, so the
  CLI would pass the sidecar's IP. Difference to Docker: an inner container's published ports
  appear at the sidecar's address, not the booth's `localhost` — a port-forwarding question of its
  own.
- *`--egress`:* an `--internal` network really is cut off (no internet, no DNS), and a proxy
  container can join it and `default` at once — so isolation, not a firewall rule, could do the
  enforcing. Open: Envoy as an explicit forward proxy (`HTTPS_PROXY`) instead of today's transparent
  one, DNS inside the isolated booth, whether the booth may still reach the host, and `--dind`
  together with `--egress`.

**Skipped tests.** The suites pin `CB_ENGINE=docker`, so these run normally. They skip — they do
not fail — only in a run made on purpose with `CB_ENGINE=apple`:

| Where | Tests | How |
| --- | --- | --- |
| `tests/basic/` | `test029--host-escape-consent.sh` | `sidecars_supported --dind \|\| exit 0` (`tests/common--source.sh`) |
| `tests/dryrun/` | `test012--config-file--envvars.sh`, `test013--config-file--args.sh`, `test018--config-file--env-expand.sh` (their configs set `dind = true`) | same |
| `tests/dryrun/dind/` | `test001--dind-ports-from-config.sh`, `test002--dind-ports-deduplicated.sh`, `test003--dind-host-gateway.sh` | same |
| `tests/complex/` | `test-egress-allowlist`, `test-egress-allowlist-extra`, `test-egress-envoy`, `test-egress-ro` | `sidecars_supported --egress \|\| exit 0` |
| `examples/workspaces/` | `appwrite`, `dind`, `egress-allowlist-extra`, `egress-envoy`, `floci`, `kind`, `kind-app`, `wails` (`-example`) | `run-example-tests.sh` reads `dind = true` / `egress = true` from the example's `.booth/config.toml` and reports it `skipped — not run, not verified` |

The examples check needs no per-example marker, so a new `--dind` / `--egress` example is covered
by itself; a new test under `tests/` adds the one-line `sidecars_supported` guard.
`tests/dryrun/test042--engine-apple.sh` keeps checking that `apple` *refuses* both. Not affected:
the `tests/config/` tests that only write `dind = true` into a config (they start nothing), and
`tests/wrapper/`, which has its own `--skip-dind`.

## Known limitations

- **`host.docker.internal` needs a current image.** It resolves through `booth-entry`; on an
  older image use `$BOOTH_HOST_NAME`, which holds the gateway address.
- **Separate image store.** Images built or pulled with Docker are not visible. A locally
  built image can be copied across: `docker save <image> | container image load`.
  `build/docker-build.sh` (and so `build/build-all.sh`) does that itself after a local build
  when Apple container is installed and running — `CB_NO_APPLE_COPY=1` skips it. Copy one tag
  per archive (re-tag the rest with `container image tag`): an archive holding two tags of the
  same image fails to load with `File exists`.
- **Ports below 1024 need `--apple-low-ports`**, `--public` included; see
  [Ports below 1024](#ports-below-1024---apple-low-ports).
- **A single-file mount drops the mount of the folder directly containing it** (Apple container
  bug). CodingBooth's own wrapper mount works around it; other such mounts get a warning. See
  [Single-file mounts](#single-file-mounts).
- **`--dind` and `--egress` are not supported** — deferred; see
  [Not supported](#not-supported---dind-and---egress).

## Where it lives (for maintainers)

| What | Where |
| --- | --- |
| Engine value, alias rules, warning | `cli/src/pkg/appctx/engine.go` |
| `--dind` / `--egress` refusal | `resolveEngineConfig` in `cli/src/pkg/booth/init/initialize_app_context.go` |
| Engine → binary (`apple` → `container`) | `docker.EngineBinary` in `cli/src/pkg/docker/docker.go` |
| Call translation and JSON rendering | `cli/src/pkg/docker/apple_engine.go` |
| Hook into the executor | top of `Docker` / `DockerOutput` (`docker.go`), `DockerBuild` (`docker_build.go`) |
| Engines queried when none is chosen | `appctx.ResolveEnginesForPath` (`appctx/engine.go`) |
| Quiet skip of a stopped service | `managedContainersAcross` (`lifecycle/lifecycle.go`), `docker.AppleServiceRunning` |
| Host gateway | `docker.AppleNetworkGateway`; `BOOTH_HOST_*` in `booth/booth.go`; the `/etc/hosts` line in `variants/base/booth-entry` |
| `booth--expose` tunnel binary | `tunnelExecCommand` (`booth/tcp_tunnel.go`) |
| VM sizing | `vmResourceArgs`, `imageVmMemoryMin` (`booth/booth.go`); the label on `variants/desktop-*/Dockerfile`; image labels in the adapter's `image inspect`; template fields `vm-*` and `runtime` params in `boothinit/template`, `boothinit/compiler`; templates in `templates/booth-vm/` |
| Single-file mount bug | `appleWrapperCopy` / `addReadOnlyBoothWrapper` (`booth/booth.go`); the warning, `appleMountConflicts` (`docker/apple_engine.go`) |
| `--apple-low-ports` | `appleLowPortsArgs` / `appleLowPortsNote` (`booth/booth.go`); `coderCommand` (`lifecycle/connect.go`); `variants/base/booth--as-coder` and its marker in `booth-entry` |

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
| 5 | `booth shell` / `booth exec` | Done |
| 6 | `stop` / `start` / `restart` / `remove` / `prune` | Done |
| 7 | Image present/pull check | Done |

### Tier 2 — Everyday parity

| # | Item | Feasibility | Notes |
| --- | --- | --- | --- |
| 8 | Show booths from all engines | ✅ Done | See [Finding booths](#finding-booths). Covers `shell`/`exec` too. |
| 9 | Host gateway: make `host.docker.internal` resolve | ✅ Done | See [Reaching the host](#reaching-the-host). Needs an image with the current `booth-entry`. |
| 10 | Home volume (`--persist-home`, `home-volume-*`) | ✅ Verified | No change needed. |
| 11 | `booth expose` tunnel and `expose list` | ✅ Fixed, verified | The host-side tunnel ran the engine name (`apple`) as a binary; it now runs `container`. |
| 12 | Port-conflict diagnosis | ✅ Same as Docker | An explicit port in use fails with the engine's raw error on both engines. |
| 13 | `booth build` | ✅ Mostly | The subcommand builds. Left: the `--silence-build` progress line on a real terminal (`container build` prints BuildKit's `#N` lines, which the Docker parser reads). |
| 14 | GUI variants (`codeserver`, `desktop-*`, `notebook`) | Partly | `notebook` verified. `codeserver` and the desktops (which use `--shm-size`, supported) are unchecked. |

### Tier 3 — Hard or blocked

| # | Item | Feasibility | Notes |
| --- | --- | --- | --- |
| 15 | `--egress` | **Deferred** | Needs its own design; see [Not supported](#not-supported---dind-and---egress). |
| 16 | `booth build --push` | ✅ Done | `container image push`, plain HTTP for a registry on this machine as Docker does. Verified: pushed to a local registry, and Docker ran the image. Multi-arch is not a `booth build` feature on any engine. |
| 17 | `--dind` | **Deferred** | A sidecar with `--cap-add ALL` works (no `--privileged` needed); see [Not supported](#not-supported---dind-and---egress). |
| 18 | Host-escape flags | Not supported | Refused (see [How it works](#how-it-works)). |
| 19 | `--public` | ✅ With `--apple-low-ports` | See [Ports below 1024](#ports-below-1024---apple-low-ports). |

### Tier 4 — Hardening

| # | Item | Notes |
| --- | --- | --- |
| 20 | Verify the gaps above by hand | Left: `--silence-build` on a terminal. (`booth shell`, image pull, `booth build`, `codeserver` and every desktop variant are done — the desktops once they got 4 GB.) |
| 21 | Complex test for the lifecycle | Skip unless `container` is installed and running; manual only. |
