# Appwrite Example

This example is a booth that runs [Appwrite](https://appwrite.io) — an open-source
Backend-as-a-Service — locally, with the official CLI already pointed at it. Auth,
databases, storage, and a console UI come out of one selector. There is no native
Appwrite install: the server is the official Docker Compose stack, started inside
Docker-in-Docker (`appwrite-server+autostart`, which pulls in `dind` and
`docker-compose`). `just run` waits for `/v1/health/version` and shows the CLI talking
to that local endpoint.

**Stack:** Appwrite CLI + Appwrite Server + Docker-in-Docker, port 8080

Appwrite wants about **4GB RAM** and the first boot downloads many images — later
starts reuse them.

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/appwrite-example
booth

# 2. Inside the booth — wait for health and point the CLI at localhost
just --list
just run                 # ./demo.sh
```

From the host, the console is published on port 8080 (`+expose`):
[http://localhost:8080](http://localhost:8080). First start creates
`admin@example.com` / `password123`. This example is **clean** data — every
`booth` is a new Appwrite. `+seed` starts from a home-seed snapshot (writes
do not stick); `+persist` keeps data in `.booth/cache` on this machine.

## What to try

The CLI is already installed. Once `just run` has printed a version JSON, these are
ordinary Appwrite CLI commands against the booth's own server:

```bash
appwrite -v
appwrite client --endpoint http://localhost:8080/v1 --self-signed true
appwrite client --debug
```

Open the console at `http://localhost:8080`, create a project, then:

```bash
appwrite init project
```

`just run` is the scripted form of the health check (`./demo.sh`). Either path is
fine; the typed commands are how you would actually use Appwrite in a project.

## What's included

| Component     | Details                                              |
|---------------|------------------------------------------------------|
| Server        | Appwrite self-hosted (port 8080, Compose via DinD)   |
| CLI           | `appwrite` (required by the server template)         |
| Docker        | DinD sidecar + Compose, required by `start-appwrite` |
| Persistence   | `APPWRITE_DATA=clean` (default). `+seed` / `+persist`    |
| Sample        | `demo.sh` — CLI version + API health round-trip      |

Select a different server version with `APPWRITE_VERSION`, or a different listen
port with `APPWRITE_PORT`, via `booth config`. The CLI version is `APPWRITE_CLI_VERSION`.
Data policy is `APPWRITE_DATA` (`clean` / `seed` / `persist`); `+seed` and
`+persist` install the CodingBooth home-seed / cache backing. For persist, run
`stop-appwrite` (or shut the booth down) so volumes dump into `~/.appwrite-server`.

`.booth/setups/` copies `appwrite-cli--setup.sh` and `appwrite-server--setup.sh` so
this example builds against a released base image that does not yet ship them.
Keep those copies byte-identical with `variants/base/setups/`.
