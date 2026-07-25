# Angular Example

This example is a minimal Angular 19 standalone-component app running inside a CodingBooth workspace. The bundled component renders a button that increments and displays a click counter using Angular's Signals API. It showcases how the booth keeps your host pristine: the Angular CLI and its roughly 500-package `node_modules` — hundreds of megabytes of transitive dependencies — live entirely inside the container. Stop the booth and every trace is gone; your machine never accumulates the sprawling global npm state that Angular projects are notorious for leaving behind.

## Run

```bash
./booth run
# inside the booth:
npm install
npm start
```

Then open http://localhost:4200/ on the host.

## What's inside

- `.booth/Boothfile` — Node.js 22.
- `.booth/config.toml` — exposes container port 4200 (Angular dev server default).
- `package.json` — Angular 19 CLI + dev server.
- `angular.json` — minimal build config using the modern `application` builder.
- `src/main.ts` — bootstraps the standalone `AppComponent`.
- `src/app/app.component.ts` — a tiny counter using the Signals API.
