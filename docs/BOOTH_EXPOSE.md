# booth expose

> Started a server on a new port? Access it from the host without restarting your booth.

`booth--expose` creates a TCP tunnel through the existing booth port, making any internal container port accessible from the host — at runtime, with no container restart.

```bash
# Inside the booth:
booth--expose 8080
# → TCP tunnel: host localhost:18080 → container localhost:8080
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
- [Relationship to -p and --expose](#relationship-to--p-and---expose)
- [Security](#security)
- [Limitations](#limitations)

---

## Overview

Docker port mappings (`-p`) are fixed at container creation. If you start a web server, database, or any service on a port that was not exposed upfront, you normally have to stop and recreate the container with the new port mapping.

`booth--expose` solves this by tunneling TCP traffic through the already-exposed booth port (typically 10000). The running booth process on the host detects the tunnel request and automatically opens a local port that forwards traffic into the container.

- Works for **all TCP traffic** — HTTP, databases, gRPC, raw TCP
- **No SSH server** required
- **No extra ports** need to be exposed on the container
- The host-side booth process sets up the listener **automatically**

---

## How It Works

Two cooperating pieces:

**Inside the container:** `booth--expose` writes a control file to `.booth/.tmp/tcp-tunnels/` and starts a WebSocket tunnel endpoint on the booth port.

**Outside the container:** The running booth process (in foreground mode) watches `.booth/.tmp/tcp-tunnels/` for changes. When a new tunnel is requested, it opens a local port on the host and forwards traffic through a WebSocket connection at a salted path on the booth port.

```
Host                          Container (port 10000)
┌──────────────┐              ┌──────────────────────┐
│ localhost:18080 ──WebSocket──→ /tcp-tunnel-<salt>/8080 │
│ (auto-created)  │              │         ↓              │
│                 │              │   localhost:8080       │
└──────────────┘              └──────────────────────┘
```

The WebSocket path includes a random salt (from the session ID in `.booth/.tmp/booth-startup.txt`) to prevent unauthorized access. See [booth tmp](BOOTH_TMP.md) for details on the session ID.

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

### Relative to booth port (`+`)

```bash
booth--expose 8080 +8080
# If booth port is 10000: host localhost:18080 → container localhost:8080
# If booth port is 12000: host localhost:20080 → container localhost:8080
```

The `+` prefix adds the value to the current booth port. This keeps port assignments predictable regardless of which port the booth is running on.

### Default (no external port)

```bash
booth--expose 8080
# Equivalent to: booth--expose 8080 +8080
```

When no external port is specified, it defaults to `+<container-port>`.

### Examples

| Command | Booth Port | Host Port | Container Port |
|---------|-----------|-----------|----------------|
| `booth--expose 3000` | 10000 | 13000 | 3000 |
| `booth--expose 3000 3000` | 10000 | 3000 | 3000 |
| `booth--expose 8080 +8080` | 10000 | 18080 | 8080 |
| `booth--expose 5432 +5432` | 12000 | 17432 | 5432 |
| `booth--expose 3000 23000` | 10000 | 23000 | 3000 |

---

## Ephemeral vs Permanent

### Ephemeral (default)

By default, tunnels are ephemeral. The control file is written to `.booth/.tmp/tcp-tunnels/`, which is cleaned on booth exit and startup (see [booth tmp](BOOTH_TMP.md)).

```bash
booth--expose 8080
```

Output:
```
TCP tunnel: host localhost:18080 → container localhost:8080
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

## Relationship to `-p` and `--expose`

CodingBooth has three ways to make container ports accessible. Each serves a different purpose:

| Method | When Decided | Survives Restart | Mechanism |
|--------|-------------|-----------------|-----------|
| `-p` (Docker port mapping) | Container creation | Yes (if keep-alive) | Docker native |
| `--expose` in `booth config` | Configuration time | Yes | Writes `-p` to run-args |
| `booth--expose` (TCP tunnel) | Runtime | No (unless `--permanent`) | WebSocket tunnel |

**Use `-p` / `--expose`** when you know the ports upfront. These are Docker-native port mappings — no overhead, full performance.

**Use `booth--expose`** when you discover a port at runtime. It tunnels through the existing booth port, so there is some overhead compared to a native port mapping, but it works without restarting the container.

> **Tip:** If you find yourself using `booth--expose` for the same port every time, consider adding it to your `config.toml` either with `booth--expose --permanent` or by adding an `--expose` to your `booth config` command.

---

## Security

The WebSocket tunnel endpoint uses a **salted path** (`/tcp-tunnel-<session-id>/<port>`) rather than a predictable URL. The session ID is generated randomly on each booth start and is only accessible via the mounted `.booth/.tmp/booth-startup.txt` file.

This prevents someone who can reach the booth port from guessing the tunnel endpoint. However, this is **not a substitute for authentication** — if the booth port is exposed publicly (`--public`), consider whether the tunneled service should also be accessible.

---

## Limitations

- **TCP only** — WebSocket tunnels are TCP-based. UDP protocols are not supported.
- **Foreground mode required** — The host-side booth process must be running to watch for tunnel requests and create listeners. This works in foreground mode (the default). For daemon mode, use `-p` / `--expose` at configuration time instead.
- **Some overhead** — Traffic is proxied through a WebSocket connection rather than a direct port mapping. For most development use cases this is negligible, but high-throughput scenarios may notice latency.
- **Port availability** — If the requested host port is already in use, the tunnel fails with an error. Choose a different external port or use `+` syntax for predictable allocation.
