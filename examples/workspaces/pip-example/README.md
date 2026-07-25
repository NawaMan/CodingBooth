# Pip Example

This example installs popular Python CLI tools and libraries globally on top of the base booth. It preinstalls packages such as httpx, rich, click, pytest, black, ruff, cowsay, and pyfiglet, so commands like `cowsay` and `pyfiglet` work the moment the booth starts. Host stays clean: these Python CLIs and libraries install inside the booth, never in your host's site-packages. Try a whole stack of tools without polluting your machine or colliding with the Python versions and packages you already depend on. When you're done, delete the booth and your host is exactly as it was — no leftover globals, no `pip uninstall` cleanup.

**Stack:** Python, pip-installed CLI tools

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/pip-example
booth

# 2. Inside the booth — try the preinstalled tools
cowsay "hello from pip-example"
pyfiglet codingbooth
pytest --version
```

## What's included

| Component | Details                                                                |
|-----------|------------------------------------------------------------------------|
| Runtime   | Python (default)                                                       |
| Packages  | `httpx`, `rich`, `click`, `pytest`, `black`, `ruff`, `cowsay`, `pyfiglet` |

Edit the `install pip ...` line in `.booth/Boothfile` to customise the package set.
