# Mojo Example

This example is a small Mojo factorial — a CLI program and a Jupyter notebook that run the same calculation. Mojo 1.0 installs as a Python package and needs CPython 3.10–3.14 plus a C++ compiler, so the interesting part is not the arithmetic: `--select mojo+kernel` pulls Python and Jupyter, pip-installs the compiler, and registers a kernelspec named **Mojo**. Modular notebooks are a Python kernel plus the `%%mojo` cell magic (each cell is a complete program with `main()`); the booth auto-imports that magic so the first cell does not have to.

**Stack:** Mojo 1.0 (via Python 3.13), Jupyter (`%%mojo`)

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/mojo-example
booth

# 2. Inside the booth — CLI factorial, or the notebook
just --list
just run 5              # ./run-factorial.sh 5
start-notebook          # then open Factorial.ipynb, kernel "Mojo"
```

## What's included

| Component       | Details                              |
|-----------------|--------------------------------------|
| Compiler        | Mojo (default 1.0.0)                 |
| Runtime         | Booth Python (`pip install mojo`)    |
| Notebook        | `Factorial.ipynb` (kernel **Mojo**, `%%mojo` cells) |
| VS Code support | Official Mojo extension              |
| Sample          | `src/factorial.mojo`                 |

Pin a different Mojo version with the `MOJO_VERSION` build arg in `.booth/Boothfile`.
