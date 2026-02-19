# Octave Example

GNU Octave development environment with Jupyter notebook support using the Calysto Octave kernel.

**Stack:** GNU Octave, Python 3.13, Jupyter Notebook, Calysto Octave Kernel

## Quick start

```bash
# 1. Launch the booth (default: notebook variant)
cd examples/workspaces/octave-example
booth

# 2. Open the Jupyter Notebook UI and select the Octave kernel
```

## Choosing a variant

This example defaults to the **notebook** variant. Change the variant in
`.booth/config.toml` for a different experience:

| Variant        | What you get                                               | How to use Octave                |
|----------------|------------------------------------------------------------|----------------------------------|
| `notebook`     | Jupyter Notebook with Octave kernel, VS Code (code-server) | Open `.ipynb`, select "Octave"   |
| `desktop-xfce` | Full Linux desktop (XFCE) with Octave GUI IDE              | Launch `octave --gui` from menu  |
| `base`         | Minimal CLI-only environment                               | Run `octave-cli` in terminal     |
| `codeserver`   | VS Code in browser with Octave extension                   | Edit `.m` files, run via terminal|

To switch variants, edit `.booth/config.toml`:

```toml
variant = "desktop-xfce"   # for the full Octave GUI experience
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | GNU Octave (system package)          |
| Plotting           | gnuplot backend                      |
| Notebook           | Jupyter with Calysto Octave kernel   |
| VS Code extensions | Octave syntax highlighting           |

## Files

| File             | Description                                |
|------------------|--------------------------------------------|
| `example.m`      | Standalone Octave script                   |
| `example.ipynb`  | Jupyter notebook with Octave kernel        |
| `run-octave.sh`  | Shell wrapper to run example.m             |

## Tips

- **Octave Forge packages**: Install within Octave using `pkg install -forge io`
- **MATLAB compatibility**: Octave is largely compatible with MATLAB `.m` files
- **Plotting in notebooks**: Inline plots work automatically with the Calysto kernel
