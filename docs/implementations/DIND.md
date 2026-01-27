# Docker-in-Docker (DinD) Implementation

Run Docker and Kubernetes inside CodingBooth — without touching your host Docker daemon.
CodingBooth’s Docker-in-Docker (DinD) implementation provides a fully isolated, reproducible container runtime that lets you build images, run containers, and launch Kubernetes clusters safely inside a workspace.
All Docker state lives in a dedicated sidecar daemon, host ports are exposed only by explicit declaration, and nothing started inside the booth can pollute or interfere with your host environment.
The result is a clean, predictable, and secure Docker experience — perfect for microservices development, CI workflows, and Kubernetes experimentation.

This document describes the Docker-in-Docker (DinD) implementation used by CodingBooth, including its architecture, startup flow, and the observable effects from both the host and inside the booth container.

The goal is to allow users to run Docker workloads inside CodingBooth without exposing the host Docker daemon, while maintaining predictable and secure port exposure behavior.

---

## Design Goals

The DinD implementation in CodingBooth is designed to:

- Allow users to run Docker commands (`docker build`, `docker run`, Kubernetes tools, etc.) inside the booth container
- Avoid mounting the host Docker socket (`/var/run/docker.sock`)
- Ensure host port exposure is explicit and declared at startup
- Prevent containers started inside the booth from being visible to the host Docker daemon
- Provide a clean and predictable development environment

## High-Level Overview

When DinD is enabled, CodingBooth runs two containers:

**DinD sidecar container**
- Runs a Docker daemon (`docker:dind`)
- Owns all host port exposure

**Booth container**
- Runs user code and tools
- Uses the Docker daemon provided by the DinD sidecar

The booth container does not talk to the host Docker daemon. Instead, it talks to the DinD daemon over TCP.

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                            Host                                │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │        Bridge Network (for DinD sidecar only)            │  │
│  │                                                          │  │
│  │  ┌─────────────────────┐                                 │  │
│  │  │   DinD Sidecar      │                                 │  │
│  │  │   (docker:dind)     │                                 │  │
│  │  │                     │                                 │  │
│  │  │  - Docker daemon    │                                 │  │
│  │  │  - Port publishing  │                                 │  │
│  │  │    to host          │                                 │  │
│  │  │                     │                                 │  │
│  │  │  Ports:             │                                 │  │
│  │  │  -p 10000:10000     │  <- booth port                  │  │
│  │  │  -p 8080:8080       │  <- from run-args               │  │
│  │  │  -p 3000:3000       │  <- from run-args               │  │
│  │  └─────────▲───────────┘                                 │  │
│  │            │                                             │  │
│  │            │  Shared network namespace                   │  │
│  │            │                                             │  │
│  │  ┌─────────┴─────────────────┐                           │  │
│  │  │   Booth Container         │                           │  │
│  │  │   (coding-booth)          │                           │  │
│  │  │                           │                           │  │
│  │  │  - User code              │                           │  │
│  │  │  - Docker CLI             │                           │  │
│  │  │  - DOCKER_HOST=           │                           │  │
│  │  │    tcp://localhost:2375   │                           │  │
│  │  └───────────────────────────┘                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                │
│  Host ports exposed: 10000, 8080, 3000                         │
└────────────────────────────────────────────────────────────────┘
```

## Key Components

### 1. DinD Sidecar Container

- **Image**: `docker:dind`
- Runs a full Docker daemon
- Started with:
  - `--privileged`
  - TLS disabled (`DOCKER_TLS_CERTDIR=`)
- Publishes all host-facing ports
- **Container name**: `{project}-{port}-dind` (e.g., `dind-example-10000-dind`)

### 2. Booth Container

- Runs user code and tools
- Uses container network mode: `--network container:{dind-sidecar}`
- Shares the same network namespace as the DinD sidecar
- Cannot publish ports directly
- Communicates with Docker via: `DOCKER_HOST=tcp://localhost:2375`

### 3. DinD Bridge Network

- A Docker bridge network created for the DinD sidecar
- Used only to attach the sidecar to Docker networking
- The booth container does not join this network directly
- **Network name**: `{project}-{port}-net` (e.g., `dind-example-10000-net`)

## Network Namespace Sharing

The booth container is started with:

```bash
docker run --network container:dind-example-10000-dind ...
```

This has several important effects:

- The booth and sidecar share:
  - `localhost`
  - IP addresses
  - Open ports
- Any service started inside the booth binds to this shared namespace
- The booth container cannot use `-p` or `--publish`

## Port Exposure Model

### Port Sources

Ports exposed to the host come from three sources:

| Source      | Description                                           | Example       |
|-------------|-------------------------------------------------------|---------------|
| Booth port  | Main port for booth services (code-server, VNC, etc.) | `10000:10000` |
| Config file | Ports declared in `.booth/config.toml` via `run-args` | `8080:8080`   |
| CLI         | Ports passed directly on command line                 | `5000:5000`   |

All ports are collected and passed to the DinD sidecar. **Duplicate ports are automatically deduplicated.**

### Declaring Ports in Config File

