# Zig Example

A minimal Zig project with `zig build` integration.

**Stack:** Zig 0.15

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/zig-example
booth

# 2. Inside the booth — build and run the primes demo
./run-primes.sh 20
```

## What's included

| Component       | Details                              |
|-----------------|--------------------------------------|
| Compiler        | Zig (default 0.15.1)                 |
| Build           | `build.zig` (Zig's native build system) |
| VS Code support | Zig language extension               |
| Sample          | `src/main.zig`                       |

Pin a different Zig version with the `ZIG_VERSION` build arg in `.booth/Boothfile`.
