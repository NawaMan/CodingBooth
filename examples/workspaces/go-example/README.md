# Go Example

This example is a batteries-included Go workspace with gopls, delve, and the GoNB notebook kernel. The bundled `treemoji` command is a tiny tree-like CLI that walks a directory and prints its structure with emoji icons, supporting flags for hidden files, directories-only, and a maximum depth. This is a genuinely batteries-included Go setup: gopls for editor intelligence, delve for debugging, and the GoNB kernel for notebook-style exploration all come up together, so nothing about the toolchain is left for you to assemble. The real showcase is cross-compilation — `build.sh` builds the very same `treemoji` binary for Linux, macOS (Intel and Apple Silicon), Windows, and beyond just by setting `GOOS`/`GOARCH`. You can ship a release for every platform from one Linux booth, without a CI matrix and without touching a single other machine.

**Stack:** Go, gopls, delve, Python, Jupyter Notebook, GoNB kernel, code-server

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/go-example
booth

# 2. Inside the booth
just --list
just run
just test
#    or open VS Code, create a .ipynb and select the Go kernel
```

## Shared download cache

`go+mod-cache` mounts two volumes that every booth on this machine shares.

| Volume | What it holds |
| --- | --- |
| `booth-cache-gomod` | Module downloads (`GOMODCACHE`) |
| `booth-cache-gobuild` | Build cache (`GOCACHE`) |

This example does not bake modules into the image, so the first `go test` fills the volumes:

```bash
./booth -- go test ./...
```

Copy this folder to a second path and run the same command with `GOPROXY=off`. That booth installs from the volumes. List them with `docker volume ls --filter label=cb.volume=cache`. While no booth is using one, `docker volume rm booth-cache-gomod` clears it.

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Go (with gopls and delve)            |
| Notebook           | Jupyter with GoNB kernel             |
| VS Code extensions | Go language support                  |
| Editor             | code-server (VS Code in browser)     |
