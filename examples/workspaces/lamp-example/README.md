# LAMP Example

This example is a canonical LAMP stack — Linux, Apache, MySQL, and PHP — running on a single CodingBooth container. Apache serves a PHP page that connects to a `lamp_demo` MySQL database and renders one seeded row ("Hi from MySQL!"). It showcases how much a single booth bundles: Apache, MySQL, and PHP all run together inside one container, wired up and auto-starting, while your host stays completely free of a web server or database. This is the classic stack that used to mean XAMPP installers and system services you could never fully uninstall — here it is one disposable container you simply throw away when you're done.

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
