# FastAPI Example

A minimal [FastAPI](https://fastapi.tiangolo.com/) async web app running inside a CodingBooth workspace.

## Run

```bash
./booth run
# inside the booth:
pip install -r requirements.txt
uvicorn app:app --host 0.0.0.0 --port 8000 --reload
```

Then open:
- http://localhost:8000/ — JSON greeting
- http://localhost:8000/docs — interactive Swagger UI

## What's inside

- `.booth/Boothfile` — sets up Python and the Python VS Code extension.
- `.booth/config.toml` — exposes container port 8000 to the host.
- `requirements.txt` — pins `fastapi` and `uvicorn`.
- `app.py` — two routes: `/` and `/api/ping`.
