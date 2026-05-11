# NPM Example

Demonstrates installing popular npm global packages on top of the base booth.

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
