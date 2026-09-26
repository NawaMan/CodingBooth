# KinD (Kubernetes in Docker) Example

This example runs a full Kubernetes cluster entirely inside a CodingBooth using KinD on top of Docker-in-Docker. `start-cluster.sh` creates a KinD cluster in the DinD sidecar and `deploy-app.sh` deploys a sample nginx app on NodePort 30080 (plus a buildable hello-service on 30081) — viewable right in the console UI's own tabs (no desktop or browser needed), and `k9s` gives you a live TUI view of the cluster from the terminal. The whole cluster — control plane, nodes, and pods — is nested inside the booth, so you get a throwaway Kubernetes environment without installing kind, kubectl, or a single container runtime on your own machine. Kick the tires on manifests, ingress, and NodePorts, then delete the entire cluster by stopping the booth — no lingering `~/.kube` config, no orphaned Docker networks, no "why is my laptop running eight etcd pods" surprise later. It's a real cluster you can be genuinely careless with.

This is a plain (non-desktop) booth, using the multi-pane console UI rather than a full remote desktop — `.booth/console.json` defaults it to a "Left Main" layout with the Markdown viewer pane on the left, so notes/docs and the terminal are visible side by side from the first load.

## Quick start

```bash
# 1. Launch the booth
cd examples/kind-example
../../codingbooth

# 2. Inside the booth — create the cluster
just --list
just start               # ./start-cluster.sh

# 3. Deploy the sample nginx app
just deploy              # ./deploy-app.sh

# 4. Verify it works (inside the booth)
curl http://localhost:30080

# 5. Try the hello-service too
./deploy-hello.sh
curl http://localhost:30081
curl http://localhost:30081/health

# 6. Clean up
./remove-hello.sh
./remove-app.sh
just stop                # ./stop-cluster.sh
```

See [Viewing services](#viewing-services) for how to open these as tabs right in the console UI.

## How it works

The workspace uses the **sidecar DinD** approach:

1. A DinD sidecar container runs the Docker daemon
2. The workspace container connects to it via `DOCKER_HOST=tcp://dind:2375`
3. KinD creates Kubernetes nodes as containers inside the DinD sidecar
4. The workspace can access K8s API and services via the DinD sidecar's hostname

```
Host
└── Workspace container (this)
    │   - has kubectl, kind installed
    │   - DOCKER_HOST=tcp://{dind}:2375
    │
    └── DinD sidecar (same network)
        └── Docker daemon
            ├── kind-control-plane container
            │   - K8s API on :6443
            │   - NodePorts on :30080-30084
            └── (K8s pods run inside)
```

## Network

The workspace shares DinD's network namespace (`--network container:dind`), which means:
- **`localhost` inside the workspace = `localhost` inside DinD**
- No hostname configuration needed — just use `localhost`

NodePorts need `extraPortMappings` in kind config to be accessible.
The `start-cluster.sh` script configures this automatically.

## Exposed ports

The following ports are pre-mapped and accessible via `http://localhost:{port}`:

| Port        | Purpose                |
|-------------|------------------------|
| 6443        | Kubernetes API server  |
| 80          | HTTP (for ingress)     |
| 443         | HTTPS (for ingress)    |
| 30080-30084 | NodePort services      |

## Viewing services

No desktop or browser here — the console UI's own tabs can load a web page directly.
Click a pane's "+" (new tab), then type into its address bar:

- `booth:30080` — nginx welcome page
- `booth:30081` — hello-service

(`booth:<port>` is the console's shorthand for "this booth, this port" — the same
thing typing `http://booth:30080` does.) `.booth/console.json` already opens the
Markdown viewer this way in the left pane by default; the same mechanism works for
any port the booth exposes.

These are only reachable from *inside* the booth — the ports aren't published to your
host machine by default. If you want that too, add `-p 30080:30080` (and any other
NodePort you use) to `run-args` in `.booth/config.toml`, matching the port(s)
`start-cluster.sh` maps.

## Watching the cluster (k9s)

[k9s](https://k9scli.io/) is installed — a terminal UI for browsing and managing a
live cluster. From any terminal in the booth, once a cluster exists:

```bash
k9s
```

It picks up the current kubectl context (`kind-kind` after `start-cluster.sh`)
automatically. `?` for help, `:pod`/`:svc`/`:deploy` to switch resource views, `Ctrl+C`
to quit.

## Scripts

| Script                   | Description                                       |
|--------------------------|---------------------------------------------------|
| `start-cluster.sh`      | Creates a KinD cluster with proper networking     |
| `stop-cluster.sh`       | Deletes the KinD cluster                          |
| `check-cluster.sh`      | Checks if the cluster is running                  |
| `deploy-app.sh`         | Deploys a sample nginx app with NodePort 30080    |
| `remove-app.sh`         | Removes the sample nginx app                      |
| `deploy-hello.sh`       | Builds and deploys hello-service (NodePort 30081) |
| `remove-hello.sh`       | Removes hello-service                             |
| `test-on-container.sh`  | Tests scripts inside the container                |
| `test-on-host.sh`       | Full integration test from the host               |

## Run tests

From inside the container:
```bash
./test-on-container.sh
```

From the host:
```bash
./test-on-host.sh
```

## Adding more NodePorts

Edit `start-cluster.sh` and add more entries to `extraPortMappings`:

```yaml
- containerPort: 30085
  hostPort: 30085
  listenAddress: "0.0.0.0"
  protocol: TCP
```

Then recreate the cluster.
