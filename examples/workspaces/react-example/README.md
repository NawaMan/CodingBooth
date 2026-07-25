# React Example

This example is a minimal React and Vite app running inside a CodingBooth workspace. The bundled component renders a button that increments and displays a click counter via React's useState hook. It showcases CodingBooth's port exposure: the Vite dev server runs inside the container yet is bound and mapped so it answers at `localhost` in your everyday browser, hot-reload and all. You get the full container-isolated toolchain with none of the friction — no guessing at container IPs and no config edits to escape the sandbox, the dev server is simply there on the host.

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
