# Rust Example

This example is a Rust (stable) development environment with Jupyter notebook support. The bundled program is a FizzBuzz generator that takes a start and end number and prints Fizz, Buzz, FizzBuzz, or the number itself for each value in that range. Here is the part worth showing off: evcxr, the Rust Jupyter kernel, is notoriously painful to build — it compiles Rust on the fly and its install trips over toolchain and linker quirks that cost most people an afternoon. In this booth it simply works out of the box. Select the Rust kernel in a notebook and you get a real REPL-style loop — define a function in one cell, call it in the next, watch types and errors as you go — turning a compiled language into something you can explore interactively.

**Stack:** Rust (stable), Jupyter Notebook, evcxr kernel, XFCE desktop, Claude Code

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/rust-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the Rust kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Rust (stable)                        |
| Notebook           | Jupyter with evcxr kernel            |
| VS Code extensions | Rust language support                |
| Desktop            | XFCE                                 |
| AI                 | Claude Code                          |
