# Dice Roller

This example is a simple dice-roller CLI built with Deno. `src/dice.ts` parses standard dice notation like 2d6 or 1d20, rolls that many dice, and prints each individual roll plus the total using only Deno's built-ins. Reproducibility: a committed `deno.lock` plus pinned packages give identical resolved dependencies in every environment. The lockfile travels with the repo and the booth pins the runtime, so every clone resolves the exact same dependency graph — no surprise upgrades, no "it broke after I pulled." Whoever runs it, whenever they run it, gets the same Deno and the same packages down to the hash.

## Features
- Roll any number of dice with any sides (e.g., 2d6, 1d20)
- Shows individual rolls and total
- Uses Deno's built-in features (no external dependencies)

## Usage

```bash
deno run src/dice.ts 2d6
deno run src/dice.ts 1d20
deno run src/dice.ts 3d8
```

## Development

Run directly:
```bash
deno run src/dice.ts [dice notation]
```

Run tests:
```bash
deno test
```
