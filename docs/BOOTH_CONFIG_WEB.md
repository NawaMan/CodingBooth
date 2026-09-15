# booth config — Web UI

> The Config TUI, in a browser, on the booth port.

`booth config --web` serves the same template catalog and Config-tab fields as
the interactive TUI, at `http://127.0.0.1:<booth-port>/`. Save writes the same
`.booth/` files `booth config --no-tui` would. This is a **host-side** editor —
no Docker, no running booth — so you can configure a project before the first
`booth` run.

Back to [README](../README.md) | See also: [booth config](BOOTH_CONFIG.md),
[config TUI](BOOTH_CONFIG_TUI.md)

---

## Quick start

```bash
booth config --web
booth config --web --select go+linter --variant codeserver
booth config --web ./my-project
```

The command prints a loopback URL with a one-shot token, opens a browser, and
waits until you Save or Quit.

## How it works

The catalog is the same `TemplateRegistry` the TUI loads — category tabs are
not hard-coded. Add a template under `templates/` and both UIs pick it up.

Save is the TUI save path: selection DSL → compile → write `.booth/`.
Hand-written Boothfile / config.toml still require **keep mine (.new)** or
typing `overwrite`.

## Port

The UI binds **127.0.0.1** on the project's booth port (`--port`, existing
`config.toml`, or **10000**). `NEXT` / `RANDOM` are tokens for a running booth,
not listen addresses; the UI falls back to 10000.

If that port is already taken (a booth is running), the command refuses rather
than stealing it. Stop the booth, or pass `--port` for a free one.

`--web` and `--no-tui` cannot be combined. With no TTY but a display
(`DISPLAY` / `WAYLAND_DISPLAY`), `booth config` without `--web` still opens
this UI so there is something to interact with.

## What it is not

- Not an in-container `/config` page. `.booth/` is read-only inside a booth
  unless you pass `--writable-booth`, and config is a host-side operation on
  purpose (see [Booth Init](implementations/BOOTHINIT.md)).
- Not a live reconfigure of a running container. Save writes files; the next
  `booth` run (or rebuild) picks them up.
