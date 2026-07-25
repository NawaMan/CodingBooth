# LEMP Example

This example is a canonical LEMP stack — Linux, nginx, MySQL, and PHP-FPM — running on a single CodingBooth container. nginx hands requests to php-fpm, which renders a page showing one seeded row pulled from a `lemp_demo` MySQL database. It showcases how much a single booth bundles: nginx, php-fpm, and MySQL run together in one container, each auto-starting and pre-wired so the path from web server to PHP to database works out of the box. Standing this up by hand normally means three separate services and a pile of socket-and-config glue; here it is one command and one throwaway container that leaves your host untouched.

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
