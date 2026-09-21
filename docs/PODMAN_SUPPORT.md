# Podman Support (proposal)

Status: **proposed, not started.** This document scopes what it would take to run
CodingBooth against Podman as an alternative to Docker, and how the user would
choose between them. No code has been written yet.

## Why this looks feasible

- The CLI only shells out to the `docker` binary via `os/exec` — it never uses
  the Docker Engine API or Go SDK (`cli/go.mod`/`go.sum` have no
  `docker/docker`, `docker/cli`, or `docker/compose` dependency). Nothing
  depends on Docker's wire protocol, only on CLI flag/argument compatibility.
- Nearly all docker invocations (~60+ call sites) already funnel through one
  package, `cli/src/pkg/docker/`, via four functions: `Docker()`,
  `DockerOutput()`, `DockerBuild()`, `DockerBuildAndPush()`.
- There is no hardcoded Docker version check or `exec.LookPath("docker")`
  preflight anywhere — failures are just generic "binary not found" errors, so
  there's nothing to un-gate for a second engine.

## How the user chooses: `engine`

The engine choice follows the exact same settings pattern already used for
`--sudo`, `--egress-mode`, etc. — no new mechanism is introduced.

- **New `AppConfig` field** (`cli/src/pkg/appctx/app_config.go`):
  `Engine string` tagged `toml:"engine,omitempty"` and `envconfig:"CB_ENGINE"`,
  with a struct-tag default of `docker`.
- **CLI flag**: `--engine docker|podman`, parsed alongside the existing flags
  in `initialize_app_context.go`.
- **Env var**: `CB_ENGINE=podman`, following the established `CB_*` convention
  (parsed via `envconfig.Process`, same path as `CB_DRYRUN`/`CB_SUDO`).
- **Per-project config file**: `engine = "podman"` in `.booth/config.toml`,
  same TOML struct as every other setting.
- **Precedence**: identical to every other AppConfig field — CLI flag > TOML
  config file > env var > default (`docker`). No special-casing needed (the
  `dryrun`/`verbose`/`config`/`code` early-capture behavior does not apply
  here).
- **`booth config` TUI**: exposed as a cycle field, the same widget already
  used for `egress-mode` — `Options: []string{"", "docker", "podman"}` added
  to the `fieldDisplays` table in `pkg/boothinit/tui/configfields.go`. This
  automatically wires it into the TUI, `--set engine=podman`, and save/reload,
  since that table drives `ConfigKeys()`/`RenderedConfigKeys()` generically.
- **Reaching `pkg/docker`**: `DockerFlags` (or equivalent) gains an `Engine`
  field, read at each call site the same way `Dryrun`/`Verbose` are today, and
  the 5 hardcoded `"docker"` literals in `docker.go` (3x `exec.Command`, 2x
  `printCmd`) become `flags.Engine`.

No general auto-detection is planned — an explicit `--engine`/`CB_ENGINE`/
config-file choice always wins, and the default stays `docker`, to avoid
silently changing behavior for existing users. The one narrow exception:
**if the engine was never explicitly set and the default (`docker`) binary
isn't on PATH but `podman` is, fall back to `podman` automatically.** Without
this, a machine that only has Podman installed would see CodingBooth as
simply broken (`docker: executable file not found`) with no hint that
`--engine podman` exists — the whole point of adding support. The fallback
is resolved once (not re-checked per `docker` call) and never overrides an
explicit choice.

When it fires, it prints one line, gated by the same `--quiet`/`CB_QUIET`
convention already used for the DinD/egress sidecar notices (`booth.go`):

```
⚠️  docker not found — using podman instead (experimental; --engine docker to force)
```

### Feature parity disclaimer

Podman support is new and not expected to have full feature parity with
Docker for a while (see the phase list below — DinD, build progress UX, and
the release pipeline are all later-phase work). This is surfaced in three
places, all short:

- **This doc** — this section.
- **`--help`** — the `--engine` flag's help line notes "podman is
  experimental — see docs/PODMAN_SUPPORT.md", next to the other flag
  descriptions in `cmd/codingbooth/help.go`.
- **Runtime warning** — whenever the resolved engine is `podman` (whether
  explicitly chosen or via the PATH fallback above), print once, modeled on
  the existing unconditional `--persist-home is experimental` warning in
  `booth.go` (i.e. *not* gated by `--quiet` — this one disclaimer is a
  "know your risks" notice the user should see even in quiet mode):

  ```
  Warning: --engine podman is experimental and may not have full Docker feature parity yet. See docs/PODMAN_SUPPORT.md.
  ```

  In the fallback case, the two messages would otherwise say almost the same
  thing twice — so the fallback line above absorbs the parity caveat itself
  and the separate unconditional warning is skipped when the engine was
  auto-fallen-back rather than explicitly requested.

