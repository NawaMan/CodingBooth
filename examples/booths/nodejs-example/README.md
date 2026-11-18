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

### Run it

Three sample notebooks come with the example: `hello-js.ipynb` (JavaScript kernel),
`hello-ts.ipynb` (TypeScript kernel, an `interface` and typed functions) and `type-error.ipynb`
(one deliberate type mistake). Open them in the editor, or let the recipes run them:

```bash
just --list
just run                 # run hello-js and hello-ts headless, print every cell's output
just typecheck           # run type-error.ipynb: tslab rejects the cell, as tsc would
just kernels             # jupyter kernelspec list — javascript and typescript beside python
just node                # plain Node.js, no Jupyter
just lab                 # JupyterLab on :18888 (Ctrl+C stops)
```

`just typecheck` passes only when the TypeScript kernel refuses the cell with
`Argument of type 'string' is not assignable to parameter of type 'number'` — the type-checking
this example is about, shown rather than described.

Port 18888 is not published to the host, so `just lab` is opened through the booth port's proxy:
[http://localhost:10000/proxy/18888/lab](http://localhost:10000/proxy/18888/lab) (the recipe prints
the URL for the booth's actual port). Kernels run through it too — the proxy forwards JupyterLab's
API and kernel WebSocket calls to port 18888.

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Node.js 22                           |
| Notebook           | Jupyter with tslab kernel            |
| VS Code extensions | Node.js language support             |
| AI                 | Claude Code                          |
