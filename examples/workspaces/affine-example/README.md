# AFFiNE Example

This example is a booth that runs [AFFiNE](https://affine.pro) — an open-source,
local-first knowledge base with documents and an infinite whiteboard — as a
self-hosted web app. PostgreSQL, Redis, and Node.js 22 come in automatically
with `--select affine-server`. The server starts with the booth
(`+autostart`) and is published to the host (`+expose`), so
`http://localhost:13010` in a **host browser tab** is the AFFiNE UI (the globe
pane cannot load Affine's `/admin/js/` SPA). First visit creates the admin
account at `/admin/setup`.

Data is **clean** (empty every booth). `+seed` starts from a home-seed snapshot
(writes discarded). `+persist` keeps `~/.affine` in `.booth/cache` and dumps
Postgres there on stop.

The desktop Electron app is a different template (`affine-desktop`) and needs
an xfce/kde/lxqt variant; this example is the server, which runs on `base`.

**Stack:** AFFiNE Server + PostgreSQL + Redis + Node.js 22, port 13010, data=clean

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/affine-example
booth

# 2. Inside the booth — wait until the UI answers
just --list
just run                 # ./demo.sh
```

From the host, the same UI is on port 13010 (`+expose`).

## What to try

The server is already starting in the background. `just run` blocks until
`http://localhost:13010` answers, then prints the URL. After that:

1. Open `http://localhost:13010/admin/setup` in a host browser tab.
2. Create the first account — that user becomes the admin.
3. Make a doc, then a whiteboard. With this example they vanish on booth
   stop (`clean`). Select `+persist` to keep them on this machine.

`start-affine-server` / `stop-affine-server` are the manual launchers.

## What's included

| Component    | Details                                              |
|--------------|------------------------------------------------------|
| Server       | Official `ghcr.io/toeverything/affine` image, copied in |
| Database     | PostgreSQL (auto-starts) + Redis                     |
| Runtime      | Node.js 22                                           |
| Port         | 13010, published to the host                         |
| Persistence  | `clean` (default). `+persist` → `.booth/cache`. `+seed` → home-seed. |
| Sample       | `demo.sh` — wait until the UI answers                |

Pin the image tag with `AFFINE_SERVER_VERSION`, or the listen port with
`AFFINE_SERVER_PORT`, via `booth config`. Desktop instead:
`--select affine-desktop` on an xfce booth.
