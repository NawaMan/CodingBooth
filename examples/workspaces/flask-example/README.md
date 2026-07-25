# Flask Example

This example is a minimal Flask web app running inside a CodingBooth workspace. It defines two routes: an HTML greeting at `/` and a JSON `pong` response at `/api/ping`, served on port 5555. It showcases reproducibility: Python and Flask are both pinned in the booth, so the same versions come up on your laptop, a colleague's machine, and CI alike. There is no virtualenv to bootstrap and no system Python to fight — the environment is fixed by the workspace, not by whatever happens to be installed on the host.

## Run

```bash
./booth run
# inside the booth:
./run.sh
```

Then open http://localhost:5555/ on the host.

## What's inside

- `.booth/Boothfile` — sets up Python and the Python VS Code extension.
- `.booth/config.toml` — exposes container port 5555 to the host.
- `requirements.txt` — pins `flask==3.1.0`.
- `app.py` — two routes: `/` and `/api/ping`.
- `run.sh` — installs deps and starts the app (run from inside the booth).
