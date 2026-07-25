# NPM Deps Example

This example pre-installs npm dependencies at booth-build time so the first run inside the booth doesn't hit the network. The Boothfile mounts `package.json` during the build and runs `npm install` to fetch chalk and warm the cache before launch. Pre-baked deps: npm install runs at build time so node_modules is warmed before your first run. The moment the booth opens, `npm test` just works — no cold install, no registry round-trips, no "works on my machine" drift between contributors. Onboarding and CI start from a fully warmed cache every single time.

**Stack:** Node.js 22, npm

## Quick start

```bash
# 1. Launch the booth (dependencies are installed during the image build)
cd examples/workspaces/npm-deps-example
booth

# 2. Inside the booth — node_modules already exists; just run
npm test
```

## What's included

| Component | Details                                                                       |
|-----------|-------------------------------------------------------------------------------|
| Runtime   | Node.js 22                                                                    |
| Build     | npm install (warmed cache at `/opt/npm-cache` populated from `package.json`)  |
| Sample    | `package.json`                                                                |

The `.booth/Boothfile` mounts `package.json` (and `package-lock.json` if present) during build and runs `npm install`, so dependencies are baked into the image.
