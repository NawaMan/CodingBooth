# Sidecar Management

CodingBooth uses sidecar containers for DinD and egress sandbox features.
These sidecars share the booth container's network namespace and must be cleaned up when the booth exits.
This document explains how sidecars are created, labeled, tracked, and cleaned up.

---

## Sidecar Types

CodingBooth creates up to three sidecar containers depending on feature flags:

| Sidecar          | Feature     | Image                          | Purpose                            |
|------------------|-------------|--------------------------------|------------------------------------|
| DinD             | `--dind`    | `docker:dind`                  | Isolated Docker daemon             |
| Sandbox netns    | `--sandbox` | `docker:dind`                  | Dedicated network namespace owner  |
| Sandbox proxy    | `--sandbox` | `envoyproxy/envoy:v1.31-latest`| Envoy egress proxy                 |

When both `--dind` and `--sandbox` are enabled, the DinD sidecar doubles as the network namespace owner (no separate sandbox-netns is created).

### Naming Convention

All sidecar container and network names follow the pattern `{booth-name}-{port}-{suffix}`:

| Resource         | Name Pattern                      | Example                       |
|------------------|-----------------------------------|-------------------------------|
| DinD container   | `{name}-{port}-dind`              | `myproject-10000-dind`        |
| DinD network     | `{name}-{port}-net`               | `myproject-10000-net`         |
| Sandbox netns    | `{name}-{port}-sandbox-netns`     | `myproject-10000-sandbox-netns` |
| Sandbox proxy    | `{name}-{port}-sandbox-proxy`     | `myproject-10000-sandbox-proxy` |
| Sandbox network  | `{name}-{port}-sandbox-net`       | `myproject-10000-sandbox-net` |

Naming functions live in `booth.go` (`getDindName`, `getDindNet`) and `sandbox_setup.go` (`getSandboxNetnsName`, `getSandboxProxyName`, `getSandboxNet`).

---

## Labels

Every sidecar container is labeled at creation for precise identification and lifecycle management:

| Label          | Value       | Purpose                                          |
|----------------|-------------|--------------------------------------------------|
| `cb.managed`   | `true`      | Marks as a CodingBooth-managed container         |
| `cb.role`      | `sidecar`   | Distinguishes sidecars from main booth containers |
| `cb.parent`    | `{name}`    | Links the sidecar to its parent booth container  |

The main booth container also carries `cb.managed=true` but does **not** have `cb.role=sidecar`. This distinction allows queries to target sidecars specifically.

### Querying Sidecars

```bash
# All sidecars for a specific booth
docker ps -aq --filter label=cb.role=sidecar --filter label=cb.parent=myproject

# All CodingBooth sidecars (any parent)
docker ps -a --filter label=cb.role=sidecar

# All CodingBooth-managed containers (main + sidecars)
docker ps -a --filter label=cb.managed=true
```

---

## Cleanup Mechanisms

Sidecars are cleaned up through multiple complementary mechanisms:

### 1. Normal Exit Cleanup

When the booth exits normally (command completes or user exits foreground mode), cleanup runs inline in `booth.go`:

```
runAsCommand() / runAsForeground()
  -> cleanupSandboxResources()   // stops proxy + netns + removes sandbox network
  -> stop DinD sidecar           // stops dind + removes dind network
```

This path handles the happy case. Sidecars are started with `--rm`, so stopping them also removes them.

**Source:** `cli/src/pkg/booth/booth.go` — `runAsCommand()`, `runAsForeground()`

### 2. Pre-Run Cleanup (Label-Based)

Before starting a new booth with DinD, `cleanupPreviousBoothInstances()` runs to remove leftover sidecars from previous sessions that exited abnormally.

It queries Docker for containers matching:
```
--filter label=cb.role=sidecar
--filter label=cb.parent={projectName}
```

This is precise — it only targets sidecars owned by the same project and covers all sidecar types (DinD, sandbox-netns, sandbox-proxy) in a single query.

It also cleans up leftover networks by name prefix + `-net` suffix matching.

**Source:** `cli/src/pkg/booth/dind_setup.go` — `cleanupPreviousBoothInstances()`

### 3. Lifecycle Command Cleanup

The lifecycle commands (`codingbooth stop`, `codingbooth remove`, `codingbooth prune`) also handle sidecars:

| Command  | Sidecar Behavior                                                         |
|----------|--------------------------------------------------------------------------|
| `stop`   | After stopping the main container, stops all sidecars with matching `cb.parent` |
| `remove` | Before removing the main container, stops all sidecars with matching `cb.parent` |
| `prune`  | After pruning stopped containers, finds and removes orphaned sidecars    |

**Orphan detection** in `prune`: queries all containers with `cb.role=sidecar`, inspects each one's `cb.parent` label, and removes those whose parent container no longer exists.

**Source:** `cli/src/pkg/lifecycle/lifecycle.go` — `stopSidecars()`, `pruneOrphanSidecars()`

### 4. Daemon Mode (No Auto-Cleanup)

In daemon mode, sidecars are **not** automatically cleaned up because the booth runs in the background. The user is informed of running sidecars and told how to stop them manually. Lifecycle commands (`codingbooth stop`) handle cleanup in this case.

---

## Source Files

| File                              | Responsibility                                         |
|-----------------------------------|--------------------------------------------------------|
| `cli/src/pkg/booth/booth.go`      | Normal exit cleanup, sidecar naming (`getDindName`, `getDindNet`) |
| `cli/src/pkg/booth/booth_runner.go` | Orchestration: calls `SetupDind()` then `SetupSandbox()` |
| `cli/src/pkg/booth/dind_setup.go` | DinD sidecar creation, label assignment, pre-run cleanup |
| `cli/src/pkg/booth/sandbox_setup.go` | Sandbox sidecar creation, label assignment, sandbox cleanup |
| `cli/src/pkg/lifecycle/lifecycle.go` | Lifecycle commands: stop/remove/prune with sidecar cleanup |

---

## Startup Flow

```
BoothRunner.Run()
  -> SetupDind(ctx)
       -> cleanupPreviousBoothInstances()   // label-based orphan cleanup
       -> createDindNetwork()               // {name}-{port}-net
       -> startDindSidecar()                // {name}-{port}-dind, with labels
       -> waitForDindReady()
  -> SetupSandbox(ctx)
       -> startSandboxNetnsOwner()          // {name}-{port}-sandbox-netns, with labels (skipped if DinD)
       -> startSandboxProxy()               // {name}-{port}-sandbox-proxy, with labels
       -> waitForSandboxProxyReady()
       -> applySandboxFirewall()
  -> PrepareCommonArgs(ctx)                 // sets cb.managed=true on main container
  -> booth.Run()
```

---

## Edge Cases

**Abnormal exit (crash, SIGKILL, test timeout):**
Sidecars remain running. They are cleaned up on the next `codingbooth run` (pre-run cleanup), by `codingbooth prune` (orphan detection), or by `codingbooth stop`/`remove` targeting the parent.

**Containers created before label support:**
Old sidecars without labels are not found by label-based queries. They must be cleaned up manually by name:
```bash
docker ps -a --format "{{.Names}}" | grep -E "(-dind$|-sandbox-netns$|-sandbox-proxy$)" | xargs -r docker stop
```

**DinD + Sandbox combined:**
When both flags are enabled, `getSandboxNetnsOwnerName()` returns the DinD sidecar name instead of creating a separate netns container. The DinD sidecar carries all three labels and serves both roles.
