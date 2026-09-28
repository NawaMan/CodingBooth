# Haskell Notebook Example

This example is a Haskell environment built on GHC and Cabal. The bundled `Factorial.hs` computes the factorial of a number you pass on the command line, showing the step-by-step multiplication for small inputs and guarding against negative or overly large values. Let us be honest about why this one earns its place: standing up a reproducible, non-interactive GHC/Cabal/ghcup toolchain is genuinely painful. ghcup expects an interactive terminal and versions drift — the kind of setup that eats a day and still breaks on the next machine. The value here is not that it is effortless, but that the pain was paid once: the `haskell` setup installs GHC and Cabal non-interactively and checks both. The next person just runs `booth` and gets a working Haskell environment, instead of re-fighting the install from scratch.

**Stack:** Haskell (GHC, Cabal), Claude Code

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/haskell-example
booth

# 2. Inside the booth
just --list
just run 5
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Haskell (GHC, Cabal via ghcup)       |
| VS Code extensions | Haskell language support             |
| AI                 | Claude Code                          |
