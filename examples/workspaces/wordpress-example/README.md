# WordPress Example

A self-contained [WordPress](https://wordpress.org/) install — PHP + Apache (mod_php) + MySQL — running on a single CodingBooth container.

## Run

```bash
./booth run
```

Then open http://localhost:8080/ on the host. WordPress's web installer will appear; fill it in with:

| Field           | Value                  |
| --------------- | ---------------------- |
| Database name   | `wordpress`            |
| Database user   | your container user (e.g. `coder`) |
| Database pass   | *(empty)*              |
| Database host   | `localhost`            |
| Table prefix    | `wp_`                  |

Both Apache and MySQL auto-start when the container boots.

## What's inside

- `.booth/Boothfile` — sets up PHP (with Composer), MySQL server, Apache (with mod_php), and a workspace-local `wp-init` setup.
- `.booth/config.toml` — maps host port 8080 to container port 80.
- `.booth/setups/wp-init--setup.sh` — downloads WordPress core into `/var/www/html` at build time, and registers a startup hook that creates the `wordpress` database on container start.

## Notes

- This is a learning/demo install — no SSL, no caching, no production hardening.
- WordPress will write `wp-config.php` into `/var/www/html` after the installer; that lives inside the container and is not persisted across re-builds.
