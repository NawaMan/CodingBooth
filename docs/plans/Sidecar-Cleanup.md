# Sidecar Cleanup Improvements

## Problem

DinD and egress sidecars can leak when the parent booth process exits abnormally (crash, SIGKILL, test timeout). Leaked sidecars hold ports indefinitely, causing `NEXT` port selection to skip large ranges.

Observed: 22 orphaned `docker:dind` containers (`*-egress-netns`) from integration tests holding ports 11000-32000, forcing `NEXT` to jump to 33000.

## Current Cleanup Mechanisms

### 1. Normal exit cleanup (`booth.go`)
- `cleanupEgressResources()` stops proxy + netns + removes network.
- DinD sidecar is stopped and network removed.
- **Only runs on graceful exit.** SIGKILL / crash / test timeout = no cleanup.

### 2. Pre-run cleanup (`cleanupPreviousBoothInstances` in `dind_setup.go`)
- Runs at DinD setup time, before starting a new booth.
- Only matches `projectName` and `projectName-*-dind`.
- **Does not cover egress sidecars** (`*-egress-netns`, `*-egress-proxy`, `*-egress-net`).
- Uses Docker `name` filter with `*` wildcard, which does not work as intended (Docker uses substring matching, not glob).

### 3. `--rm` flag on sidecars
- All sidecars are started with `--rm`, so they auto-remove when stopped.
- But if the parent process dies without stopping them, they keep running forever.

## Risks with Current Approach

- **Wrong sidecar killed:** The wildcard-based cleanup in `cleanupPreviousBoothInstances` could match sidecars belonging to a different booth run if project names share a prefix.
- **Egress sidecars never cleaned up:** The pre-run cleanup only targets DinD patterns, completely missing egress containers.
- **Integration tests are worst case:** Tests create many sidecars with unique names (timestamps + random suffixes), and if the test process crashes, none get cleaned up.

## Proposed Fix: Label-Based Ownership

### Label sidecars with parent identity

When starting any sidecar (DinD, egress-netns, egress-proxy), add:
```
--label cb.managed=true
--label cb.role=sidecar
--label cb.parent=<container-name>
```

### Targeted cleanup on start

Replace `cleanupPreviousBoothInstances` wildcard matching with:
```
docker ps -aq --filter label=cb.parent=<my-container-name>
```

This is precise -- no wildcards, no risk of killing another booth's sidecars.

### Lifecycle command integration

`codingbooth stop` and `codingbooth remove` should also query `--filter label=cb.parent=<name>` and stop/remove any matching sidecars.

### Orphan detection in `codingbooth list` or `codingbooth prune`

Could optionally list orphaned sidecars (sidecars whose `cb.parent` container no longer exists) and offer to clean them up.

## Sidecar Naming Reference

| Sidecar              | Name pattern                          | Created by         |
|----------------------|---------------------------------------|--------------------|
| DinD                 | `{name}-{port}-dind`                  | `dind_setup.go`    |
| DinD network         | `{name}-{port}-net`                   | `dind_setup.go`    |
| Egress netns owner  | `{name}-{port}-egress-netns`         | `egress_setup.go` |
| Egress proxy        | `{name}-{port}-egress-proxy`         | `egress_setup.go` |
| Egress network      | `{name}-{port}-egress-net`           | `egress_setup.go` |

## Priority

Low-medium. The issue mainly surfaces during development/testing with DinD or egress features. Regular (non-DinD, non-egress) booth usage is unaffected.
