# booth expose

> Started a server on a new port? Access it from the host without restarting your booth.

`booth--expose` creates a TCP tunnel through the Docker runtime, making any internal container port accessible from the host — at runtime, with no container restart.

```bash
# Inside the booth:
booth--expose 8080
# → TCP tunnel: container localhost:8080 → host localhost:8080
# Note: this tunnel lasts until the booth stops; use 'booth config --expose' to keep it.
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Port Syntax](#port-syntax)
- [Lifetime](#lifetime)
- [Closing a tunnel](#closing-a-tunnel)
- [Listing ports](#listing-ports)
- [The other direction: reaching a service on the host](#the-other-direction-reaching-a-service-on-the-host)
- [Relationship to -p and --expose](#relationship-to--p-and---expose)
- [Security](#security)
- [Limitations](#limitations)

---

## Overview

Docker port mappings (`-p`) are fixed at container creation. If you start a web server, database, or any service on a port that was not exposed upfront, you normally have to stop and recreate the container with the new port mapping.

`booth--expose` solves this by tunneling TCP traffic via `docker exec` and `socat` (`podman exec` when the booth runs on Podman, see [Podman support](PODMAN_SUPPORT.md)). The running booth process on the host detects the tunnel request and automatically opens a local port that forwards traffic into the container.

- Works for **all TCP traffic** — HTTP, databases, gRPC, raw TCP
- Works in **all variants** — base, terminal, codeserver, notebook, desktop
- **No SSH server** required
- **No extra ports** need to be exposed on the container
- The host-side booth process sets up the listener **automatically**

---

## How It Works

Two cooperating pieces:

**Inside the container:** `booth--expose` writes a control file to `.booth/.tmp/tcp-tunnels/`.

**Outside the container:** The running booth process (in foreground mode) watches `.booth/.tmp/tcp-tunnels/` for changes. When a new tunnel is requested, it opens a local port on the host and forwards each connection via `docker exec -i <container> socat STDIO TCP:localhost:<port>`.

```
Host                          Container
┌──────────────┐              ┌──────────────────────┐
│ localhost:8080 ──docker exec──→ socat STDIO TCP:8080  │
│ (auto-created)  │              │         ↓              │
│                 │              │   localhost:8080       │
└──────────────┘              └──────────────────────┘
```

---

## Port Syntax

```bash
booth--expose <container-port> [external-port]
```

### Explicit external port

```bash
booth--expose 8080 18080
# container localhost:8080 → host localhost:18080
```

### Relative to the offset base (`+`)

```bash
booth--expose 8080 +8080
# If booth port is 10000: container localhost:8080 → host localhost:18080
# If booth port is 12000: container localhost:8080 → host localhost:20080
```

The `+` prefix adds the value to the **offset base**, which is the booth port unless the booth was
started with `--offset-base` (see [Booth Run → Ports](BOOTH_RUN.md#ports)). Following the booth port
keeps port assignments predictable regardless of which port the booth is running on — two booths of
the same project sit on different booth ports and so tunnel to different host ports.

A booth that owns the whole host — a cloud one, typically — has no such collision to dodge and a
front door on a port it did not choose, so it sets a base of its own instead:

```bash
booth --port 443 --offset-base 20000
# inside: booth--expose 8080 +8080  gives container localhost:8080 → host localhost:28080
```

### Default (no external port)

```bash
booth--expose 8080
# container localhost:8080 → host localhost:8080
```

When no external port is specified, it defaults to the same port number.

### Examples

| Command | Offset Base | Host Port | Container Port |
|---------|-------------|-----------|----------------|
| `booth--expose 3000` | 10000 | 3000 | 3000 |
| `booth--expose 3000 +3000` | 10000 | 13000 | 3000 |
| `booth--expose 8080 +8080` | 10000 | 18080 | 8080 |
| `booth--expose 5432 +5432` | 12000 | 17432 | 5432 |
| `booth--expose 8080 +8080` | 0 (`--offset-base 0`) | 8080 | 8080 |
| `booth--expose 3000 23000` | 10000 | 23000 | 3000 |

The offset base is the booth port unless `--offset-base` moved it, so the first four rows are also
"booth port 10000 / 10000 / 10000 / 12000".

---

## Lifetime

A tunnel lasts until the booth stops. Its control file lives in `.booth/.tmp/tcp-tunnels/`, which
is cleaned on booth exit and startup (see [booth tmp](BOOTH_TMP.md)).

```bash
booth--expose 8080
```

Output:
```
TCP tunnel: container localhost:8080 → host localhost:8080
Note: this tunnel lasts until the booth stops; use 'booth config --expose' to keep it.
```

To keep a port across restarts, publish it instead. Run `booth config` on the host with
`--expose`, which accepts the same `+OFFSET` form:

```bash
booth config --expose 8080          # host 8080 → container 8080
booth config --expose +8080         # host <offset-base>+8080 → container 8080
```

That becomes a Docker port mapping in `.booth/config.toml`, and it takes effect the next time the
booth starts. See [Relationship to -p and --expose](#relationship-to--p-and---expose).

---

## Closing a tunnel

```bash
booth--expose close 8080               # stop forwarding container:8080 to the host
```

A tunnel lives exactly as long as its control file in `.booth/.tmp/tcp-tunnels/`: `close`
removes the file, and the host-side booth process closes the listener within a second
(`Tunnel closed: …` in its output). The port can be exposed again straight away.

`close` only covers tunnels. Ports published when the container was created (`-p`, `booth config
--expose`, a template's `+expose`) are Docker port mappings and stay until the booth is recreated
without them.

## Listing ports

Two commands report what a booth exposes and where — one from the host, one from
inside the booth. They read the same run-time manifest (`.booth/.tmp/ports.json`,
written when the booth starts) plus the live runtime tunnels, so both sides agree
on the mappings; each then adds what only its vantage point can see.

### From the host: `booth expose list`

Shows every port the booth publishes to the host — the booth front door, any
published (`-p`) ports, and any runtime tunnels — and confirms each against
`docker port` (the `LIVE` column). With no name, the booth for the current
directory is used.

```bash
booth expose list                 # the current directory's booth
booth expose list demo            # a booth by name
booth expose list --name demo
```

```
CONTAINER  HOST             PROTO  KIND        LIVE  SOURCE
10000      127.0.0.1:11000  tcp    front door  yes   booth front door
13000      0.0.0.0:13000    tcp    published   yes   published (-p)
12222      0.0.0.0:19888    tcp    published   yes   published (-p)
5432       127.0.0.1:5432   tcp    tunnel      yes   booth--expose
```

If the manifest is absent (an older booth, or one brought up with `docker
start`), the live `docker port` view is used instead — the mappings still show,
just without their `SOURCE` labels.

### From inside the booth: `booth--expose list`

Shows the same published ports and tunnels, and adds — from `ss` — **which
process is listening** on each port and whether it is actually up. It also
surfaces **internal-only** services that are listening but not published to the
host (a good way to discover a port worth `booth--expose`-ing).

```bash
booth--expose list
```

```
CONTAINER HOST                   PROTO KIND        STATUS  SERVER
10000     127.0.0.1:11000        tcp   front door  up      nginx
13000     0.0.0.0:13000          tcp   published   up      node
12222     0.0.0.0:19888          tcp   published   up      jupyter-lab
5432      127.0.0.1:5432         tcp   tunnel      up      -
14444     -                      tcp   internal    up      websockify
```

A `SERVER` of `-` means the process is owned by another user and `ss` could not
name it; a `KIND` of `internal` with no `HOST` means the service listens inside
the container but is not published to the host.

---

## The other direction: reaching a service on the host

Everything above carries a port **out** of the booth. Going the other way — a
booth talking to a database, an API, or a language server that runs on your
host — needs no tunnel and no configuration: the host is always reachable at
`host.docker.internal`.

```bash
# Inside the booth, against a PostgREST on the host's port 3000:
curl http://host.docker.internal:3000/

