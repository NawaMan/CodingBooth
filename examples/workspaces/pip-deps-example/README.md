# Pip Deps Example

Demonstrates pre-installing Python packages at booth-build time using `pip` and a project-local `requirements.txt`.

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
