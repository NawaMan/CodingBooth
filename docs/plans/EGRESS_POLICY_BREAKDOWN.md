# Egress Policy Breakdown

This is the execution breakdown for shipping egress policy in Booth.

## Current Status

- [x] Decision doc created: `docs/implementations/EGRESS_POLICY_PLAN.md`
- [x] Experiments completed (sidecar netns + firewall + Envoy proxy)
- [x] Phase 1 (config parsing + validation) completed
- [x] Runtime orchestration (MVP: Envoy + iptables)
- [ ] Proxy policy generation
- [ ] Enforcement backends
- [ ] Tests + docs + UX polish

## Milestones

## Milestone 1 - Config Foundation (MVP start)

Goal: parse and validate egress configuration without runtime behavior changes.

Work items:
- Add `--sandboxed` shorthand flag to enable egress defaults.
- Add `[egress]` config model in AppConfig.
- Add AppContext accessors for egress values.
- Validate:
  - mode enum
  - enforcement enum
  - default policy enum
  - mutual exclusivity of allowlist vs policy file
  - referenced file existence.

Target files:
- `cli/src/pkg/appctx/app_config.go`
- `cli/src/pkg/appctx/app_context.go`
- `cli/src/pkg/booth/init/initialize_app_context.go`
- tests in `cli/src/pkg/appctx/` and `cli/src/pkg/booth/init/`

## Milestone 2 - Runtime Wiring (Envoy + iptables only)

Goal: first working backend pair using sidecar model.

Work items:
- Reuse DinD sidecar netns if `--dind` is enabled.
- Otherwise create a dedicated egress netns-owner sidecar.
- Launch Envoy sidecar in shared netns.
- Attach workspace container to shared netns.
- Apply iptables enforcement in shared netns.

## Milestone 3 - Policy Inputs

Goal: support simple + advanced policy input modes.

Work items:
- Simple mode: `.booth/egress/allowlist.txt` -> generated Envoy config.
- Advanced mode: `.booth/egress/envoy.yaml` passthrough.
- Mount policy artifacts read-only.

## Milestone 4 - Hardening + UX

Goal: make the feature safe and operable.

Work items:
- Drop unnecessary capabilities on sidecars.
- Ensure non-privileged runtime for workspace/proxy containers.
- Add status/diagnostic command output.
- Add troubleshooting docs and threat model notes.

## Milestone 5 - Expand Backends

Goal: optional alternative engines.

Work items:
- Add `squid`/`tinyproxy` modes.
- Add optional nftables backend.
- Keep policy/enforcement contracts stable.
