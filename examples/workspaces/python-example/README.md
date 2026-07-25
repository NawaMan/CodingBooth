# Python Example

This example is a Python 3.13 environment wired for interactive work in Jupyter notebooks. The bundled `Main.py` prints a quick environment check — the Python version, host platform, the current time, and a 2+2 sanity test — while the companion notebooks run the same kind of code cell by cell. Here is why it is worth a look: the fiddly ipykernel that normally trips people up during setup is already registered and wired to the notebook UI. Open any `.ipynb`, pick the Python kernel, and you are running live cells in seconds — no `pip install`, no kernelspec surgery, no version drift between your interpreter and your notebook. It is the whole interactive-Python experience, ready the instant the booth starts.

**Stack:** Python 3.13, Jupyter Notebook, ipykernel, XFCE desktop, Claude Code

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/python-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the Python kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | Python 3.13                          |
| Notebook           | Jupyter with ipykernel               |
| VS Code extensions | Python language support              |
| Desktop            | XFCE                                 |
| AI                 | Claude Code                          |
