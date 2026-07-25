# PERN Example

This example is a modern PERN stack — Postgres, Express, React, and Node — running on a single CodingBooth container. An Express API creates and seeds an `items` table in Postgres and serves it at `GET /api/items`, which a React and Vite client fetches and lists in the browser. It showcases how much a single booth bundles: Postgres, Express, React, and Node — database, API, and frontend — all run inside one container. Postgres is already up and seeded before you start, so there is nothing to provision or tear down; the whole stack is disposable and self-contained, and your host never sees a database.

## Run

Two terminals inside the booth:

```bash
# terminal 1 — API
cd server && npm install && npm start
```

```bash
# terminal 2 — client (Vite dev server)
cd client && npm install && npm run dev
```

Then open http://localhost:5173/ on the host. The page should list items the Express API reads from Postgres.

## What's inside

- `.booth/Boothfile` — Node.js and Postgres. (Postgres auto-starts on container boot via the `postgresql` setup, so no workspace-local init script is needed.)
- `.booth/config.toml` — exposes 3000 (API) and 5173 (Vite).
- `server/server.js` — Express + `pg`; creates the `items` table and seeds one row on startup. Connects via the local Unix socket as the container user.
- `client/` — React 18 + Vite 5; one `App.jsx` that fetches `/api/items`.
