# MEAN Example

This example is a canonical MEAN stack — MongoDB, Express, Angular, and Node — running on a single CodingBooth container. An Express/Mongoose API seeds one item into MongoDB and serves it at `GET /api/items`, which an Angular client fetches and lists in the browser. It showcases how much a single booth bundles: MongoDB, Express, Angular, and Node — a full four-tier JavaScript stack — all live in one container. There is no separate database to install and babysit and no Node version to juggle; the entire MEAN stack comes up together and vanishes cleanly the moment you stop the booth.

## Run

Two terminals inside the booth:

```bash
# terminal 1 — API
cd server && npm install && npm start
```

```bash
# terminal 2 — client (Angular dev server)
cd client && npm install && npm start
```

Then open http://localhost:4200/ on the host. The page should list items the Express API reads from MongoDB.

## What's inside

- `.booth/Boothfile` — Node.js, MongoDB, and the workspace-local `mean-init` setup.
- `.booth/config.toml` — exposes 3000 (API) and 4200 (Angular dev server).
- `.booth/setups/mean-init--setup.sh` — registers a startup hook that auto-starts `mongod` (MongoDB's setup only prepares data dirs).
- `server/server.js` — Express + Mongoose; seeds one item if the collection is empty, exposes `GET /api/items`.
- `client/` — Angular 19 standalone-component app with one `AppComponent` that fetches `/api/items`.
