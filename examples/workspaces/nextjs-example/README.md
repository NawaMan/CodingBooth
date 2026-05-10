# Next.js Example

A minimal [Next.js 15](https://nextjs.org/) App Router demo running inside a CodingBooth workspace.

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