Ports that should be reachable from the host can be declared in `.booth/config.toml`:

```toml
variant  = "desktop-xfce"
dind     = true
run-args = [
    "-p", "8080:8080",
    "-p", "3000:3000"
]
```

### Declaring Ports via CLI

Additional ports can be passed directly on the command line:

```bash
coding-booth -p 5000:5000
```

These are combined with ports from the config file.

### Port Deduplication

If the same port is declared in both config and CLI, it appears only once:

```bash
# Config has: -p 8080:8080
# CLI adds:   -p 8080:8080 -p 5000:5000
# Result:     -p 10000:10000 -p 8080:8080 -p 3000:3000 -p 5000:5000
#             (8080 appears once, not twice)
```

### How Port Handling Works

1. CodingBooth parses `run-args` from config and CLI
2. Port flags (`-p`, `--publish`) are extracted and deduplicated
3. These flags are applied to the DinD sidecar
4. Port flags are removed from the booth container arguments
5. The booth container shares the sidecar's network namespace

Resulting commands:

```bash
# DinD sidecar (gets all ports)
docker run ... -p 10000:10000 -p 8080:8080 -p 3000:3000 docker:dind

# Booth container (no -p flags, shares sidecar network)
docker run ... --network container:dind-example-10000-dind ...
```

## Observable Effects (Intended Behavior)

### Inside the Booth Container

Any service can be started on any port:

```bash
docker run -p 8080:8080 my-server
docker run -p 3000:3000 another-server
```

Both services are reachable from inside the booth:
- `localhost:8080`
- `localhost:3000`

### From the Host

Only ports declared at startup are reachable:

| Port | Declared at startup? | Accessible from host? |
|------|----------------------|-----------------------|
| 8080 | Yes (in config)      | Yes                   |
| 3000 | No                   | No                    |

This guarantees that no new host ports can be exposed after startup.

## Container Visibility and Docker Daemons

There are two Docker daemons involved:

### Host Docker Daemon

- Manages:
  - DinD sidecar container
  - Booth container
- Visible via `docker ps` on the host

### DinD Docker Daemon

- Runs inside the sidecar
- Used by the booth container
- Manages:
  - Containers started by the user inside the booth
- Visible via `docker ps` inside the booth

### Resulting Visibility

| Location     | `docker ps` shows            |
|--------------|------------------------------|
| Host         | Sidecar + booth containers   |
| Inside booth | Only user-started containers |

This separation is intentional and ensures isolation from the host Docker daemon.

## Startup Sequence

1. Create DinD bridge network (if needed)
2. Extract port mappings from `run-args` (config + CLI)
3. Deduplicate port mappings
4. Start DinD sidecar with all port mappings
5. Wait for Docker daemon readiness
6. Strip port and network flags from booth arguments
7. Start booth container with:
   - `--network container:{sidecar}`
   - `DOCKER_HOST=tcp://localhost:2375`

## Cleanup Behavior

When the booth session ends:

1. Stop the DinD sidecar container
2. Remove the DinD bridge network (if created by this session)

## Implementation Details

The DinD setup is handled in these source files:

| File                                | Purpose                                               |
|-------------------------------------|-------------------------------------------------------|
| `cli/src/pkg/booth/booth_runner.go` | `SetupDind()` orchestrates DinD initialization        |
| `cli/src/pkg/booth/dind_setup.go`   | Network creation, sidecar management, port extraction |
| `cli/src/pkg/booth/dind_names.go`   | Naming conventions for DinD resources                 |

Key functions:
- `extractPortFlags()` - Extracts and deduplicates port mappings from `run-args`
- `stripNetworkAndPortFlags()` - Removes port/network flags from booth container args
- `startDindSidecar()` - Starts the DinD sidecar with all port mappings

## Limitations

- Ports must be declared at startup
- Ports cannot be dynamically exposed to the host after startup
- DinD requires privileged mode
- Slight performance overhead due to nested Docker

## FAQ

### Why Not Mount the Host Docker Socket?

Mounting `/var/run/docker.sock` would:

- give the booth full control over the host Docker daemon
- allow accidental deletion of host containers and images
- allow uncontrolled host port exposure
- break isolation between projects

The DinD sidecar design avoids all of these risks by:

- isolating Docker state per booth
- preventing host daemon access
- enforcing explicit port exposure
- keeping host Docker clean

## Summary

CodingBooth's DinD implementation provides:

- A clean separation between host and user Docker workloads
- Explicit, startup-time port exposure
- Full Docker functionality inside the booth
- Predictable networking and container visibility
- Automatic deduplication of port mappings

All observed behaviors — port access, container visibility, and isolation — are intentional design outcomes, not side effects.

---

## Related Files

- `cli/src/pkg/booth/booth_runner.go` — `SetupDind()` orchestrates DinD initialization
- `cli/src/pkg/booth/dind_setup.go` — Network creation, sidecar management, port extraction
- `cli/src/pkg/booth/dind_names.go` — Naming conventions for DinD resources
- `examples/dind-example/` — Basic DinD usage example
- `examples/kind-example/` — Running Kubernetes with KinD inside the booth
