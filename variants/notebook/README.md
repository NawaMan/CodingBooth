# IDE Notebook Variant

Browser-based JupyterLab environment for interactive development.

**Includes:**
- Python 3.12
- JupyterLab
- Bash kernel for notebooks
- Web Preview — view a server running in the booth (e.g. port `3000`) in JupyterLab tabs, from the Launcher; **Markdown Viewer** browses the project's `.md` files with `viewmd` ([details](../../docs/BOOTH_VARIANTS.md#web-preview-1))

**Usage:**
```bash
booth --variant notebook
```

**Access:** Open browser to `http://localhost:10000` (default booth port) for the JupyterLab interface.

**Purpose:** Ideal for data science, exploratory programming, and interactive documentation.
