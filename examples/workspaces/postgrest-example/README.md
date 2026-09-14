# PostgREST Example

This example turns a PostgreSQL table into a REST API with no server code at all —
[PostgREST](https://postgrest.org) generates the API straight from the database schema. It
showcases two things together:

- **`postgresql+pg-ext-pkg`**: `pgvector` and `pg_trgm` are enabled automatically on container
  boot — just apt-installing the packages isn't enough, since the extensions can only be turned on
  once the server is actually running.
- **`postgrest+autostart+expose`**: the REST API starts automatically after PostgreSQL is up, and
  is published to the host.

The demo is a tiny product catalog with two RPC endpoints that show what each extension is
actually for: `pg_trgm` for typo-tolerant search, `pgvector` for "find similar items" search.

## Run

```bash
./booth run
# inside the booth:
just --list
just seed     # load the demo product catalog (idempotent, safe to re-run)
just demo     # walk through the API
```

`just demo` prints three things:
1. All products, straight off the auto-generated `GET /products`.
2. A search for the misspelled **"Runing Shoez"** — `pg_trgm` still finds and ranks the actual
   "Running Shoes" products by similarity, rather than requiring an exact substring match.
3. "Nearest neighbors" to a hiking-ish embedding — `pgvector`'s `<->` distance operator, exposed as
   a `POST /rpc/match_products` call.

You can also poke at it yourself once seeded, from the host:

```bash
curl http://localhost:<published-port>/products
curl -X POST http://localhost:<published-port>/rpc/search_products \
  -H "Content-Type: application/json" -d '{"query": "hikeing bots"}'
```

The published port is `+3000` relative to the booth's own port — see what `./booth run` printed,
or `docker port <container>`.

## What's inside

- `.booth/Boothfile` — `postgresql+pg-ext-pkg:pgvector,pg_trgm` and `postgrest+autostart+expose`.
- `seed.sql` — creates the `products` table (with a toy 3-dimensional `vector` column), seeds five
  rows, and defines two SQL functions PostgREST exposes as RPC endpoints: `search_products`
  (trigram similarity) and `match_products` (vector distance).
- `Justfile` — `just seed` loads the data, `just demo` runs the three example requests.

## The one non-obvious step

PostgREST caches the database schema when it starts — which is before `just seed` has created
anything. `seed.sql` ends with `NOTIFY pgrst, 'reload schema'`, which tells the already-running
PostgREST to pick up the new table and functions immediately. Skip that notification and every
request 404s with "Could not find the table/function ... in the schema cache" even though the
table is right there in `psql`.
