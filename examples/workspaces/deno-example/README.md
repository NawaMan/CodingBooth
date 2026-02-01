# Dice Roller

A simple dice roller CLI built with Deno.

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
