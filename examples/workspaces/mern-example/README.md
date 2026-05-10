# MERN Example

A canonical [MERN](https://en.wikipedia.org/wiki/MEAN_%28solution_stack%29#MERN) stack — MongoDB + Express + React + Node — running on a single CodingBooth container.

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

Then open http://localhost:5173/ on the host. The page should list items the Express API reads from MongoDB.

## What's inside

- `.booth/Boothfile` — Node.js, MongoDB, and the workspace-local `mern-init` setup.
- `.booth/config.toml` — exposes 3000 (API) and 5173 (Vite).
- `.booth/setups/mern-init--setup.sh` — startup hook that auto-starts `mongod`.
- `server/server.js` — Express + Mongoose; seeds one item if empty, exposes `GET /api/items`.
- `client/` — React 18 + Vite 5; one `App.jsx` that fetches `/api/items`.
