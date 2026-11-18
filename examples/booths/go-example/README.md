# Go Example

This example is a small Go project in a plain base booth: Go with gopls and delve, and nothing else. The program, `go4096`, is a terminal sliding-tile puzzle. Slide the tiles with the arrow keys (or WASD), equal tiles that meet merge into their sum, and the goal is a 4096 tile. It uses only the standard library: raw key input comes from `stty`, so `go build` never downloads a module. The rules live in `game/` with unit tests, apart from the terminal code in `main.go`, and `--demo` plays a fixed game by itself, so the binary can be tested without a terminal.

For Go with a desktop, notebooks (GoNB), code-server, shared module caches and cross-compiling, see [go-full-example](../go-full-example/).

**Stack:** Go, gopls, delve

## Quick start

```bash
# 1. Launch the booth
cd examples/booths/go-example
booth

# 2. Inside the booth
just --list
just run                 # play: arrows or WASD, q quits
just run --seed 42       # a game you can replay
just demo                # the game plays itself and prints how it ends
just test                # the rules' unit tests
just build               # ./bin/go4096
```

## What's included

| Component       | Details                                   |
|-----------------|-------------------------------------------|
| Language        | Go (template default), gopls, delve       |
| VS Code support | Go extension (for a VS Code you attach)   |
| Sample          | `go4096`: `main.go` (terminal), `game/` (rules + tests) |
