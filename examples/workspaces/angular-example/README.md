# Angular Example

A minimal [Angular 19](https://angular.dev/) standalone-component app running inside a CodingBooth workspace.

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
