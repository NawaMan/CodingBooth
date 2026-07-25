# Pip Deps Example

This example pre-installs Python packages at booth-build time using `pip` and a project-local `requirements.txt`. It runs `pip install -r .booth/requirements.txt` during the image build to bake in requests and flask before the booth is ever launched. Pre-baked deps: requirements are installed at image build time for an offline-fast first run with nothing left to download. Teammates and CI can clone, launch, and be productive in seconds — no waiting on `pip install`, no flaky network stalling a demo, and the exact same package versions for everyone. The dependency work happens once, at build time, instead of on every fresh checkout.

**Stack:** Python, pip

## Quick start

```bash
# 1. Launch the booth (dependencies are installed during the image build)
cd examples/workspaces/pip-deps-example
booth

# 2. Inside the booth — the packages from .booth/requirements.txt are already importable
python -c "import requests; print(requests.__version__)"
```

## What's included

| Component | Details                                                            |
|-----------|--------------------------------------------------------------------|
| Runtime   | Python (default)                                                   |
| Build     | `pip install -r .booth/requirements.txt` during image build        |

Edit `.booth/requirements.txt` to change which packages are baked into the image.
