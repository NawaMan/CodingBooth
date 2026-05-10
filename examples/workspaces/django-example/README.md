# Django Example

A minimal [Django](https://www.djangoproject.com/) web app running inside a CodingBooth workspace.

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
