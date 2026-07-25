# Node.js Example

This example is a Node.js 22 environment with Jupyter notebook support for both JavaScript and TypeScript. There is no standalone script to run — you open a `.ipynb`, select the JavaScript or TypeScript kernel, and execute code cell by cell against the tslab kernel. Here is what makes it worth a look: the single tslab kernel registers two working Jupyter kernels — one for JavaScript and one for TypeScript — with the TypeScript side giving you real type-checking inside notebook cells. No Babel config, no ts-node wiring, no separate build step to babysit. Pick a kernel and prototype a TypeScript idea with types checked as you go, or drop to plain JavaScript, all interactively and all ready the instant the booth starts.

**Stack:** Node.js 22, Jupyter Notebook, tslab kernel, Claude Code

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/nodejs-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the JavaScript or TypeScript kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Node.js 22                           |
| Notebook           | Jupyter with tslab kernel            |
| VS Code extensions | Node.js language support             |
| AI                 | Claude Code                          |
