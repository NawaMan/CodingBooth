# Appwrite Example

This example is a booth that runs [Appwrite](https://appwrite.io) — an open-source
Backend-as-a-Service — locally, with the official CLI already pointed at it. Auth,
databases, storage, and a console UI come out of one selector. There is no native
Appwrite install: the server is the official Docker Compose stack, started inside
Docker-in-Docker (`appwrite-server+autostart`, which pulls in `dind` and
`docker-compose`). `just run` waits for `/v1/health/version` and shows the CLI talking
to that local endpoint.

**Stack:** Appwrite CLI + Appwrite Server + Docker-in-Docker + Node.js 24, ports 8080 (console/API) and 5173 (Svelte starter)

Appwrite wants about **4GB RAM** and the first boot downloads many images — later
starts reuse them.

## Appwrite and Firebase

If you know Firebase, Appwrite fills the same role: auth, a document database, file storage,
functions, realtime and a web console, used from a client SDK rather than a backend you write.
The difference is who runs it. Firebase lives only in Google's cloud. Appwrite is open source and
can run anywhere Docker does — here, entirely inside the booth (offline once its images are pulled),
with fresh data on every start. Compare [`firebase-example`](../firebase-example/), where only the CLI is in the booth and
the backend stays in the cloud, and [`pocketbase-example`](../pocketbase-example/), a backend
built into a single Go binary.

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/appwrite-example
booth

# 2. Inside the booth — wait for health and point the CLI at localhost
just --list
just run                 # ./demo.sh
just web                 # ./web.sh — the Svelte starter on :5173
```

Appwrite runs on Docker-in-Docker, a privileged sidecar, so `booth` warns and asks
`Start this booth? [y/N]` before it starts. Type `y` and press Enter for code you trust; anything
else, a bare Enter included, aborts. `booth --dind-allowed` skips the question (the warning still
prints) — the only way to run it from a script. See [Security](https://github.com/NawaMan/CodingBooth/blob/main/docs/BOOTH_SECURITY.md#dind).

From the host, the console is published on port 8080 (`+expose`):
[http://localhost:8080](http://localhost:8080), or through the booth's own port at
[http://localhost:10000/proxy/8080/console/](http://localhost:10000/proxy/8080/console/) (a
plain tab, or the globe pane in the Console UI). `just run` prints both for the booth's actual
port. First start creates
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

## The Svelte starter

`starter-for-svelte/` is Appwrite's own
[Svelte starter](https://github.com/appwrite/starter-for-svelte), copied in unchanged. It is a
one-page SvelteKit app with a **Send a ping** button that calls `client.ping()`. Out of the box
it points at Appwrite Cloud. Here it points at this booth's server:

```bash
just web                 # inside the booth (or from the host — it starts one)
```

`just web` runs `just app` first (`./appwrite-app.sh`), which signs in as the console admin,
creates a team, a `starter` project and a `localhost` web platform — each skipped when it is
already there — and writes `starter-for-svelte/.env` (gitignored) with the host-side endpoint.
Then it installs the starter's packages and serves it with Vite. Open
[http://localhost:5173](http://localhost:5173) and press **Send a ping**: the log row shows
`200 /v1/ping {"message":"Pong!"}` from your own Appwrite. It also works through the booth
port at [http://localhost:10000/proxy/5173/](http://localhost:10000/proxy/5173/).

### Seeing both ends

The page's **Logs** list is the browser's side: it lives in the page and resets on reload. To
watch the same pings land on the server, open a second terminal pane beside the starter:

```bash
just watch               # one line per /v1/ping as Appwrite receives it (Ctrl+C stops)
just pings               # the project's own counter: pingCount and pingedAt
```

```
#1   02:09:03  GET /v1/ping → 200      ← the check at the end of just app
#2   02:09:34  GET /v1/ping → 200      ← Send a ping
```

`just pings` counts one more than the page shows, because `just app` sends its own ping to
check the setup. `just watch` reads the API container's log, so it lists pings since that
container started; `pingCount` is kept with the project. Don't use the console's **Requests**
chart to count pings: it is a usage statistic that a background worker adds up later. On
Appwrite 1.9.6 it showed 2 for 4 pings.

The browser runs on the host, so `.env` names the *host* ports: the booth port minus the
offsets in `.booth/config.toml` (`+-1920` → 8080 for Appwrite, `+-4827` → 5173 for Vite, with
the default booth port 10000). On another booth port they move together; `APPWRITE_HOST_PORT`
and `WEB_HOST_PORT` override them.

Data is `clean`, so a new booth has no `starter` project — `just app` (and `just web`) create
it again.

## What's included

| Component     | Details                                              |
|---------------|------------------------------------------------------|
| Server        | Appwrite self-hosted (port 8080, Compose via DinD)   |
| CLI           | `appwrite` (required by the server template)         |
| Docker        | DinD sidecar + Compose, required by `start-appwrite` |
| Persistence   | `APPWRITE_DATA=clean` (default). `+seed` / `+persist`    |
| Runtime       | Node.js 24, for the Svelte starter                   |
| Sample        | `demo.sh` — CLI version + API health round-trip      |
| App           | `starter-for-svelte/` — `just web`, wired by `appwrite-app.sh` |

Select a different server version with `APPWRITE_VERSION`, or a different listen
port with `APPWRITE_PORT`, via `booth config`. The CLI version is `APPWRITE_CLI_VERSION`.
Data policy is `APPWRITE_DATA` (`clean` / `seed` / `persist`); `+seed` and
`+persist` install the CodingBooth home-seed / cache backing. For persist, run
`stop-appwrite` (or shut the booth down) so volumes dump into `~/.appwrite-server`.
