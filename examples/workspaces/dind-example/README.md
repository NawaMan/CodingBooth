# Docker-in-Docker (DinD) Example

This example runs a full Docker engine inside a CodingBooth without ever touching your host's Docker socket. With `dind = true`, a DinD sidecar container runs its own Docker daemon, and `start-server.sh` builds an image and runs a Python `http.server` container on port 8080, all nested inside the booth. Because the containers live in a nested daemon rather than on your host, you get full `docker build`/`docker run` without the classic escape hatch of bind-mounting `/var/run/docker.sock` — which effectively hands the container root on your machine. Experiment as recklessly as you like: fill the image cache, wedge the daemon, spawn a swarm of containers, then throw it all away by simply stopping the booth, with your host Docker never touched. That's the safe way to let an AI agent or a CI script drive Docker.

## Table of Contents

- [Quick Start](#quick-start)
- [Why Run Docker-in-Docker in CodingBooth?](#why-run-docker-in-docker-in-codingbooth)
- [Architecture](#architecture)
- [Scripts](#scripts)
- [Configuration](#configuration)


## Why Run Docker-in-Docker in CodingBooth?

Running Docker inside CodingBooth provides a **secure, isolated environment** for container workloads:

| Benefit                  | Description                                                                                                              |
|--------------------------|--------------------------------------------------------------------------------------------------------------------------|
| **No Socket Sharing**    | Your host Docker socket stays private. No risk of container escape or accidental host modifications.                    |
| **Reproducibility**      | Every developer gets the same Docker environment. No version mismatches, no conflicting images or networks.             |
| **Isolation**            | All images, containers, and networks live inside the booth. Host system stays clean.                                    |
| **Safe Experimentation** | Break things freely. Corrupt your Docker state? Just restart the booth. No impact on host or other projects.            |
| **Clean Teardown**       | When you're done, everything disappears. No orphaned containers, dangling images, or zombie networks on your host.      |
| **CI/CD Ready**          | The same containerized environment runs locally and in CI pipelines, eliminating environment drift.                     |

This is the foundation for running Kubernetes (KIND), building multi-container apps, or any Docker-based workflow in complete isolation.

## Quick Start

```bash
# Start the workspace
cd examples/workspaces/dind-example
../../codingbooth

# Inside the workspace, Docker is ready:
docker run hello-world

# Build and run the example server:
./start-server.sh    # Build image and start container
./check-server.sh    # Verify it's running
curl localhost:8080  # Test the server
./stop-server.sh     # Stop and cleanup
```

## Architecture

```
Host
└── DinD sidecar container
    ├── Docker daemon (:2375)
    │   └── Your containers (http-server, etc.)
    └── Workspace container (shares DinD network)
        ├── Docker CLI (connects to sidecar)
        └── Your code mounted at /home/coder/code
```

The DinD sidecar runs a full Docker daemon. The workspace container connects to it via the shared network, so `docker` commands work seamlessly.

## Scripts

| Script                 | Description                                                                     |
|------------------------|---------------------------------------------------------------------------------|
| `./start-server.sh`    | Builds the http-server image and starts it in daemon mode with port forwarding |
| `./stop-server.sh`     | Stops the http-server container and closes port forwarding                     |
| `./check-server.sh`    | Checks if the server is running (green checkmark if up, red X if down)         |
| `./test-on-container.sh` | Tests start/check/stop scripts inside the container                          |

## Configuration

`.booth/config.toml`:
```toml
variant  = "desktop-xfce"
dind     = true
run-args = [
    "-p", "8080:8080",
    "-p", "3000:3000",
]
```

Setting `dind = true` automatically:
- Creates a DinD sidecar container with a Docker daemon
- Creates a network connecting the sidecar and workspace
- Configures the workspace to use the sidecar's Docker daemon

## Cleanup

Just stop the booth — the DinD sidecar, network, and all containers inside are cleaned up automatically.
