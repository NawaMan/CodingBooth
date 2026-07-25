# Zig Example

This example is a minimal Zig project wired up with Zig's native `zig build` system. The bundled program takes a limit and prints every prime number up to it, followed by the total count found. This one is about reproducibility, and Zig makes the case better than most: the language is pre-1.0 and its syntax and `build.zig` API routinely break between releases, so a project that compiled last month can fail outright on today's Zig. By pinning the exact Zig version, this booth guarantees `zig build` behaves the same for everyone, indefinitely — no chasing breaking changes, no "which Zig were you on?" debugging. When you are ready to move to a newer release deliberately, the `ZIG_VERSION` build arg lets you do it on your own terms rather than being forced by whatever happens to be installed.

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
