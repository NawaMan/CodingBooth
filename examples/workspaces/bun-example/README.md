# Greeter

This example is a simple greeting CLI built with Bun and TypeScript. `src/greeter.ts` greets a name passed on the command line, prints the current time, and offers optional colorized output, with a matching `bun test` suite. Host stays clean: Bun and any global CLI tools install in the booth, not on your host. Give Bun a spin — a fast, still-evolving runtime — without committing it to your machine or having it sit alongside your Node setup. Everything lives in the booth, so evaluating a new toolchain costs you nothing on cleanup and never touches your day-to-day environment.

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
