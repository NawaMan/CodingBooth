# LEMP Example

This example is a canonical LEMP stack — Linux, nginx, MySQL, and PHP-FPM — running on a single CodingBooth container. nginx hands requests to php-fpm, which renders a page showing one seeded row pulled from a `lemp_demo` MySQL database. It showcases how much a single booth bundles: nginx, php-fpm, and MySQL run together in one container, each auto-starting and pre-wired so the path from web server to PHP to database works out of the box. Standing this up by hand normally means three separate services and a pile of socket-and-config glue; here it is one command and one throwaway container that leaves your host untouched.

## Run

```bash
./booth run
```

Then open http://localhost:8080/ on the host. You should see a PHP-FPM-rendered page with a row pulled from MySQL.

### Run it

```bash
just --list
just page                # ./demo.sh page — the page nginx + PHP-FPM render, with the row from MySQL
just db                  # ./demo.sh db — the lemp_demo.hello table itself
just status              # ./demo.sh status — nginx, php-fpm and mysqld running
just versions            # PHP, MySQL and nginx versions
```

With no booth running, each recipe starts one and stops it again afterwards, so it waits
for the services the booth starts (up to 60s) before it checks anything. To browse the page,
keep a booth up with `./booth run` or `just shell`.

## What's inside

- `.booth/Boothfile` — PHP, MySQL, nginx+php-fpm, and the project-local `lemp-init` demo.
- `.booth/config.toml` — maps host port 8080 to container port 80.
- `.booth/setups/lemp-init--setup.sh`:
  - Installs `php-mysql`.
  - Drops `/var/www/html/index.php` (the demo page).
  - Registers a startup hook that creates the `lemp_demo` database with a `hello` table on container boot.

## Notes

- nginx, php-fpm, and mysqld all auto-start via `/usr/share/startup.d/` hooks.
- Demo only — no SSL, no production hardening.
