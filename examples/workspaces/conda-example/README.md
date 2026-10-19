# Conda Example — from a latency report to a Molecule Lab

This example is a Python data booth built on conda, opening in JupyterLab. Conda installs pandas,
matplotlib and **RDKit** from conda-forge, and the booth registers the conda environment as its own
Jupyter kernel, so the packages conda installs are the ones your notebooks import. Three examples
share it, from simple to complex. The first is a script that reads a web API's request log and
reports p50/p95/p99 latency per endpoint, the question every backend developer has asked. The
second is the same log in a notebook, with charts that find the slow endpoint and the four-minute
incident hiding in it. The third is a cheminformatics lab: it draws a dozen well-known drugs from
their SMILES strings and tests them against Lipinski's rule of five, using RDKit, a C++ toolkit that
is the textbook case for conda's prebuilt native packages. Launch the booth and all three run, with
nothing installed on your host.

**Stack:** Conda (Miniforge), Python 3.13 (conda env), pandas, matplotlib, RDKit, JupyterLab
(notebook variant)

## Three examples, simple to complex

| # | Example | Kind | What it shows | Run it |
|---|---------|------|---------------|--------|
| 1 | **API latency report** | script | Read a CSV with pandas; p50 / p95 / p99 and error rate per endpoint | `just run` |
| 2 | **API latency notebook** — `Latency.ipynb` | notebook | The same log, charted: latency histogram, slowest endpoint, an incident over time | open in JupyterLab |
| 3 | **Molecule Lab** — `Molecules.ipynb` | notebook + script | RDKit, a native library conda ships prebuilt: structure drawings, drug-likeness, a substructure search | open in JupyterLab, or `just molecule caffeine` |

Examples 1 and 2 read the same file, `data/requests.csv`: 30 minutes of traffic to a small API
(595 requests, five endpoints). Example 2 imports its numbers from the script in example 1
(`src/latency.py`), and example 3's notebook and script share `src/molecules.py`.

## Quick start

```bash
# 1. Launch the booth — JupyterLab opens on the booth port (http://localhost:10000)
cd examples/workspaces/conda-example
./booth

# 2. In JupyterLab, open Latency.ipynb, then Molecules.ipynb, and Run → Run All Cells.
#    The kernel in the top-right corner reads "Python 3.13 (conda)".
```

From a terminal, on the host or in the booth:

```bash
just                           # the recipes, in example order
just run                       # 1. latency report, every endpoint, slowest p95 first
just run /api/search           # 1. one endpoint
just latency-notebook          # 2. run Latency.ipynb headlessly → Latency.out.ipynb
just molecule caffeine         # 3. descriptors + rule-of-five verdict
just molecule 'C1=CC=CC=C1'    # 3. any SMILES — this one is benzene
just molecules                 # 3. the molecules the lab knows by name
just molecule-notebook         # 3. run Molecules.ipynb headlessly → Molecules.out.ipynb
```

`just run` prints:

```text
595 requests, 10:00:03 to 10:30:04

                  requests  p50_ms  p95_ms  p99_ms  errors_%
route
GET /api/search        113   300.2  2111.4  3124.0      12.4
POST /api/orders        90   161.8   328.2   347.1       2.2
GET /api/orders        157    86.2   182.6   216.3       2.5
GET /api/users         172    40.2    74.8    96.1       0.6
GET /health             63     3.0     5.0     5.5       0.0

Slowest p95: GET /api/search (2111 ms)
```

## What's included

| Component  | Details |
|------------|---------|
| Variant    | `notebook` — JupyterLab is the booth's UI |
| Conda      | Miniforge at `/opt/conda`; the env lives under `/opt/conda-envs/` and is linked at `/opt/python` |
| Packages   | `pandas`, `matplotlib`, `rdkit` from conda-forge (`python+conda-pkg`) |
| Kernel     | **Python 3.13 (conda)** — the conda env as a Jupyter kernel (`python+conda-kernel`) |
| Data       | `data/requests.csv` — the request log behind examples 1 and 2 |
| Scripts    | `src/latency.py` (example 1), `src/molecule.py` + `src/molecules.py` (example 3) |
| Notebooks  | `Latency.ipynb` (example 2), `Molecules.ipynb` (example 3) |

## Conda and Jupyter: why the extra kernel

The notebook variant installs JupyterLab into its own Python venv, and its stock kernel, **Python
(venv)**, runs that venv. Conda installs packages into a *different* environment. Without the
`conda-kernel` extension, `import rdkit` in a notebook fails even though `python -c 'import rdkit'` in
the terminal works. The extension installs `ipykernel` into the conda env and registers it as a second
kernel, so pick **Python 3.13 (conda)** for any notebook that needs conda's packages. Both notebooks
here already name it in their metadata, so they open on the right kernel.

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
