# TODO App on KIND - Full-Stack Kubernetes Example

This example deploys a real full-stack microservices TODO app to a Kubernetes cluster running inside a CodingBooth. One command flow (`start-cluster.sh`, `build.sh`, `deploy-app.sh`, `access-app.sh`) spins up a KinD cluster and deploys a React + Vite frontend, a Go REST/WebSocket API, a Go export service, and PostgreSQL, then port-forwards the UI to `http://localhost:3000`. The entire cluster and its microservices run nested inside the booth, so a production-style Kubernetes stack — frontend, two Go services, and a database wired together with real manifests — comes up on any laptop with zero host setup. A new teammate goes from `git clone` to a running, seeded, port-forwarded app in one command flow instead of a day of installing tools and chasing version drift, and everyone runs the exact same kubectl, kind, and runtime versions. When they're done, stopping the booth erases the whole cluster cleanly — nothing to uninstall, nothing left polluting the host.

## Table of Contents

- [TODO App on KIND - Full-Stack Kubernetes Example](#todo-app-on-kind---full-stack-kubernetes-example)
  - [Table of Contents](#table-of-contents)
  - [Why Run Kubernetes in CodingBooth?](#why-run-kubernetes-in-codingbooth)
    - [Credentials Separation Pattern](#credentials-separation-pattern)
    - [Interactive Runnable Documentation](#interactive-runnable-documentation)
  - [Quick Start](#quick-start)
  - [Architecture](#architecture)
  - [Tech Stack](#tech-stack)
  - [Ports](#ports)
  - [Accessing the App](#accessing-the-app)
  - [Scripts](#scripts)
  - [API Endpoints](#api-endpoints)
    - [Expected 404s and 405s](#expected-404s-and-405s)
    - [Service-to-Service Export Flow](#service-to-service-export-flow)
  - [Project Structure](#project-structure)
  - [How It Works](#how-it-works)
  - [Configuration](#configuration)
  - [Cleanup](#cleanup)


## Why Run Kubernetes in CodingBooth?

Running Kubernetes inside CodingBooth provides a **repeatable, isolated environment** that solves common development challenges:

| Benefit                  | Description                                                                                                                                   |
|--------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| **Reproducibility**      | Every developer gets the exact same Kubernetes setup. No version mismatches, no missing tools, no configuration drift.                        |
| **Isolation**            | The entire cluster lives inside the booth. Host system stays clean - no leftover Docker resources, or kubectl configs polluting your machine. |
| **Team Consistency**     | New team members can run `./codingbooth` and have a working Kubernetes environment in minutes, not hours of setup.                            |
| **Safe Experimentation** | Break things freely. Corrupt your cluster? Just restart the container. No risk to your host or other projects.                                |
| **Clean Teardown**       | When you're done, everything disappears cleanly. No orphaned resources, no zombie processes, no manual cleanup.                               |
| **CI/CD Ready**          | The same containerized environment runs locally and in CI pipelines, eliminating "works on my machine" issues.                                |

This example demonstrates running a full Kubernetes cluster with multiple microservices, a database, and networking - all completely contained and reproducible.

### Credentials Separation Pattern

CodingBooth supports separating **secrets** (kept safe on your host) from **configuration** (committed with the project):

| What                    | Where                      | Committed?             |
|-------------------------|----------------------------|------------------------|
| Credentials (secrets)   | Host `~/.aws/credentials`  | No - user keeps safe   |
| Config (profile/region) | `.booth/home/.aws/config`  | Yes - shared with team |

**How it works:**
```toml
# .booth/config.toml - mount credentials from host (read-only)
run-args = [
    "-v", "~/.aws/credentials:/etc/cb-home-seed/.aws/credentials:ro",
]
```

```ini
# .booth/home/.aws/config - project-specific profile (committed to repo)
[default]
region = ap-southeast-1

[profile my-project-prod]
region = us-east-1
role_arn = arn:aws:iam::123456789:role/ProjectRole
source_profile = default
```

This way you never forget which AWS profile/region to use for each project - it's defined in the repo. Team members just need matching profile names in their host credentials.

### Interactive Runnable Documentation

Include Jupyter Notebooks (`*.ipynb`) in your project for **documentation that actually runs**:

- Step-by-step guides with explanations and executable code cells
- New team members follow along and run each step
- No copy-paste errors - just click "Run"
- Documentation stays in sync because it's tested by running it

This example includes:
- [`TODO-App-Guide.ipynb`](TODO-App-Guide.ipynb) - Deploy to KIND (local Kubernetes)
- [`TODO-App-AWS-EKS-Guide.ipynb`](TODO-App-AWS-EKS-Guide.ipynb) - Deploy to AWS EKS (cloud)

## Quick Start

**Interactive Guides (Jupyter Notebooks):**
- [`TODO-App-Guide.ipynb`](TODO-App-Guide.ipynb) - Deploy to KIND (local Kubernetes)
- [`TODO-App-AWS-EKS-Guide.ipynb`](TODO-App-AWS-EKS-Guide.ipynb) - Deploy to AWS EKS (cloud)

```bash
# Start the booth
cd examples/workspaces/kind-app-example
booth

# Inside the workspace, run:
./start-cluster.sh   # Create KIND cluster
./build.sh           # Build Docker images
./deploy-app.sh      # Deploy to Kubernetes
./access-app.sh      # Start port-forwards
./status.sh          # One-shot health check (optional)

# Open http://localhost:3000 in your browser
```

**Timings.** On a cold booth, `./start-cluster.sh` spends most of its time pulling the
~1.5 GB `kindest/node` image, and `./build.sh` pulls `golang:1.21-alpine`,
`oven/bun:1-alpine`, and `nginx:alpine` and runs `bun install` — budget several minutes
each. Once those layers are cached, cluster creation takes ~15 s and rebuilds take
seconds. `./deploy-app.sh` is fast either way; it waits on rollout, not on downloads.

**Tip: run the first two steps in parallel.** `./start-cluster.sh` and `./build.sh` are
independent — one creates the cluster, the other builds images — and both talk to the
same DinD daemon. Running them concurrently cuts a couple of minutes off a cold start:

```bash
./start-cluster.sh &
./build.sh &
wait
./deploy-app.sh
```

`./deploy-app.sh` must come after both, since it `kind load`s the images into the cluster.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  KIND Cluster (todo-app namespace)                              │
│                                                                 │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐  │
│   │    React     │      │   Go API     │      │   Export     │  │
│   │   (nginx)    │─────▶│   Service    │─────▶│   Service    │  │
│   │   web:80     │ /api │   api:8080   │ HTTP │ export:8081  │  │
│   └──────────────┘  /ws └──────────────┘      └──────────────┘  │
│                              │                                  │
│                              ▼                                  │
│                        ┌──────────────┐                         │
│                        │  PostgreSQL  │                         │
│                        │ postgres:5432│                         │
│                        └──────────────┘                         │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Component      | Technology                                        |
|----------------|---------------------------------------------------|
| Frontend       | React 18 + TypeScript + Vite + Tailwind CSS + Bun |
| API            | Go 1.21 + Chi router + gorilla/websocket          |
| Export Service | Go 1.21 + Chi router                              |
| Database       | PostgreSQL 15                                     |
| Web Server     | nginx                                             |
| Container      | Docker + KIND (Kubernetes IN Docker)              |

The Go versions above are the `golang:1.21-alpine` build stages pinned in each service's
`Dockerfile`. The Go toolchain installed in the booth itself is newer (set by
`CB_GO_VERSION` in `.booth/Boothfile`) and is what you get from `go` on the command line —
the two are independent by design, so the images build reproducibly regardless of the
booth's toolchain.

## Ports

| Port | Service | Description                | Needed for the demo?                          |
|------|---------|----------------------------|-----------------------------------------------|
| 3000 | Web UI  | React frontend             | **Yes** — this is the only port you need      |
| 8080 | API     | Go REST API + WebSocket    | Optional — for hitting the API directly       |
| 8081 | Export  | Export service (CSV/JSON)  | Optional — internal service, rarely called directly |

Port 3000 alone is sufficient: the nginx in the `web` pod proxies `/api/` and `/ws`
through to `api:8080` inside the cluster (see [`k8s/web-configmap.yaml`](k8s/web-configmap.yaml)),
so the UI, the REST API, and the CSV/JSON export all work through that single port.

## Accessing the App

`./access-app.sh` starts `kubectl port-forward` with `--address 0.0.0.0`, which makes the
services reachable **from inside the booth** — for example from Firefox or Chrome on the
booth desktop, which is the simplest way to demo this.

Reaching the app **from the host browser** is a separate step. A port-forward inside the
container does not by itself publish anything to the host. Check what is actually reachable:

```bash
booth--expose list
```

Rows marked `internal` are container-only. A port is reachable from the host only if its
row says `published` (declared in `.booth/config.toml` at container start) or `tunnel`
(created at runtime). If port 3000 shows `internal`, open a tunnel:

```bash
booth--expose 3000          # host localhost:3000 -> container 3000
booth--expose 8080          # optional, only if you want the API from the host
booth--expose 8081          # optional
```

Runtime tunnels are **ephemeral and do not survive a booth restart**. To persist one, use
`booth--expose 3000 --permanent`, which writes to `.booth/config.toml` — that file is
read-only inside the booth by default, so this requires either editing it from the host or
restarting with `--writable-booth`.

## Scripts

| Script                | Description                                           |
|-----------------------|-------------------------------------------------------|
| `./status.sh`         | Show cluster, pods, services, and port-forward status |
| `./start-cluster.sh`  | Create KIND cluster                                   |
| `./stop-cluster.sh`   | Delete KIND cluster                                   |
| `./check-cluster.sh`  | Check if cluster is running                           |
| `./build.sh`          | Build all Docker images                               |
| `./deploy-app.sh`     | Deploy TODO app to cluster                            |
| `./remove-app.sh`     | Remove TODO app from cluster                          |
| `./access-app.sh`     | Start port-forwards to access app from host           |
| `./access-app-stop.sh`| Stop port-forwards                                    |

## API Endpoints

**API service** (port 8080, [`api/main.go`](api/main.go)):

| Method | Endpoint                      | Description                    |
|--------|-------------------------------|--------------------------------|
| GET    | /health                       | Liveness check                 |
| GET    | /api/tasks                    | List all tasks                 |
| POST   | /api/tasks                    | Create a task                  |
| GET    | /api/tasks/:id                | Get a task                     |
| PUT    | /api/tasks/:id                | Update a task                  |
| DELETE | /api/tasks/:id                | Delete a task                  |
| GET    | /api/export?format=csv\|json  | Export tasks                   |
| WS     | /ws                           | WebSocket for real-time updates|

**Export service** (port 8081, [`export-service/main.go`](export-service/main.go)):

| Method | Endpoint  | Description                                      |
|--------|-----------|--------------------------------------------------|
| GET    | /health   | Liveness check                                   |
| POST   | /export   | Format a supplied task list as CSV or JSON       |

### Expected 404s and 405s

Neither Go service registers a route at `/`, so these responses are **correct behavior,
not a broken deployment**:

| Request                       | Response | Why                                              |
|-------------------------------|----------|--------------------------------------------------|
| `GET http://localhost:8080/`  | 404      | Nothing mounted at root; routes live under `/api` |
| `GET http://localhost:8081/`  | 404      | Nothing mounted at root                          |
| `GET http://localhost:8081/export` | 405 | `/export` is registered as POST-only — a browser sends GET |
| `GET http://localhost:8080/ws` | 400     | Expects a WebSocket upgrade, not a plain GET     |

Use `/health` on either service for a quick "is it up?" check, and `/api/tasks` on the API
for a quick "is the database wired up?" check.

### Service-to-Service Export Flow

The export is a genuine two-service hop, not a local function call:

```
Browser  ──GET /api/export?format=csv──▶  api:8080
                                            │  reads tasks from postgres:5432
                                            │
                                            ├──POST /export──▶  export-service:8081
                                            │   {"tasks": [...], "format": "csv"}
                                            │                      │ formats CSV/JSON
                                            ◀──────────────────────┘
Browser  ◀──────CSV/JSON body──────────────┘
```

The API finds the export service via the `EXPORT_SERVICE_URL` environment variable, set to
`http://export-service:8081` in [`k8s/api-configmap.yaml`](k8s/api-configmap.yaml) and
falling back to `http://localhost:8081` when unset. This is why the export service is
POST-only and has no browser-friendly GET route — it is an internal service that receives
an already-fetched task list, never a public endpoint.

## Project Structure

```
kind-app-example/
├── TODO-App-Guide.ipynb  # Interactive Jupyter notebook guide
├── .booth/
│   ├── config.toml       # Runtime config (DinD, published ports)
│   └── Boothfile         # Image build: kubectl, kind, go, bun, python, aws-cli
│
├── api/                  # Go API Service
│   ├── main.go
│   ├── handlers/         # REST + WebSocket handlers
│   ├── models/           # Data models
│   ├── db/               # Database connection
│   └── Dockerfile
│
├── export-service/       # Go Export Service
│   ├── main.go
│   ├── handlers/         # Export handlers (CSV/JSON)
│   └── Dockerfile
│
├── web/                  # React Frontend
│   ├── src/
│   │   ├── components/   # React components
│   │   ├── api/          # API client
│   │   └── hooks/        # Custom hooks (WebSocket)
│   ├── e2e/              # Playwright tests
│   └── Dockerfile
│
├── k8s/                  # Kubernetes manifests
│   ├── postgres-*.yaml   # Database
│   ├── api-*.yaml        # API service
│   ├── export-*.yaml     # Export service
│   └── web-*.yaml        # Frontend
│
└── seed/seed.sql         # Database seed data
```

## How It Works

This example uses **Docker-in-Docker (DinD)** to run a KIND cluster inside the workspace:

```
Host
└── DinD sidecar container
    ├── Docker daemon (:2375)
    │   └── KIND cluster
    │       └── Kubernetes pods (postgres, api, web, export)
    └── Workspace container (shares DinD network)
        ├── kubectl, kind, docker CLI
        └── Your code mounted at /home/coder/code
```

Port-forwards use `--address 0.0.0.0` so they bind to every interface in the container
rather than just loopback. That is what makes them reachable beyond the process that
started them — but it does **not** by itself publish anything to the host; that still
requires a published port or a tunnel. See [Accessing the App](#accessing-the-app).

## Configuration

Two files drive the booth. **`.booth/Boothfile`** builds the image — it declares the
toolchain, so every teammate gets identical versions:

```
# syntax=codingbooth/boothfile:1

arg CB_GO_VERSION=1.25.3
arg CB_BUN_VERSION=1.3.6

setup dind                    # Docker-in-Docker, required for KIND
setup kind                    # Kubernetes IN Docker
setup aws-cli                 # for the EKS guide

setup go ${CB_GO_VERSION}
setup bun ${CB_BUN_VERSION}
setup python
setup notebook 18888          # Jupyter, for the runnable guides
```

**`.booth/config.toml`** controls runtime:

```toml
dind = true

run-args = ["--publish", "+-7000:3000"]
```

`dind = true` is the essential line — without the DinD sidecar there is no Docker daemon
to run the KIND cluster in.

> **Note on publishing ports.** The `--publish` run-arg above is intended to map the web UI
> to a host port, but do not assume it took effect. Verify with `booth--expose list`: if
> port 3000 shows `internal` rather than `published`, nothing reached the host and you
> should open a tunnel with `booth--expose 3000`. See
> [Accessing the App](#accessing-the-app). Accessing the UI from a browser **inside** the
> booth desktop works regardless and needs no port publishing at all.

## Cleanup

```bash
./access-app-stop.sh   # Stop port-forwards
./remove-app.sh        # Remove app from cluster
./stop-cluster.sh      # Delete KIND cluster
```