### Podman-specific behavior worth knowing

- **Rootless UID mapping.** Rootless Podman maps the host user to container
  *root*, which would leave bind-mounted files (and `.booth/.tmp`, where the
  shutdown/restart markers live) unwritable by the in-container `coder` user.
  For a non-root host user, `booth run` therefore adds `--userns=keep-id
  --user root` so the host UID maps to the same UID inside. Rootful Podman and
  Docker are unaffected.
- **Builds use `--format docker`.** Buildah's default OCI image format silently
  ignores the Dockerfile `SHELL` directive, which every shipped Dockerfile
  relies on (`bash -o pipefail`). The build wrapper adds `--format docker` for
  Podman.
- **`booth list/stop/start/restart/remove/prune` pick the engine from
  `CB_ENGINE` (or `.booth/config.toml` where a `--code` is available), not from
  `--engine`.** With both engines installed and nothing set they look at Docker,
  so run `CB_ENGINE=podman booth stop` for a booth started with `--engine podman`
  (or set `engine = "podman"` in `.booth/config.toml`).
- **Rootless Podman needs `/etc/subuid` and `/etc/subgid` entries** for your
  user (`sudo usermod --add-subuids ... --add-subgids ...`, then
  `podman system migrate`); without them image layers cannot be unpacked.

## Phases

Each phase ends with something a user can actually run and observe — no phase
ships as "plumbing only."

### Phase 1 — Core lifecycle + dryrun/verbose on Podman
Add the `engine` setting (flag/env/config/TUI, as above) and thread it through
`pkg/docker`. Fix the handful of bypass call sites that run outside the
`pkg/docker` wrapper but are used in ordinary lifecycle regardless of DinD:
`dind_setup.go`'s `cleanupPreviousBoothInstances()`/port-conflict helpers, and
`connect.go`'s root-exec and UID-wait calls. Update `print_cmd.go` so
`--dryrun`/`--verbose` print the correct `podman ...` command line.

**User-visible:** `booth run/connect/stop/restart/rm --engine podman` (or
`CB_ENGINE=podman`) works end-to-end on a basic booth with no Docker daemon
involved, and `--dryrun`/`--verbose` show accurate Podman commands from day
one.

### Phase 2 — `booth expose` on Podman
Fix `tcp_tunnel.go`'s direct `docker exec ... socat` call to go through the
engine abstraction.

**User-visible:** `booth expose` (port tunneling) works on a Podman-run booth.

### Phase 3 — Build progress UX on Podman
`build_progress.go` currently parses BuildKit's specific `#N` vertex progress
format; Podman/Buildah's build output differs. Adapt (or add a
format-specific parser) so live build progress renders correctly instead of
silently falling back.

**User-visible:** `booth build`/`config` on Podman shows real live progress
output during image builds, not just "it eventually finishes."

### Phase 4 — DinD / nested-docker parity (design-first)
The `docker:dind` sidecar + `DOCKER_HOST=tcp://localhost:2375` model
(`dind_setup.go`, `docs/implementations/DIND.md`) has no drop-in Podman
equivalent — Podman is rootless/daemonless by default with a different
nesting story. This phase starts with a design decision (in the same spirit
as the paused DinD/privileged consent-gate decision) before any code is
written.

**User-visible:** templates/tools that need Docker-inside-the-booth (the
`dind` tool, `docker-compose` setup, Appwrite stack) either work under a
Podman-run booth, or fail with a clear, documented "not supported with Podman
yet" message instead of a confusing error.

### Phase 5 — Release pipeline on Podman
Podman/Buildah equivalents (`podman build --platform`, `podman manifest`) for
`build/docker-build.sh`'s buildx-based multi-arch build+push.

**User-visible:** maintainers can cut and publish official multi-arch
CodingBooth images using Podman instead of Docker buildx.

### Phase 6 — Test/CI parity
A Podman variant of `tests/wrapper/` (nested `dockerd` has no direct Podman
analog — rootless Podman is daemonless) and a CI matrix leg running the
existing suites against Podman.

**User-visible:** a green "Podman: supported" CI check backing the claim,
not just "should work."

## Out of scope / open questions

- Auto-detecting the engine when `docker` is absent (deferred; see above).
- Podman as a *Boothfile compilation target* (generating Containerfiles /
  Buildah scripts) — already noted as a deferred idea in
  `docs/plans/Boothfile--improvement.md`, but a distinct feature from
  choosing the runtime engine the CLI itself shells out to.
- Whether `docker-compose`/Appwrite setups installed *inside* a booth image
  (`variants/base/setups/docker-compose--setup.sh`,
  `appwrite-server--setup.sh`) need a Podman-in-booth variant — orthogonal to
  the host engine choice and not addressed by any phase above.