# Or a PostgreSQL on 5432:
psql -h host.docker.internal -p 5432 -U postgres
```

Every booth is started with that name mapped to the host, so the same command
works on Linux, macOS, and Windows. `booth--info` reports what it resolves to,
along with the host's own address on its network:

```
=== Host Access ===

Host:     host.docker.internal -> 192.168.65.254
Host IP:  192.168.1.42  ($BOOTH_HOST_IP -- the host's address on its own network)
```

Two variables carry the same facts for scripts, and both show up in `booth--envs`:

| Variable | What it holds |
|---|---|
| `BOOTH_HOST_NAME` | The name to dial — always `host.docker.internal` |
| `BOOTH_HOST_IP` | The host's IPv4 address on its own network. Unset if the host has none (no interface up beyond loopback) |

Prefer `BOOTH_HOST_NAME`. `BOOTH_HOST_IP` is the address the *rest of the
network* uses to reach your machine — the one to hand to a colleague, or to put
in a config that has to name an address rather than a host — and it changes when
you move between networks, while the name does not.

**The service must not be bound to `127.0.0.1` only.** A host-local bind is
unreachable from inside any container; the service has to listen on `0.0.0.0`
(or on the host's LAN address). This is the single most common reason a host
service "cannot be reached" from a booth. For PostgREST that is
`server-host = "0.0.0.0"`; for a dev server it is usually `--host 0.0.0.0`.

**Under `--egress`** the booth's traffic goes through the egress proxy, which
allows only what its policy allows. The host alias is set up the same way (on
the sidecar that owns the network namespace), but reaching a host service still
requires the egress allowlist to permit it — that restriction is the point of
running with `--egress`.

---

## Relationship to `-p` and `--expose`

CodingBooth has three ways to make container ports accessible. Each serves a different purpose:

| Method | When Decided | Survives Restart | Mechanism |
|--------|-------------|-----------------|-----------|
| `-p` (Docker port mapping) | Container creation | Yes (if keep-alive) | Docker native |
| `--expose` in `booth config` | Configuration time | Yes | Writes `-p` to run-args |
| `booth--expose` (TCP tunnel) | Runtime | No | docker exec + socat |

**Use `-p` / `--expose`** when you know the ports upfront. These are Docker-native port mappings — no overhead, full performance.

**Use `booth--expose`** when you discover a port at runtime. It tunnels via `docker exec`, so there is some overhead compared to a native port mapping, but it works without restarting the container.

> **Tip:** If you find yourself using `booth--expose` for the same port every time, add it with `booth config --expose <port>` so it is published every time the booth starts.

---

## Security

The tunnel uses `docker exec` (or `podman exec`) to bridge connections, which requires access to the container engine. Only processes that can run `docker exec` on the container (i.e., the host-side booth process) can create tunnels.

**Where the tunnel listens follows the booth.** A booth started without `--public` binds its tunnels to `localhost`, so they are not reachable from other machines. A booth started with `--public` binds them to `0.0.0.0`, the same as its own published port:

| Booth | Tunnel listens on | Reachable from |
|-------|-------------------|----------------|
| default | `localhost:<port>` | the host only |
| `--public` | `0.0.0.0:<port>` | anything that can route to the host |

This is what makes `booth--expose` useful on a remote or hosted booth, where "the host" is not the machine holding the browser. It also means the exposed service is reachable by whoever can reach that host: the tunnel adds **no authentication and no TLS** of its own, unlike the booth's own port, which is password-protected. A development server tunneled out of a public booth is public — check that it is meant to be.

Because of that, `booth--expose` **refuses** to open a tunnel on a public booth unless you pass `--ok-public`:

```
$ booth--expose 8080 28080
Error: this booth is public — port 28080 would be open on
       every interface with NO password and NO TLS of its own.
       Pass --ok-public if that is what you mean.
```

```
$ booth--expose 8080 28080 --ok-public
TCP tunnel: host localhost:28080 -> container localhost:8080
⚠️  This booth is public — port 28080 is now open on every
   interface with NO password and NO TLS of its own.
```

`--ok-public` is a one-off acknowledgement for that single call — it is never read from `.booth/config.toml` or an environment variable, the same as `--public` and the password itself, so a committed config file can never pre-approve this.

A tunnel lasts until its control file under `.booth/.tmp/tcp-tunnels/` is removed (deleting the file closes the listener within a second), or until the booth restarts, which clears `.booth/.tmp/` along with every ephemeral tunnel.

The same check applies at booth startup — before any tunnel is even opened — if a `--public` booth already publishes an extra port (a template's own `+expose`, or `--expose` at config time): the booth refuses to start without `--ok-public` on the `codingbooth`/`booth` command line, and warns even with it:

```
$ codingbooth --public
Error: this booth is public. Port(s) 18080 would be open on every
       interface with NO password and NO TLS of their own — only the
       booth's own port (https://localhost:13000) is protected.
       Pass --ok-public if that is what you mean.

$ codingbooth --public --ok-public
⚠️  This booth is public. Port(s) 18080 have no password or TLS of
   their own — only the booth's own port (https://localhost:13000) is protected.
```

---

## Limitations

- **TCP only** — `socat` bridges TCP connections. UDP protocols are not supported.
- **Foreground mode required** — The host-side booth process must be running to watch for tunnel requests and create listeners. This works in foreground mode (the default). For daemon mode, use `-p` / `--expose` at configuration time instead.
- **Per-connection overhead** — Each TCP connection spawns a `docker exec` process. For development use (a handful of concurrent connections) this is negligible, but high-throughput scenarios may notice latency.
- **Port availability** — If the requested host port is already in use, the tunnel fails with an error. Choose a different external port or use `+` syntax for predictable allocation.
- **Host ports below 1024** — The tunnel listens on the host's `localhost`, and a normal user may not open a port below 1024 there: macOS allows it only on every interface, Linux not at all. `booth--expose 8080 80` therefore fails with `permission denied` (with a hint to pick 1024 or above) on any engine; use e.g. `booth--expose 8080 8080`. The error is printed once; the tunnel keeps retrying quietly, so freeing the port lets it open. This is about the *host* port — a port below 1024 *inside* an Apple container booth is [`--apple-low-ports`](CONTAINER_SUPPORT.md#ports-below-1024---apple-low-ports).
