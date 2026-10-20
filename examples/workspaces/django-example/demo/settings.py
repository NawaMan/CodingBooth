SECRET_KEY = "demo-only-not-for-production"
DEBUG = True
ALLOWED_HOSTS = ["*"]

# The demo's views never touch a database, so no apps with models and no
# database: nothing to migrate, and no db.sqlite3 written into the example.
INSTALLED_APPS = []

MIDDLEWARE = [
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "demo.urls"

DATABASES = {}

USE_TZ = True
