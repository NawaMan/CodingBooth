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

4. **Config model**
   - Add egress config in `.booth/config.toml`:
     - `egress.mode = "none|envoy|squid|tinyproxy"`
     - `egress.enforcement = "none|iptables|nftables"`
     - `egress.default = "deny|allow"`
     - `egress.allowlist_file = ".booth/egress/allowlist.txt"` (optional)
     - `egress.policy_file = ".booth/egress/envoy.yaml"` (optional advanced mode)
   - Add `--sandbox` shorthand flag to enable secure defaults:
     - `egress.mode=envoy`
     - `egress.enforcement=iptables`
     - `egress.default=deny`

5. **User-facing policy files**
   - Support either:
     - `.booth/egress/allowlist.txt` (simple), or
     - `.booth/egress/envoy.yaml` (advanced/custom).

6. **Immutability requirement for policy files**
   - Policy files must be mounted into sidecar/proxy containers as **read-only bind mounts**.
   - Containers must run **without `--privileged`** and without `CAP_SYS_ADMIN`.
   - Do not mount Docker socket into workspace/proxy.
   - This protects against in-container root modifying mounted policy files through normal overlay/write paths.

7. **Operational note**
   - If host-level trust is broken (host root, privileged container, or Docker socket control), policy can still be bypassed.
   - This is expected and should be documented in threat model.

## Implementation Tasks

## Phase 1 - Config + Parsing

- [ ] Add `[egress]` schema support to config parsing.
- [ ] Add validation for:
  - mode/enforcement enum values
  - deny/allow default
  - mutually exclusive/simple-vs-advanced policy inputs
  - policy file existence checks.

## Phase 2 - Runtime Orchestration

- [ ] Add netns-owner container lifecycle (create/start/reuse/cleanup).
- [ ] Add proxy sidecar lifecycle for `egress.mode`.
- [ ] Attach workspace container to netns-owner (`--network container:...`).
- [ ] Add deterministic naming (`{container}-{port}-egress-netns`, etc).

## Phase 3 - Policy Materialization

- [ ] Implement allowlist -> generated proxy config rendering.
- [ ] Support direct custom config pass-through for `.booth/egress/envoy.yaml`.
- [ ] Store generated artifacts under `.booth/tools/egress/` and mount read-only.

## Phase 4 - Enforcement

- [ ] Implement `iptables` enforcement script for shared netns:
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
- [ ] Drop unnecessary capabilities.
- [ ] Set `no-new-privileges` where possible.
- [ ] Ensure policy mounts are read-only and verify write attempts fail.

## Phase 6 - UX + CLI

- [ ] Add CLI flags mirroring config values (with clear precedence rules).
- [ ] Add `booth --egress-status` diagnostics output:
  - mode/enforcement
  - loaded policy file
  - active proxy endpoint
  - enforcement active/inactive.

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

Start with:
- `egress.mode = envoy`
- `egress.enforcement = iptables`
- `egress.default = deny`
- only `.booth/egress/allowlist.txt`

Then add custom `envoy.yaml` and alternate engines after MVP stabilizes.

## Current MVP Progress

- [x] `--sandbox` flag + config parsing and validation
- [x] Envoy sidecar runtime wiring
- [x] iptables enforcement runtime wiring
- [x] Reuse DinD sidecar network namespace when `--dind` is enabled
- [x] Dedicated sandbox netns owner when `--dind` is not enabled
- [ ] CLI status/diagnostics command
- [ ] Full integration tests that run real Docker end-to-end in CI
