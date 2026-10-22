# Goose Example

This example is a minimal [Goose](https://aardappel.github.io/goose/) project: a memory-safe
systems language with no heap allocator, garbage collector or lifetime annotations. The bundled
program prints every prime number up to a limit, followed by how many it found. It shows the two
ways Goose runs code: **in-process**, where the compiler hands its generated C to the bundled
TinyCC and runs it with no build step, and **native**, where `goose-lang build` links an
executable with gcc. Both need system pieces a bare Goose download does not bring — the C
library's headers for the first, a C compiler for the second — and the booth installs them with
the compiler, so neither fails on a fresh machine with `stdint.h not found`.

**Stack:** Goose 2026.3, gcc

> **The command is `goose-lang`, not `goose`.** Goose's own docs and samples say `goose`; in a
> booth that name belongs to the Goose AI agent (the `goose` template), so the two can be
> installed side by side. `goose-lang` is the same compiler.

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/goose-lang-example
booth

# 2. Inside the booth — run the primes demo
just --list
just run 20              # goose-lang src/primes.goose -- 20
just build && ./primes 20
```

## What's included

| Component       | Details                                                         |
|-----------------|-----------------------------------------------------------------|
| Compiler        | Goose (pinned 2026.3), at `/usr/local/goose-lang-current`       |
| In-process runs | Bundled TinyCC + `libc6-dev`                                    |
| Native builds   | gcc (`goose-lang build`)                                        |
| Language server | `goose-lang lsp`                                                |
| Sample          | `src/primes.goose`                                              |

The release's own samples, docs and VS Code extension (`vscode/goose-language.vsix`) are under
`/usr/local/goose-lang-current/`. Goose publishes linux x64 builds only, so this booth does not
build on Apple Silicon.

Pin a different release with the `GOOSE_LANG_VERSION` build arg in `.booth/Boothfile`, or
regenerate with `booth config --select goose-lang:2026.2`.

## Recipes

| Recipe          | Does                                                   |
|-----------------|--------------------------------------------------------|
| `just run [N]`  | Run in-process (default limit 100)                     |
| `just check`    | Typecheck only, run nothing                            |
| `just build`    | Native executable at `./primes`, via gcc               |
| `just shell`    | Open a shell in this project's booth                   |

Every recipe also works from the host: it runs in the booth, starting one if needed.
