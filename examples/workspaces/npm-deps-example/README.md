# NPM Deps Example

Demonstrates pre-installing npm dependencies at booth-build time so the first run inside the booth doesn't hit the network.

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
