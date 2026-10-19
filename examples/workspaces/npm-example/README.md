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

### Run it

`hello.ts` is a small typed greeting and `banner.mjs` draws a box around whatever it is given; the
recipes put every tool to work on them:

```bash
just --list
just run                 # figlet banner, ts-node hello.ts | node banner.mjs, then cowsay
just check               # tsc --noEmit (strict tsconfig.json)
just lint                # eslint on banner.mjs, prettier --check on every sample
just cache               # ./cache.sh — the shared pnpm store below, in one go
just packages            # npm ls -g --depth=0
```

ESLint lints `banner.mjs` rather than `hello.ts` because it cannot parse TypeScript without the
`typescript-eslint` plugin, which this example does not install.

**TypeScript is pinned to 5.x** (`typescript@^5` in the Boothfile). TypeScript 7 is the Go port and
no longer ships the JavaScript API that `ts-node` 10 is built on, so with it `ts-node` cannot run
any file (`Cannot read properties of undefined (reading 'fileExists')`). Unpin it once you drop
`ts-node`, e.g. for Node's own `node hello.ts`.

## Shared download cache

`nodejs+npm-cache` mounts `booth-cache-npm` on the npm download cache. `nodejs+pnpm-cache` mounts `booth-cache-pnpm` on the pnpm store. pnpm is not in the image; installing it is what fills the npm cache.

```bash
./booth -- 'mkdir -p /tmp/pnpm-try && cd /tmp/pnpm-try && npm init -y && npx --yes pnpm add left-pad'
```

The store is its own filesystem, so pnpm copies packages into `node_modules` instead of hardlinking them. The download still comes from `booth-cache-pnpm`.

Copy this folder to a second path and run:

```bash
./booth -- 'mkdir -p /tmp/pnpm-try2 && cd /tmp/pnpm-try2 && npm init -y && npx --yes pnpm add left-pad'
```

A shared-store hit reports `reused` greater than 0 and `downloaded` 0. List the volumes with `docker volume ls --filter label=cb.volume=cache`.

## What's included

| Component | Details                                                                   |
|-----------|---------------------------------------------------------------------------|
| Runtime   | Node.js (default)                                                         |
| Packages  | `typescript@^5`, `ts-node`, `prettier`, `eslint`, `cowsay`, `figlet-cli`  |

To change the package set, regenerate rather than edit the Boothfile by hand (a hand edit makes
`booth config` treat the file as hand-written): re-run the `booth config` line from the
Boothfile's `# Configured by:` header with a different `npm-pkg:` list.
