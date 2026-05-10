# React Example

A minimal [React](https://react.dev/) + [Vite](https://vitejs.dev/) app running inside a CodingBooth workspace.

## Run

```bash
./booth run
# inside the booth:
npm install
npm run dev
```

Then open http://localhost:5173/ on the host.

## What's inside

- `.booth/Boothfile` — sets up Node.js 22 and the React VS Code extension.
- `.booth/config.toml` — exposes container port 5173 (Vite dev server) to the host.
- `package.json` — React 18 + Vite 5.
- `vite.config.js` — binds Vite to `0.0.0.0` so the host can reach it.
- `src/App.jsx` — a tiny counter component to confirm state works.
