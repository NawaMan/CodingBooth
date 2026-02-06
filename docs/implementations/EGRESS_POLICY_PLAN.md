# Egress Policy - Decisions and Implementation Tasks

This file captures decisions from the Envoy/firewall experiments and the task list to ship the feature.

## Decisions

1. **Architecture**
   - Use a **sidecar-based egress model**.
   - Run a dedicated **network namespace owner** container.
   - Run both:
     - the user workspace container, and
     - the proxy container
     in that shared namespace via `--network container:<netns-owner>`.

2. **Policy + Enforcement split**
   - Keep these as separate components:
     - **Policy engine** (Envoy/Squid/Tinyproxy/none)
     - **Enforcement engine** (iptables/nftables/none)
   - This enables pluggable backends.

3. **Default security posture**
   - Default to **deny outbound**.
   - Explicit allow rules are required for access.

4. **Configuration surface**
   - Externally supported surface is **only** `--sandboxed`.
   - Policy is provided by **one** of:
   - `.booth/sandbox/allowlist.txt` (simple), or
   - `.booth/sandbox/envoy.yaml` (advanced/custom).
   - These are **mutually exclusive**. If both are set, fail fast with a clear error (no implicit precedence).
   - Internally, `--sandboxed` uses Envoy + iptables with default deny (implementation detail, not user-tunable).
   - If neither file exists, a default allowlist is materialized from the embedded template
     (see `docs/implementations/example-allowlist.txt` or `codingbooth print-default-allowlist.txt`).

6. **Immutability requirement for policy files**
   - Policy files must be mounted into sidecar/proxy containers as **read-only bind mounts**.
   - Containers must run **without `--privileged`** and without `CAP_SYS_ADMIN`.
   - Do not mount Docker socket into workspace/proxy.
   - This protects against in-container root modifying mounted policy files through normal overlay/write paths.

7. **Operational note**
   - If host-level trust is broken (host root, privileged container, or Docker socket control), policy can still be bypassed.
   - This is expected and should be documented in threat model.
8. **GPU/USB compatibility note**
   - GPU/USB access does **not** require `--privileged` or `CAP_NET_ADMIN`.
   - As long as `--privileged` and `CAP_NET_ADMIN` are **not** granted, egress firewall rules remain enforced.
9. **DinD incompatibility (2026-02-06)**
   - `--sandboxed` with `--dind` is **not supported**.
   - The DinD sidecar shares the egress network namespace, and a user with Docker access can run
     a privileged container to flush nftables/iptables, bypassing the firewall.
   - Until further research, require `--sandboxed` to run **without** `--dind`.

## Implementation Tasks

## Phase 1 - Config + Parsing

- [x] Add `[egress]` schema support to config parsing.
- [x] Add validation for:
  - mode/enforcement enum values
  - deny/allow default
  - mutually exclusive/simple-vs-advanced policy inputs
  - policy file existence checks.

## Phase 2 - Runtime Orchestration

- [x] Add netns-owner container lifecycle (create/start/reuse/cleanup).
- [x] Add proxy sidecar lifecycle for `egress.mode`.
- [x] Attach workspace container to netns-owner (`--network container:...`).
- [x] Add deterministic naming (`{container}-{port}-egress-netns`, etc).

## Phase 3 - Policy Materialization

- [x] Implement allowlist -> generated proxy config rendering.
- [x] Support direct custom config pass-through for `.booth/sandbox/envoy.yaml`.
- [x] Store generated artifacts under `.booth/tools/egress/` and mount read-only.

## Phase 4 - Enforcement

- [x] Implement `iptables` enforcement script for shared netns:
  - allow loopback
  - allow established/related
  - allow DNS
  - allow app -> local proxy port
  - allow proxy process outbound 80/443
  - default OUTPUT DROP.
- [ ] Add optional `nftables` backend.
- [ ] Add teardown/restore logic for rules on stop.

## Phase 5 - Hardening

- [ ] Ensure sidecar/workspace are not launched privileged for egress mode.
  - [ ] error out
  - [ ] offer an explicit override
- [ ] Drop unnecessary capabilities. -- error out
- [ ] Set `no-new-privileges` where possible.
- [ ] Ensure policy mounts are read-only and verify write attempts fail.

## Phase 6 - UX + CLI

- [ ] Document `--verbose` as the debug surface for egress details (mode, policy file, proxy port, enforcement status).

## Phase 7 - Docs

- [ ] Add user doc page: quick start with `allowlist.txt`.
- [ ] Add advanced doc page: custom `envoy.yaml`.
- [ ] Add threat model/bypass boundaries section.
- [ ] Add troubleshooting (blocked domain, DNS issues, proxy startup failures).

## Phase 8 - Tests

- [ ] Integration tests:
  - allowed domain succeeds via proxy
  - blocked domain returns deny
  - direct no-proxy outbound fails
  - policy file write fails in container (root and non-root).
- [ ] Regression tests for cleanup (no leaked containers/rules).

## Suggested MVP scope

Start with `--sandboxed` only:
- Envoy + iptables with default deny (implementation detail).
- Policy provided by `.booth/sandbox/allowlist.txt` or `.booth/sandbox/envoy.yaml` (mutually exclusive).

Defer alternate engines and user-tunable config until after MVP stabilizes.

## Current MVP Progress

- [x] `--sandboxed` flag + config parsing and validation
- [x] Envoy sidecar runtime wiring
- [x] iptables enforcement runtime wiring
- [x] Reuse DinD sidecar network namespace when `--dind` is enabled
- [x] Dedicated sandbox netns owner when `--dind` is not enabled
- [ ] **Re-evaluate DinD reuse** — shared netns allows firewall bypass via privileged DinD containers.
- [ ] CLI status/diagnostics command
- [ ] Full integration tests that run real Docker end-to-end in CI
