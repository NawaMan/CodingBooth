# Flask Example

A minimal [Flask](https://flask.palletsprojects.com/) web app running inside a CodingBooth workspace.

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
