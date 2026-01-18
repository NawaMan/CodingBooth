# Docker in Docker example

This example shows the use of DinD (Docker in Docker).
It allows user to run a docker container include the workspace container.

This is an experimental feature due to some limitation.

The feature is implemented by creating a side-car container to run the workspace-container on 
  and a network to connect the side-car with the workspace-container.
The initial idea is to avoid sharing the docker socket to the host.
But this cause some inconvinient as the port are in a different network so to use the expose docker in the workspace container.

This implementation will be revisited if it is later shown that we can't do anything useful (particularly related to K8s).

## Scripts

| Script                 | Description                                                                    |
|------------------------|--------------------------------------------------------------------------------|
| `start-server.sh`      | Builds the http-server image and starts it in daemon mode with port forwarding |
| `stop-server.sh`       | Stops the http-server container and closes port forwarding                     |
| `check-server.sh`      | Checks if the server is running (green ✓ if up, red ✗ if down)                 |
| `test-on-container.sh` | Tests start/check/stop scripts inside the container                            |
| `test-on-host.sh`      | Full integration test including host port accessibility                        |
