# Pip Example

Demonstrates installing popular Python packages globally on top of the base booth.

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
