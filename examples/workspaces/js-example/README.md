# JavaScript / TypeScript Example

A "Time App" that demonstrates client-server development inside a CodingBooth,
with a React + Vite frontend and an Express API backend.

**Stack:** Node.js, Bun, Deno, TypeScript, React, Vite, Express

## Quick start

```bash
# Inside the booth
./start-server.sh          # starts both API (port 3000) and Vite (port 5173)
```

This launches two background servers:

| Server      | Port | What it serves                                                              |
|-------------|------|-----------------------------------------------------------------------------|
| Express API | 3000 | `/api/time` and `/api/currenttime` — returns the current server time as JSON |
| Vite dev    | 5173 | The React frontend — shows live client and server clocks side by side        |

## Try it

### From inside the booth

Open a terminal inside the booth and run:

```bash
curl http://localhost:3000/api/time        # API: JSON with server time
curl http://localhost:5173                  # Vite: the HTML page
```

### From your host machine

The same ports are forwarded to your host, so open a browser to:

- **http://localhost:5173** — the full app (React + live clock)
- **http://localhost:3000** — the API server info page (or `/api/time` for raw JSON)

Both pages should show a ticking clock. The **Client** time comes from your
browser's `Date`; the **Server** time comes from the Express API running inside
the booth. If both times are in sync, everything is working.

## Other commands

```bash
./check-server.sh              # verify both servers are up
./check-server.sh --expect=down  # verify both servers are down
./stop-server.sh               # stop both servers
./start-server.sh --runtime=bun  # use Bun instead of Node for the API
```
