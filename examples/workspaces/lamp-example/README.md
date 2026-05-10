# LAMP Example

A canonical [LAMP](https://en.wikipedia.org/wiki/LAMP_%28software_bundle%29) stack — Linux + Apache + MySQL + PHP — running on a single CodingBooth container.

## Run

```bash
./booth run
```

Then open http://localhost:8080/ on the host. You should see a PHP-rendered page with a row pulled from MySQL.

## What's inside

- `.booth/Boothfile` — sets up PHP, MySQL, Apache (with mod_php), and the workspace-local `lamp-init` setup.
- `.booth/config.toml` — maps host port 8080 to container port 80.
- `.booth/setups/lamp-init--setup.sh`:
  - Installs `php-mysql` so PHP can talk to MySQL.
  - Drops `/var/www/html/index.php` (the demo page).
  - Registers a startup hook that creates the `lamp_demo` database with a `hello` table on container boot.

## Notes

- Both `apache2` and `mysqld` auto-start via the standard `/usr/share/startup.d/` hooks installed by their respective setups.
- Demo only — no SSL, no production hardening.
