# PocketBase Example

This example is **Tripboard** — a small trip calendar — built on [PocketBase](https://pocketbase.io)
used as a *Go framework* rather than as a downloaded binary. PocketBase is an ordinary `go.mod`
dependency, so a database, a REST API, an admin UI and this app's own routes all come out of one
`go build`, and the whole server is a single static binary with SQLite compiled in. It showcases
CodingBooth's port exposure and version pinning together: the Go toolchain is pinned in the
Boothfile, PocketBase is pinned in `go.mod`, and the server started inside the container is
forwarded to your host, so `localhost:8090` in your normal browser reaches both the calendar and
the admin UI with no port plumbing to set up.

## Run

```bash
./booth run
# inside the booth:
./build.sh                                                    # one static binary
./tripboard superuser upsert you@example.com 'a-strong-password'
./start.sh                                                    # → http://localhost:8090/
```

`start.sh` builds first (`go build` is incremental, so it is nearly free) and serves on
`0.0.0.0` — which matters: the booth publishes container port 8090 to the host, so a server bound
to `127.0.0.1` would ignore that mapping and nothing would answer.

The first build downloads PocketBase and its dependencies; later builds are fast. The first run
creates `pb_data/` (SQLite database, logs) and applies the migrations, so the demo trip is already
on screen — no import step. The superuser account is only needed to *edit*: reading the calendar
works signed out.

Then open:

| URL | What it is |
|---|---|
| `http://localhost:8090/` | The trip: five days, one 24-hour row each |
| `http://localhost:8090/api/trip` | The same trip as JSON, already cut into days |
| `http://localhost:8090/api/collections/trip_events/records?sort=starts_at` | The raw records — PocketBase's built-in REST API, no code written for it |
| `http://localhost:8090/_/` | Admin UI: browse and edit the trip |

Edit an event in the admin UI, reload the calendar, and it moves. The superuser account you created
above is the login.

## What to try

- **Drag a hotel across midnight.** Change `ends_at` on *Hotel Alfama Rooftop* in the admin UI. The
  block is cut at midnight and each day keeps the part it owns — that split happens in Go, in
  `trip.go`, not in the browser.
- **Flip `certainty` to `tentative`.** The block loses its fill and picks up a dashed outline, so
  what is still undecided reads differently from what is booked.
- **Add an event with no `ends_at`.** It renders as a dot: a moment, not a block.
- **Delete `pb_data/` and restart.** The trip comes back identically — the schema and the seed are
  Go code under `internal/migrations/`, not a database you have to keep.

## What's inside

- `.booth/Boothfile` — pins the Go toolchain (1.25.7) and adds gopls, dlv and the Go VS Code
  extension.
- `.booth/config.toml` — maps container port 8090 to host port 8090.

  Both are `booth config` output, fingerprinted in `.booth/.generated`, so `booth config` opens
  them in its TUI with the selection and the Go pin already filled in. Change the environment
  there rather than by hand — a hand-edit is detected, and from then on `booth config` refuses to
  touch the file without `--overwrite`. The command that produced them is the header's
  `# Configured by:` line.
- `build.sh` / `start.sh` — build the binary; build-and-serve it (`PORT=…` to move it).
- `go.mod` — pins PocketBase itself (`v0.39.9`).
- `main.go` — wires PocketBase up: migrations, one custom route, and `pb_public/` served last so its
  catch-all cannot shadow the API.
- `trip.go` — `GET /api/trip`: loads the events and arranges them day by day.
- `internal/migrations/` — the `trip_events` collection, then the demo trip that fills it. The trip
  is invented; the booking references are not real.
- `pb_public/index.html` — the calendar. One file, no build step, no framework.
