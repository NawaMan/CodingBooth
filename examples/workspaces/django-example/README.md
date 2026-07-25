# Django Example

This example is a minimal Django web app running inside a CodingBooth workspace. Its two view functions serve an HTML greeting at `/` and a JSON `{"status": "ok", "message": "pong"}` response at `/api/ping`, backed by a local SQLite database. It showcases reproducibility: the Python interpreter and the exact Django version are pinned inside the booth, so the app you run today is the same app a teammate runs six months from now. There is no "works on my machine" and no dependency drift — clone the workspace and the runtime materializes exactly as specified, on any host, every single time.

## Run

```bash
./booth run
# inside the booth:
pip install -r requirements.txt
python manage.py runserver 0.0.0.0:8000
```

Then open:
- http://localhost:8000/ — text greeting
- http://localhost:8000/api/ping — JSON

## What's inside

- `.booth/Boothfile` — Python and the Python VS Code extension.
- `.booth/config.toml` — exposes container port 8000.
- `requirements.txt` — pins `django==5.1.4`.
- `manage.py` — Django entry point.
- `demo/settings.py` — minimal settings (sqlite, debug=True, hosts=*).
- `demo/urls.py` — two view functions: `/` and `/api/ping`.

This deliberately skips `INSTALLED_APPS` admin/sessions/etc. for a one-page demo. Add them as you'd add them to any Django project.
