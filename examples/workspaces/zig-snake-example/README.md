# Snake — A Terminal Game in Zig

This example is a classic terminal Snake game written in Zig, built and played entirely inside [CodingBooth](https://github.com/NawaMan/CodingBooth) with no Zig installation on the host. `zig build run` compiles and launches the single-file `src/main.zig` game (arrow / WASD controls), and `build-all.sh` cross-compiles native binaries for six targets — x86_64 and aarch64 Linux (gnu and musl) plus Intel and Apple-Silicon macOS. Batteries-included and standardized to Linux: it builds and plays with no Zig on the host, yet still cross-compiles to many targets from one booth. Clone, run `./booth`, and you are playing a game compiled from source without ever installing a toolchain — then `build-all.sh` hands you native binaries for six OS/architecture combinations from that same environment. One standardized Linux booth becomes a portable build farm you can run the outputs of directly on your own machine.

## Prerequisites

- Bash
- Docker

## Quick Start

```bash
git clone <this-repo>
cd zig-snake
./booth          # Start the CodingBooth container
zig build run    # Build and play!
```

## Controls

| Key           | Action                 |
|---------------|------------------------|
| Arrow keys    | Move                   |
| W / A / S / D | Move                   |
| Q             | Quit                   |
| R             | Restart (on game over) |

## Try Modifying

Open `src/main.zig` and tweak the constants at the top:

```zig
const BOARD_WIDTH: u16 = 30;       // try 40 for a wider board
const BOARD_HEIGHT: u16 = 20;      // try 15 for a shorter one
const INITIAL_SPEED_MS: u64 = 150; // lower = faster (try 80!)
const SNAKE_COLOR: []const u8 = "\x1b[32m"; // change to "\x1b[33m" for yellow
```

Then rebuild and run:

```bash
zig build run
```

## Cross-Compile

Build binaries for 6 platforms from inside the booth:

```bash
./build-all.sh
ls dist/
```

Exit the booth and run the native binary directly on your host machine.

## Project Structure

```
src/main.zig    — The game (single file, ~360 lines)
build.zig       — Zig build configuration
build-all.sh    — Cross-compilation script
```
