# Snake — A Terminal Game in Zig

A classic terminal snake game built inside [CodingBooth](https://github.com/NawaMan/CodingBooth), no Zig installation required.

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
