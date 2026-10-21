# Haskell Notebook Example

This example is a Haskell environment built on GHC and Cabal. The bundled `Factorial.hs` computes the factorial of a number you pass on the command line, showing the step-by-step multiplication for small inputs and guarding against negative or overly large values. Let us be honest about why this one earns its place: standing up a reproducible, non-interactive GHC/Cabal/ghcup toolchain is genuinely painful. ghcup expects an interactive terminal and versions drift — the kind of setup that eats a day and still breaks on the next machine. The value here is not that it is effortless, but that the pain was paid once: the `haskell` setup installs GHC and Cabal non-interactively and checks both. The next person just runs `booth` and gets a working Haskell environment, instead of re-fighting the install from scratch.

The notebook side is the same story. IHaskell, the Haskell Jupyter kernel, is 143 cabal packages built against one exact GHC (about 11 minutes), and IHaskell 0.13 on ghcup's recommended GHC 9.10.3 kills the kernel the moment a cell imports `Data.Map` and calls `insertWith`. Here the kernel comes prebuilt, on GHC 9.12.4 installed beside the booth's own GHC, and `Haskell-Tour.ipynb` walks through it cell by cell.

**Stack:** Haskell (GHC, Cabal), Jupyter Notebook, IHaskell kernel, Claude Code

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/haskell-example
booth

# 2. Inside the booth
just --list
just run 5
#    or open Haskell-Tour.ipynb in Jupyter (the Haskell kernel is preselected)
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Haskell (GHC, Cabal via ghcup)       |
| Notebook           | Jupyter with IHaskell (GHC 9.12.4)   |
| VS Code extensions | Haskell language support             |
| AI                 | Claude Code                          |
