# KinD (Kubernetes in Docker) Example

Run a full Kubernetes cluster inside a CodingBooth using KinD and DinD (Docker in Docker).

## Quick start

```bash
# 1. Launch the booth
cd examples/kind-example
../../codingbooth

# 2. Inside the booth — create the cluster
./start-cluster.sh

# 3. Deploy the sample nginx app
./deploy-app.sh

# 4. Verify it works (inside the booth)
curl http://localhost:30080

# 5. Open in your host browser
#    http://localhost:30080    — you should see the nginx welcome page

# 6. Try the hello-service too
./deploy-hello.sh
curl http://localhost:30081
curl http://localhost:30081/health

# 7. Clean up
./remove-hello.sh
./remove-app.sh
./stop-cluster.sh
```

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
