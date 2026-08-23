# Sandbox Isolation Modes (`--sandbox` / `--sandbox-mode`)

**Status:** Designed, implementation deferred. Tracking sbx maturity via `.github/workflows/sbx-watch.yaml`.

## Context

CodingBooth runs dev environments in Docker containers (shared host kernel: namespaces +
cgroups + seccomp). The `--egress` feature already hardens the *network* boundary. This plan
adds a separate, orthogonal axis: how strongly the *workload* is isolated at the kernel level.

The word "sandbox" was freed up when the old network feature was renamed `sandbox` → `egress`
(commit `09e5a35`). It now correctly means workload isolation, giving a clean pair:

- `--sandbox` → how strongly the workload is isolated (kernel boundary)
- `--egress`  → what the workload's network can reach (traffic boundary)

## Flag surface

Mirrors the existing `--egress` / `--egress-mode` / `--egress-enforcement` convention.

```
--sandbox                      # turn on; auto-selects the strongest available installed mode
--sandbox-mode <mode>          # none | gvisor | sysbox | kata | sbx
CB_SANDBOX / CB_SANDBOX_MODE   # env equivalents
```

Bare `--sandbox` (no mode) is the friendly knob: pick the best mode that is actually installed,
fall back with a clear message if none are. `microvm` was considered as a value but **dropped** —
it is ambiguous (both `kata` and `sbx` are microVMs) and redundant. Concrete impl names only.

## Modes

| Mode | Mechanism | Separate install | KVM? | Keeps host networking? | Integration effort | Status |
|---|---|---|---|---|---|---|
| `none` | runc (today) | — | no | yes | trivial | stable |
| `gvisor` | runsc userspace kernel | runsc + register runtime | no¹ | yes | small (`--runtime=runsc`) | **supported** |
| `sysbox` | syscall-trap + userns + fs emulation | sysbox pkg + register runtime | no | yes | small (`--runtime=sysbox-runc`) | **supported** |
| `kata` | lightweight VM per container | kata pkg + register runtime | yes | mostly | medium (`--runtime=kata`) | **experimental** |
| `sbx` | Docker Sandboxes (own daemon + microVM) | `sbx` CLI (proprietary) | yes | **no — rework** | large (separate launcher) | **experimental** |

¹ gVisor runs without KVM (ptrace/systrap); KVM is an optional speed mode.

`gvisor`/`sysbox`/`kata` are OCI runtimes — they slot into the existing `docker run` path as a
single `--runtime=` arg, inside the current `docker` package abstraction, and preserve the host
daemon (so port mapping, web proxy pane, and TCP tunnel keep working). `sbx` is the outlier: not
a runtime but a separate launcher with its own daemon/netns, which breaks host networking and
needs a rework — hence largest effort and lowest priority.

## Why `sbx` and `kata` are experimental

- **`sbx`** — pre-1.0 (`v0.39.0`, Aug 2026) despite the "GA" framing; actively breaking its CLI
  (`sbx run <name>` → `sbx run --name <name>`, `sbx policy set-default` → `sbx policy init`); still
  fixing core daemon hangs. Six releases landed between v0.33.0 and v0.39.0 without reaching 1.0.
  Since the integration shells out to that CLI, upstream breakage breaks us. Also: don't bundle the
  binary (proprietary, no redistribution grant) — detect + delegate only.
- **`kata`** — the mechanism is mature, but *our* integration (KVM detection + VM networking) is
  unproven. Experimental until validated.

## Detection (all modes: detect → use → else fall back + print install help)

Nothing here ships with Docker; each runtime must be installed and registered with the daemon.

```bash
docker info --format '{{json .Runtimes}}'   # runsc / sysbox-runc / kata present?
command -v sbx                              # sbx CLI on PATH?
```

## Integration seam

Slots into `BoothRunner.Run()` (cli/src/pkg/booth/booth_runner.go) right after `SetupDind` /
`SetupEgress`, as a `SetupSandbox(ctx)` step that injects `--runtime=` into the run args (runtime
modes) or swaps the launcher (sbx). Reuses the `docker` package for runtime modes.

## Notable interactions

- **sysbox + DinD**: sysbox runs Docker-in-Docker **without `--privileged`**. This may unblock the
  currently-banned `--egress` + `--dind` combo (EGRESS.md:184), which is banned precisely because a
  *privileged* DinD container can bypass the iptables egress firewall. Worth validating — it's a
  real feature unlock with no microVM required.
- **Allowlist as shared source of truth**: the `--egress` allowlist could feed both Envoy (container
  mode) and a microVM/sandbox network policy — one `allowlist.txt`, multiple enforcement backends.
- **sbx credentials are not environment variables** (since sbx v0.35.0): sbx used to pick up keys
  like `ANTHROPIC_API_KEY` from the host environment and inject them; it no longer does, and
  authenticates only from its own keychain or OAuth. A booth passes credentials exactly the way sbx
  stopped accepting, so delegating to it would silently leave the agent unauthenticated. Whatever
  `SetupSandbox` does for sbx has to reach the keychain — `sbx secret import` — which makes
  credentials part of the integration rather than something inherited for free. This does not
  affect the runtime modes, where the container is still ours and `-e` still works.

## Plan

1. Ship `none` + `gvisor` + `sysbox` first (cheap runtime swaps, no KVM, networking intact).
2. Validate the sysbox ↔ `--egress`+`--dind` interaction.
3. `kata` next (experimental) for KVM hosts.
4. `sbx` last (experimental) — revisit when it hits **1.0**. The `sbx readiness watch` workflow
   opens an issue when sbx releases, so we learn at release time, not at implementation time.
