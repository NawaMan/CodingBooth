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

`python+pip-cache` mounts `booth-cache-pip` on `/opt/pip-cache`. On startup, booth-entry sets every directory on that mount to coder, mode 1777, including a root-owned `http-v2` left by the image build. `python+uv-cache` mounts `booth-cache-uv` on the uv cache. The packages in the Boothfile are baked into the image at build time. A package that is not in that list is what fills the volumes. coder cannot write the image environment, so the install goes to a `--target` directory:

```bash
./booth -- 'pip install --target /tmp/py-user six'
./booth -- 'uv pip install --target /tmp/uv-user six'
```

Copy this folder to a second path and run:

```bash
./booth -- 'pip install --target /tmp/py-user2 six'
./booth -- 'uv pip install --offline --target /tmp/uv-user2 six'
```

The second pip install prints `Using cached`. The uv install finishes from `booth-cache-uv`. uv may say it copied the package instead of hardlinking it, because the cache volume is its own filesystem. List the volumes with `docker volume ls --filter label=cb.volume=cache`.

## What's included

| Component | Details                                                                |
|-----------|------------------------------------------------------------------------|
| Runtime   | Python (default)                                                       |
| Packages  | `httpx`, `rich`, `click`, `pytest`, `black`, `ruff`, `cowsay`, `pyfiglet` |

Edit the `install pip ...` line in `.booth/Boothfile` to customise the package set.
