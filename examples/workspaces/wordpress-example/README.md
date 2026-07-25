# WordPress Example

This example is a self-contained WordPress install — PHP, Apache with mod_php, and MySQL — running on a single CodingBooth container. On boot it serves WordPress core's web installer at port 8080 against an auto-created `wordpress` MySQL database, ready for you to complete the famous five-minute setup. It showcases pre-baked dependencies: WordPress core is downloaded into the image at build time and PHP, Apache, and MySQL all come up together, so the very first boot drops you straight onto the famous installer with nothing left to fetch. There is no download-unzip-configure dance and no LAMP stack to assemble by hand — a complete, ready-to-run WordPress environment materializes from a single command.

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
