# Next.js Example

This example is a minimal Next.js 15 App Router demo running inside a CodingBooth workspace. It serves a server-rendered page at `/` and a JSON `pong` from a Route Handler at `/api/ping`. It showcases CodingBooth's port exposure: a single forwarded port carries both the server-rendered page and its API route out of the container to your host browser. The whole Next.js app — SSR and backend handler together — behaves exactly as if it were running natively on your machine, while actually living in a disposable, isolated container.

## Run

```bash
./booth run
# inside the booth:
npm install
npm run dev
```

Then open:
- http://localhost:3000/ — server-rendered page
- http://localhost:3000/api/ping — JSON route handler

## What's inside

- `.booth/Boothfile` — Node.js 22 and the React VS Code extension.
- `.booth/config.toml` — exposes container port 3000.
- `package.json` — Next.js 15 + React 19.
- `app/layout.js` — root layout.
- `app/page.js` — a server component for `/`.
- `app/api/ping/route.js` — a Route Handler for `GET /api/ping`.
