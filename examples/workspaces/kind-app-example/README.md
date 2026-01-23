# TODO App on KIND - Full-Stack Kubernetes Example

A real-world TODO application deployed to KIND (Kubernetes IN Docker), demonstrating microservices architecture with React, Go, and PostgreSQL.

## Quick Start

**Interactive Guides (Jupyter Notebooks):**
- [`TODO-App-Guide.ipynb`](TODO-App-Guide.ipynb) - Deploy to KIND (local Kubernetes)
- [`TODO-App-AWS-EKS-Guide.ipynb`](TODO-App-AWS-EKS-Guide.ipynb) - Deploy to AWS EKS (cloud)

```bash
# Start the workspace
cd examples/workspaces/kind-app-example
../../coding-booth

# Inside the workspace, run:
./start-cluster.sh   # Create KIND cluster
./build.sh           # Build Docker images
./deploy-app.sh      # Deploy to Kubernetes
./access-app.sh      # Start port-forwards

# Open http://localhost:3000 in your browser
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  KIND Cluster (todo-app namespace)                              │
│                                                                 │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────────┐ │
│   │    React     │      │   Go API     │      │   Export     │ │
│   │   (nginx)    │─────▶│   Service    │─────▶│   Service    │ │
│   │   web:80     │ /api │   api:8080   │ HTTP │ export:8081  │ │
│   └──────────────┘  /ws └──────────────┘      └──────────────┘ │
│                              │                                  │
│                              ▼                                  │
│                        ┌──────────────┐                        │
│                        │  PostgreSQL  │                        │
│                        │ postgres:5432│                        │
│                        └──────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

| Component | Technology |
|-----------|------------|
| Frontend | React 18 + TypeScript + Vite + Tailwind CSS + Bun |
| API | Go 1.21 + Chi router + gorilla/websocket |
| Export Service | Go 1.21 + Chi router |
| Database | PostgreSQL 15 |
| Web Server | nginx |
| Container | Docker + KIND (Kubernetes IN Docker) |

## Ports

| Port | Service | Description |
|------|---------|-------------|
| 3000 | Web UI | React frontend |
| 8080 | API | Go REST API + WebSocket |
| 8081 | Export | Export service (CSV/JSON) |

## Scripts

| Script | Description |
|--------|-------------|
| `./status.sh` | Show cluster, pods, services, and port-forward status |
| `./start-cluster.sh` | Create KIND cluster |
| `./stop-cluster.sh` | Delete KIND cluster |
| `./check-cluster.sh` | Check if cluster is running |
| `./build.sh` | Build all Docker images |
| `./deploy-app.sh` | Deploy TODO app to cluster |
| `./remove-app.sh` | Remove TODO app from cluster |
| `./access-app.sh` | Start port-forwards to access app from host |
| `./access-app-stop.sh` | Stop port-forwards |

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | /api/tasks | List all tasks |
| POST | /api/tasks | Create a task |
| GET | /api/tasks/:id | Get a task |
| PUT | /api/tasks/:id | Update a task |
| DELETE | /api/tasks/:id | Delete a task |
| GET | /api/export?format=csv\|json | Export tasks |
| WS | /ws | WebSocket for real-time updates |

## Project Structure

```
kind-app-example/
├── TODO-App-Guide.ipynb  # Interactive Jupyter notebook guide
├── .booth/
│   ├── config.toml       # Workspace config (DinD, ports)
│   └── Dockerfile        # Workspace image with kubectl, kind, go, bun
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

Port-forwards use `--address 0.0.0.0` to make services accessible from the host through the DinD sidecar's port mappings.

## Configuration

`.booth/config.toml`:
```toml
variant  = "xfce"
dind     = true
run-args = [
    "-p", "3000:3000",
    "-p", "8080:8080",
    "-p", "8081:8081",
]
```

## Cleanup

```bash
./access-app-stop.sh   # Stop port-forwards
./remove-app.sh        # Remove app from cluster
./stop-cluster.sh      # Delete KIND cluster
```
