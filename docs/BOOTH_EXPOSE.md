# booth expose

> Started a server on a new port? Access it from the host without restarting your booth.

`booth--expose` creates a TCP tunnel through the Docker runtime, making any internal container port accessible from the host — at runtime, with no container restart.

```bash
# Inside the booth:
booth--expose 8080
# → TCP tunnel: host localhost:8080 → container localhost:8080
#
# Note: This tunnel is ephemeral and will not survive a booth restart.
#       Use --permanent to save to .booth/config.toml.
```

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Port Syntax](#port-syntax)
- [Ephemeral vs Permanent](#ephemeral-vs-permanent)
- [Listing ports](#listing-ports)
- [Relationship to -p and --expose](#relationship-to--p-and---expose)
- [Security](#security)
- [Limitations](#limitations)

---

## Overview

Docker port mappings (`-p`) are fixed at container creation. If you start a web server, database, or any service on a port that was not exposed upfront, you normally have to stop and recreate the container with the new port mapping.

`booth--expose` solves this by tunneling TCP traffic via `docker exec` and `socat`. The running booth process on the host detects the tunnel request and automatically opens a local port that forwards traffic into the container.

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
# host localhost:18080 → container localhost:8080
```

### Relative to the offset base (`+`)

```bash
booth--expose 8080 +8080
# If booth port is 10000: host localhost:18080 → container localhost:8080
# If booth port is 12000: host localhost:20080 → container localhost:8080
```

The `+` prefix adds the value to the **offset base**, which is the booth port unless the booth was
started with `--offset-base` (see [Booth Run → Ports](BOOTH_RUN.md#ports)). Following the booth port
keeps port assignments predictable regardless of which port the booth is running on — two booths of
the same project sit on different booth ports and so tunnel to different host ports.

A booth that owns the whole host — a cloud one, typically — has no such collision to dodge and a
front door on a port it did not choose, so it sets a base of its own instead:

```bash
booth --port 443 --offset-base 20000
# inside: booth--expose 8080 +8080  → host localhost:28080 → container localhost:8080
```

### Default (no external port)

```bash
booth--expose 8080
# host localhost:8080 → container localhost:8080
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

## Ephemeral vs Permanent

### Ephemeral (default)

By default, tunnels are ephemeral. The control file is written to `.booth/.tmp/tcp-tunnels/`, which is cleaned on booth exit and startup (see [booth tmp](BOOTH_TMP.md)).

```bash
booth--expose 8080
```

Output:
```
TCP tunnel: host localhost:8080 → container localhost:8080
Note: This tunnel is ephemeral and will not survive a booth restart.
      Use --permanent to save to .booth/config.toml.
```

### Permanent (`--permanent`)

To persist a tunnel across restarts, use `--permanent`. This writes the tunnel configuration to `.booth/config.toml`.

```bash
booth--expose 8080 +8080 --permanent
```

This adds to `.booth/config.toml`:

```toml
[tcp-tunnels]
8080 = "+8080"
```

The tunnel is also activated immediately for the current session.

**Requires `--writable-booth`:** The `.booth/` directory is mounted read-only by default. If the booth was not started with `--writable-booth`, the `--permanent` flag will fail:

```
Cannot write to .booth/config.toml (booth directory is read-only).
Use --writable-booth when starting the booth, or add the tunnel
config to .booth/config.toml manually.
```

### Permanent tunnels in config.toml

You can also add tunnel configurations directly to `.booth/config.toml`:

```toml
[tcp-tunnels]
3000 = "+3000"           # React dev server
8080 = "18080"           # API server (explicit port)
5432 = "+5432"           # PostgreSQL
```

These tunnels activate automatically on every booth start. If a host port is unavailable, the tunnel is skipped with a warning — the booth start is not blocked.

---

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
18888      0.0.0.0:19888    tcp    published   yes   published (-p)
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
18888     0.0.0.0:19888          tcp   published   up      jupyter-lab
5432      127.0.0.1:5432         tcp   tunnel      up      -
10099     -                      tcp   internal    up      websockify
```

A `SERVER` of `-` means the process is owned by another user and `ss` could not
name it; a `KIND` of `internal` with no `HOST` means the service listens inside
the container but is not published to the host.

---

## Relationship to `-p` and `--expose`

CodingBooth has three ways to make container ports accessible. Each serves a different purpose:

| Method | When Decided | Survives Restart | Mechanism |
|--------|-------------|-----------------|-----------|
| `-p` (Docker port mapping) | Container creation | Yes (if keep-alive) | Docker native |
| `--expose` in `booth config` | Configuration time | Yes | Writes `-p` to run-args |
| `booth--expose` (TCP tunnel) | Runtime | No (unless `--permanent`) | docker exec + socat |

**Use `-p` / `--expose`** when you know the ports upfront. These are Docker-native port mappings — no overhead, full performance.

**Use `booth--expose`** when you discover a port at runtime. It tunnels via `docker exec`, so there is some overhead compared to a native port mapping, but it works without restarting the container.

> **Tip:** If you find yourself using `booth--expose` for the same port every time, consider adding it to your `config.toml` either with `booth--expose --permanent` or by adding an `--expose` to your `booth config` command.

---

## Security

The tunnel uses `docker exec` to bridge connections, which requires access to the Docker socket. Only processes that can run `docker exec` on the container (i.e., the host-side booth process) can create tunnels. The tunnel is bound to `localhost` by default, so it is not accessible from other machines.

If the booth port is exposed publicly (`--public`), consider whether the tunneled service should also be accessible.

---

## Limitations

- **TCP only** — `socat` bridges TCP connections. UDP protocols are not supported.
- **Foreground mode required** — The host-side booth process must be running to watch for tunnel requests and create listeners. This works in foreground mode (the default). For daemon mode, use `-p` / `--expose` at configuration time instead.
- **Per-connection overhead** — Each TCP connection spawns a `docker exec` process. For development use (a handful of concurrent connections) this is negligible, but high-throughput scenarios may notice latency.
- **Port availability** — If the requested host port is already in use, the tunnel fails with an error. Choose a different external port or use `+` syntax for predictable allocation.
