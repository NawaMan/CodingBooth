# Conda Example — Molecule Lab

This example is a small cheminformatics lab in JupyterLab, built on conda. **RDKit**, a C++ chemistry
toolkit with Python bindings, comes prebuilt from conda-forge, together with pandas and matplotlib. The
bundled notebook, `Molecules.ipynb`, takes a dozen well-known drugs (aspirin, caffeine, morphine,
rifampicin…) from their SMILES strings, draws their structures, measures them, checks each against
Lipinski's rule of five, charts weight against lipophilicity, and highlights a substructure search. RDKit
is the textbook case for conda: native code with a pile of compiled dependencies, which conda-forge ships
ready-made for every platform the booth runs on. It is also the textbook trap for conda in Jupyter, and
this booth closes it: the conda environment is registered as its own kernel, so the packages you install
with conda are the ones your notebook imports. Launch the booth and you are drawing molecules in a
browser tab, with nothing installed on your host.

**Stack:** Conda (Miniforge), Python 3.13 (conda env), RDKit, pandas, matplotlib, JupyterLab (notebook
variant)

## Quick start

```bash
# 1. Launch the booth — JupyterLab opens on the booth port (http://localhost:10000)
cd examples/workspaces/conda-example
./booth

# 2. In JupyterLab, open Molecules.ipynb and Run → Run All Cells.
#    The kernel in the top-right corner reads "Python 3.13 (conda)".
```

The same molecules are on the command line too:

```bash
just --list
just run caffeine              # descriptors + rule-of-five verdict
just run aspirin ibuprofen     # several at once
just run 'C1=CC=CC=C1'         # any SMILES — this one is benzene
just list                      # the molecules the lab knows by name
just notebook                  # run the whole notebook headlessly → Molecules.out.ipynb
```

## What's included

| Component  | Details |
|------------|---------|
| Variant    | `notebook` — JupyterLab is the booth's UI |
| Conda      | Miniforge at `/opt/conda`; the env lives under `/opt/conda-envs/` and is linked at `/opt/python` |
| Packages   | `rdkit`, `pandas`, `matplotlib` from conda-forge (`python+conda-pkg`) |
| Kernel     | **Python 3.13 (conda)** — the conda env as a Jupyter kernel (`python+conda-kernel`) |
| Notebook   | `Molecules.ipynb` — structure grid, descriptor table, rule-of-five chart, substructure search |
| CLI        | `src/molecule.py` — the same descriptors for one molecule (`just run <name\|SMILES>`) |

`src/molecules.py` holds the molecule shelf and the descriptor code that both of them use.

## Conda and Jupyter: why the extra kernel

The notebook variant installs JupyterLab into its own Python venv, and its stock kernel, **Python
(venv)**, runs that venv. Conda installs packages into a *different* environment. Without the
`conda-kernel` extension, `import rdkit` in a notebook fails even though `python -c 'import rdkit'` in
the terminal works. The extension installs `ipykernel` into the conda env and registers it as a second
kernel, so pick **Python 3.13 (conda)** for any notebook that needs conda's packages. This notebook
already names it in its metadata, so it opens on the right kernel.

```bash
jupyter kernelspec list        # python (the venv), bash, and conda
```

## Growing the stack

```bash
conda install scikit-learn     # inside the booth, then Kernel → Restart Kernel
```

A package installed that way lasts until the booth is removed. To bake one into the image, add it to
the selection and regenerate:

```bash
booth config --no-tui --overwrite --variant notebook \
  --select 'python:3.12+conda+conda-pkg:rdkit,pandas,matplotlib,scikit-learn+conda-kernel/notebook'
```

`python:3.12` is the notebook's own venv (JupyterLab runs on it); the conda env picks its own Python.
