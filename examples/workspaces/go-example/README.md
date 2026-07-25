# Go Example

This example is a batteries-included Go workspace with gopls, delve, and the GoNB notebook kernel. The bundled `treemoji` command is a tiny tree-like CLI that walks a directory and prints its structure with emoji icons, supporting flags for hidden files, directories-only, and a maximum depth. This is a genuinely batteries-included Go setup: gopls for editor intelligence, delve for debugging, and the GoNB kernel for notebook-style exploration all come up together, so nothing about the toolchain is left for you to assemble. The real showcase is cross-compilation — `build.sh` builds the very same `treemoji` binary for Linux, macOS (Intel and Apple Silicon), Windows, and beyond just by setting `GOOS`/`GOARCH`. You can ship a release for every platform from one Linux booth, without a CI matrix and without touching a single other machine.

**Stack:** Go, gopls, delve, Python, Jupyter Notebook, GoNB kernel, code-server

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/go-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the Go kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Go (with gopls and delve)            |
| Notebook           | Jupyter with GoNB kernel             |
| VS Code extensions | Go language support                  |
| Editor             | code-server (VS Code in browser)     |
