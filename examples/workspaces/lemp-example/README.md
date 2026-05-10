# LEMP Example

A canonical [LEMP](https://en.wikipedia.org/wiki/LAMP_%28software_bundle%29#Variants) stack — Linux + nginx + MySQL + PHP-FPM — running on a single CodingBooth container.

## Run

```bash
./booth run
```

Then open http://localhost:8080/ on the host. You should see a PHP-FPM-rendered page with a row pulled from MySQL.

## What's inside

- `.booth/Boothfile` — sets up PHP, MySQL, nginx (with php-fpm wired into the default site), and the workspace-local `lemp-init` setup.
- `.booth/config.toml` — maps host port 8080 to container port 80.
- `.booth/setups/lemp-init--setup.sh`:
  - Installs `php-mysql`.
  - Drops `/var/www/html/index.php` (the demo page).
  - Registers a startup hook that creates the `lemp_demo` database with a `hello` table on container boot.

## Notes

- nginx, php-fpm, and mysqld all auto-start via `/usr/share/startup.d/` hooks.
- Demo only — no SSL, no production hardening.
