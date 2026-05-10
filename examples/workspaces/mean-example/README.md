# MEAN Example

A canonical [MEAN](https://en.wikipedia.org/wiki/MEAN_%28solution_stack%29) stack — MongoDB + Express + Angular + Node — running on a single CodingBooth container.

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
