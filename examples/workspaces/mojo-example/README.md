# Mojo Example

This example is a small Mojo program that computes the factorial of a number you pass on the command line (default 5). Mojo 1.0 installs as a Python package and needs CPython 3.10–3.14 plus a C++ compiler, so the interesting part is not the arithmetic — it is that `--select mojo` pulls Python, pip-installs the compiler into the booth venv, and leaves `mojo` on PATH so `just run` JIT-compiles and prints a result.

**Stack:** Mojo 1.0 (via Python 3.13)

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/mojo-example
booth

# 2. Inside the booth — compute a factorial
just --list
just run 5              # ./run-factorial.sh 5
```

## What's included

| Component       | Details                              |
|-----------------|--------------------------------------|
| Compiler        | Mojo (default 1.0.0)                 |
| Runtime         | Booth Python (`pip install mojo`)    |
| VS Code support | Official Mojo extension              |
| Sample          | `src/factorial.mojo`                 |

Pin a different Mojo version with the `MOJO_VERSION` build arg in `.booth/Boothfile`.
