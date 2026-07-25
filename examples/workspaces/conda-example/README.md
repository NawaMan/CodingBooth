# Conda Example

This example is a Python data-science environment built on Miniconda with NumPy preinstalled. The bundled `src/stats.py` takes numbers on the command line and uses NumPy to report their count, sum, mean, median, standard deviation, min, max, and range. Batteries-included: a Miniconda data-science stack (Python plus NumPy) is ready in a single launch. Skip the notoriously fiddly conda setup, the environment activation dance, and the native-library build errors — it is all resolved once and baked in. Launch the booth and you are computing statistics on real arrays immediately, with `conda install` on hand whenever you need to grow the stack.

**Stack:** Conda (Miniconda), Python 3.12, NumPy

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/conda-example
booth

# 2. Inside the booth — run the stats sample
./run-stats.sh 1 2 3 4 5
```

## What's included

| Component | Details                                  |
|-----------|------------------------------------------|
| Python    | 3.12 (managed by conda)                  |
| Packages  | `numpy` (preinstalled via `install conda`) |
| Sample    | `src/stats.py` — mean/median/stdev demo  |

Install more packages inside the booth with `conda install <pkg>` or `pip install <pkg>`.
