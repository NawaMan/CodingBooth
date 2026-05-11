# Conda Example

Python data-science environment built on Miniconda with NumPy preinstalled.

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
