# Greeter

A simple greeting CLI built with Bun and TypeScript.

## Features
- Greet someone by name
- Optional colorful output
- Shows current time

## Usage

```bash
bun run src/greeter.ts World
bun run src/greeter.ts --color Alice
./greeting.sh Alice
```

## Development

Run directly:
```bash
bun run src/greeter.ts [name]
```

Run tests:
```bash
bun test
```

For maintainers, automated example tests live in `.cb-tests/` and can be run from:
```bash
./run-automatic-on-host-test.sh
```
