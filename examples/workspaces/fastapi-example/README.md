# FastAPI Example

This example is a minimal FastAPI async web app running inside a CodingBooth workspace. It serves a JSON greeting at `/` and a JSON `pong` at `/api/ping`, with FastAPI's auto-generated Swagger UI at `/docs`. It showcases CodingBooth's port exposure: the uvicorn server started inside the container is automatically forwarded to your host, so you open `localhost` in your normal browser and it just works. FastAPI's interactive Swagger UI at `/docs` comes across the same way — a live API playground running in an isolated container yet reachable as if it were native, with no manual port plumbing to set up.

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
