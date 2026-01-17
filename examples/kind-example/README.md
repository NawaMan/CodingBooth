# KinD (Kubernetes in Docker) Example

This example demonstrates running a Kubernetes cluster inside the workspace using KinD and DinD (Docker in Docker).

## How It Works

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

## Network Configuration

The workspace shares DinD's network namespace (`--network container:dind`), which means:
- **`localhost` inside the workspace = `localhost` inside DinD**
- No hostname configuration needed - just use `localhost`

### NodePort Access
- KinD nodes run inside DinD's internal Docker network
- NodePorts need `extraPortMappings` in kind config to be accessible
- The `start-cluster.sh` script configures this automatically

## Exposed Ports

The following ports are pre-mapped and accessible via `http://localhost:{port}`:

| Port       | Purpose                    |
|------------|----------------------------|
| 6443       | Kubernetes API server      |
| 80         | HTTP (for ingress)         |
| 443        | HTTPS (for ingress)        |
| 30080-30084| NodePort services          |

## Scripts

| Script                 | Description                                    |
|------------------------|------------------------------------------------|
| `start-cluster.sh`     | Creates a KinD cluster with proper networking  |
| `stop-cluster.sh`      | Deletes the KinD cluster                       |
| `check-cluster.sh`     | Checks if the cluster is running               |
| `deploy-app.sh`        | Deploys a sample nginx app with NodePort 30080 |
| `remove-app.sh`        | Removes the sample nginx app                   |
| `deploy-hello.sh`      | Builds and deploys hello-service (NodePort 30081) |
| `remove-hello.sh`      | Removes hello-service                          |
| `test-on-container.sh` | Tests scripts inside the container             |
| `test-on-host.sh`      | Full integration test from the host            |

## Usage

### Start the workspace

```bash
cd examples/kind-example
../../workspace
```

### Inside the workspace

```bash
# Create a KinD cluster
./start-cluster.sh

# Check cluster status
./check-cluster.sh
kubectl get nodes

# Deploy sample app (uses NodePort 30080)
./deploy-app.sh

# Access the app via localhost
curl http://localhost:30080

# Clean up
./remove-app.sh
./stop-cluster.sh
```

### Run tests

From inside the container:
```bash
./test-on-container.sh
```

From the host:
```bash
./test-on-host.sh
```

## Configuration

The `.ws/config.toml` enables DinD mode:
```toml
variant  = "xfce"
dind     = true
```

The `.ws/Dockerfile` installs:
- Docker CLI and DinD support
- kubectl
- kind

## Adding More NodePorts

To expose additional NodePorts, edit `start-cluster.sh` and add more entries to `extraPortMappings`:

```yaml
- containerPort: 30085
  hostPort: 30085
  listenAddress: "0.0.0.0"
  protocol: TCP
```

Then recreate the cluster.
