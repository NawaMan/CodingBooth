# R Example

This example is an R environment wired for statistical notebooks through Jupyter. The bundled `example.R` generates a noisy linear dataset, fits a linear model with `lm()`, and prints the regression summary along with the intercept, slope, and R-squared. What makes this demo-worthy is that the IRkernel — R's own Jupyter kernel, and a famously fiddly one to register — is already in place and talking to the notebook UI. No juggling `IRkernel::installspec()`, no missing system libraries, no kernel that fails to appear in the dropdown. Open a notebook, pick R, and you are fitting models, printing summaries, and iterating on statistical analysis interactively from the very first launch — the natural way to do exploratory data work.

**Stack:** R, Jupyter Notebook, IRkernel

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/r-example
booth

# 2. Inside the booth — open VS Code, create a .ipynb file and select the R kernel
```

## What's included

| Component          | Details                              |
|--------------------|--------------------------------------|
| Language           | R                                    |
| Notebook           | Jupyter with IRkernel                |
| VS Code extensions | R language support                   |
