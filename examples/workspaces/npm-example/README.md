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

## What's included

| Component | Details                                                                   |
|-----------|---------------------------------------------------------------------------|
| Runtime   | Node.js (default)                                                         |
| Packages  | `typescript`, `ts-node`, `prettier`, `eslint`, `cowsay`, `figlet-cli`     |

Edit the `install npm ...` line in `.booth/Boothfile` to customise the global package set.
