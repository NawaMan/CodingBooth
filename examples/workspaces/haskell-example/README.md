# Haskell Notebook Example

This example is a Haskell environment built on GHC with Jupyter notebook support. The bundled `Factorial.hs` computes the factorial of a number you pass on the command line, showing the step-by-step multiplication for small inputs and guarding against negative or overly large values. Let us be honest about why this one earns its place: standing up a reproducible, non-interactive GHC/Cabal/ghcup toolchain is genuinely painful. ghcup expects an interactive terminal, versions drift, and the IHaskell kernel adds its own native-library requirements — the kind of setup that eats a day and still breaks on the next machine. The value here is not that it is effortless, but that the pain was paid once: the booth bakes in the workarounds and repair steps so the failures are already solved. The next person just runs `booth` and gets a working Haskell environment and notebook kernel, instead of re-fighting the install from scratch.

**Stack:** Haskell (GHC), Jupyter Notebook, IHaskell kernel, KDE Plasma desktop, Claude Code

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/haskell-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the Haskell kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Haskell (GHC)                        |
| Notebook           | Jupyter with IHaskell kernel         |
| VS Code extensions | Haskell language support             |
| Desktop            | KDE Plasma                           |
| AI                 | Claude Code                          |
