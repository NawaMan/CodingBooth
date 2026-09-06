# MERN Example

This example is a canonical MERN stack — MongoDB, Express, React, and Node — running on a single CodingBooth container. An Express/Mongoose API seeds one item into MongoDB and serves it at `GET /api/items`, which a React and Vite client fetches and lists in the browser. It showcases how much a single booth bundles: MongoDB, Express, React, and Node — a full-stack JavaScript setup end to end — all live in one container. The database, API, and frontend toolchain arrive together and leave together, so trying the whole stack costs a single command and none of the usual local-install cleanup.

## Run

Two terminals inside the booth (`just --list`):

```bash
# terminal 1 — API
just server              # cd server && npm install && npm start
```

```bash
# terminal 2 — client (Vite dev server)
just client              # cd client && npm install && npm run dev
```

Then open http://localhost:5173/ on the host. The page should list items the Express API reads from MongoDB.

## What's inside

- `.booth/Boothfile` — Node.js and MongoDB with `+start` (mongod on boot).
- `.booth/config.toml` — exposes 3000 (API) and 5173 (Vite).
- `server/server.js` — Express + Mongoose; seeds one item if empty, exposes `GET /api/items`.
- `client/` — React 18 + Vite 5; one `App.jsx` that fetches `/api/items`.
