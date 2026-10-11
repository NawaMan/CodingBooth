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

## Shared download cache

`python+pip-cache` mounts `booth-cache-pip` on `/opt/pip-cache` (mode 1777, the directory the Python setup creates). `python+uv-cache` mounts `booth-cache-uv` on the uv cache. The packages in the Boothfile are baked into the image at build time. A package that is not in that list is what fills the volumes:

```bash
./booth -- pip install six
./booth -- uv pip install --system six
```

Copy this folder to a second path and run:

```bash
./booth -- pip install --no-index six
./booth -- uv pip install --offline --system six
```

The second booth installs from the volumes. List them with `docker volume ls --filter label=cb.volume=cache`.

## What's included

| Component | Details                                                                |
|-----------|------------------------------------------------------------------------|
| Runtime   | Python (default)                                                       |
| Packages  | `httpx`, `rich`, `click`, `pytest`, `black`, `ruff`, `cowsay`, `pyfiglet` |

Edit the `install pip ...` line in `.booth/Boothfile` to customise the package set.
