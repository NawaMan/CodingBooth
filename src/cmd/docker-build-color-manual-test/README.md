# Docker Build Color Manual Test

This manual test shows Docker's native colored build output when running directly in a terminal.

## Files

- **[run-docker-build-color-manual-test.sh](file:///home/nawa/dev/git/WorkSpace/tests/go/run-docker-build-color-manual-test.sh)** - Shell script to run the integration test
- **[main.go](file:///home/nawa/dev/git/WorkSpace/src/cmd/docker-build-color-manual-test/main.go)** - Go program that builds a Docker image

## Usage

```bash
cd tests/go
./run-docker-build-color-manual-test.sh
```

Or run directly:

```bash
go run ./src/cmd/docker-build-color-manual-test/main.go
```

## What You'll See

When running this integration test in a terminal (not through `go test`), you should see:

- **Colored progress bars** - Blue/green progress indicators
- **Colored build steps** - Different colors for different stages
- **Layer caching info** - Visual feedback on cached vs. new layers
- **Build status** - Success/failure with colors

## Why This Works

Unlike the test examples that run through `go test`, this integration test:

1. Runs directly in your terminal (has a real TTY)
2. Uses `--progress=auto` which detects the TTY and enables colors
3. Has environment variables set for color support:
   - `FORCE_COLOR=1`
   - `BUILDKIT_COLORS=run=green:warning=yellow:error=red:cancel=cyan`
   - `TERM=xterm-256color`

## Comparison

- **go test examples** - Plain text output (no TTY detection)
- **This manual test** - Full colored output (real TTY)
