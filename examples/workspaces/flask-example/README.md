# Flask Example

A minimal [Flask](https://flask.palletsprojects.com/) web app running inside a CodingBooth workspace.

## Run

```bash
./booth run
# inside the booth:
pip install -r requirements.txt
python app.py
```

Then open http://localhost:5000/ on the host.

## What's inside

- `.booth/Boothfile` — sets up Python and the Python VS Code extension.
- `.booth/config.toml` — exposes container port 5000 to the host.
- `requirements.txt` — pins `flask==3.1.0`.
- `app.py` — two routes: `/` and `/api/ping`.
