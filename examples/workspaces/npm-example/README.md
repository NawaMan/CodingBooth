# NPM Example

This example installs popular npm global packages on top of the base booth. It preinstalls typescript, ts-node, prettier, eslint, cowsay, and figlet-cli, so commands like `tsc`, `cowsay`, and `figlet` are ready immediately. Host stays clean: global npm tools install in the booth, not in your host's global node_modules. Experiment with heavyweight CLIs and formatters without a single `npm i -g` touching your machine or clashing with the Node version you run day to day. Throw the booth away and every global tool goes with it, leaving your host untouched.

**Stack:** Node.js, npm global tools

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/npm-example
booth

# 2. Inside the booth — try the preinstalled tools
cowsay "hello from npm-example"
figlet codingbooth
tsc --version
```

## Shared download cache

`nodejs+npm-cache` mounts `booth-cache-npm` on the npm download cache. `nodejs+pnpm-cache` mounts `booth-cache-pnpm` on the pnpm store. pnpm is not in the image; installing it is what fills the npm cache.

```bash
./booth -- bash -lc 'npm install -g pnpm && mkdir -p try && cd try && npm init -y && pnpm add left-pad'
```

The store is its own filesystem, so pnpm copies packages into `node_modules` instead of hardlinking them. The download still comes from `booth-cache-pnpm`.

Copy this folder to a second path and run:

```bash
./booth -- bash -lc 'npm install -g pnpm && mkdir -p try && cd try && npm init -y && npm install --offline left-pad && pnpm add --offline left-pad'
```

`--offline` succeeds only after the first booth has filled the volumes. List them with `docker volume ls --filter label=cb.volume=cache`.

## What's included

| Component | Details                                                                   |
|-----------|---------------------------------------------------------------------------|
| Runtime   | Node.js (default)                                                         |
| Packages  | `typescript`, `ts-node`, `prettier`, `eslint`, `cowsay`, `figlet-cli`     |

Edit the `install npm ...` line in `.booth/Boothfile` to customise the global package set.
