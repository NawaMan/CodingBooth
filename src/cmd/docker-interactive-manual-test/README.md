# Docker Interactive Manual Test

Manual test demonstrating Docker's TTY detection and interactive shell support.

## Usage

```bash
cd tests/go
./run-docker-interactive-manual-test.sh
```

Or run directly:

```bash
go run ./src/cmd/docker-interactive-manual-test/main.go
```

## What It Tests

- **TTY Detection** - Shows whether stdin/stdout are connected to a TTY
- **Interactive Flags** - Demonstrates `-i` and `-t` flag handling
- **Real Terminal** - Provides interactive shell when run in a terminal

## Why This Exists

Unlike `go test` which captures output and prevents TTY detection, this manual test runs directly in your terminal, allowing you to:

1. See actual TTY status (stdin, stdout detection)
2. Get an interactive shell with `-it` flags
3. Verify the Docker package correctly handles TTY scenarios

## Comparison

- **go test** - No TTY, flags auto-filtered
- **This manual test** - Real TTY, interactive shell works
