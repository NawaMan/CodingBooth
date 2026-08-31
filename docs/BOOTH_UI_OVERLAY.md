# booth UI overlay

> A shared browser overlay layer that sits on top of every booth variant, enabling host-to-booth UI interactions.

The booth UI overlay is the mechanism that allows the host (CLI, scripts, CI pipelines) to present visual UI elements to users working inside a booth. It works by wrapping the variant's web UI in an iframe and injecting an overlay layer on top — giving the host a channel to render content over the booth without modifying the variant itself.

Currently, the overlay is used by [booth message](BOOTH_MESSAGE.md) to show interactive dialogs and toast notifications. The architecture is designed to support additional overlay features in the future.

Back to [README](../README.md)

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Wrapper Page](#wrapper-page)
- [Nginx Configuration](#nginx-configuration)
- [Readiness Gate](#readiness-gate)
- [API Server](#api-server)
- [Overlay HTML Injection](#overlay-html-injection)
- [Adding a Variant](#adding-a-variant)
- [Extending the Overlay](#extending-the-overlay)

---

## Overview

Every booth variant (VS Code, Jupyter, desktop) runs its own web service on an internal port. The overlay system places an nginx reverse proxy in front of that service, serving a wrapper HTML page that:

1. Embeds the variant UI in a full-screen iframe.
2. Injects overlay HTML/CSS/JS on top of the iframe.
3. Routes API calls to a lightweight server that bridges between the overlay and the host filesystem.

This means overlay features work identically across all variants — the variant doesn't need to know about the overlay at all.

---

## Architecture

```
Browser --> nginx (:10000)
              |-- /              --> 302 redirect to /booth
              |-- /booth         --> wrapper HTML (iframe + overlay)
              |-- /booth-messages/api/  --> API server (:10007)
              |-- /*             --> inner service (variant-specific port)
```

**Key ports:**

| Port  | Role |
|-------|------|
| 10000 | Outer port — nginx, exposed to the user's browser |
| 10007 | API server — handles overlay API requests |
| Varies | Inner port — the variant's own service (e.g., 19999 for code-server) |

---

## Wrapper Page

The wrapper page is a minimal HTML document generated at boot time by `start-booth-wrapped`. It consists of:

- A full-screen `<iframe>` pointing at the variant's inner service (via `IFRAME_SRC`).
- The overlay HTML snippet, injected inline from `overlay.html`.

```
variants/base/setups/booth-message-wrapper--setup.sh
  --> installs wrapper.html template to /usr/local/share/booth-message-wrapper/
  --> installs overlay.html
  --> installs nginx.conf.template
  --> installs start-booth-wrapped script
```

At startup, `start-booth-wrapped` substitutes environment variables into the templates and produces the final `index.html` and `nginx.conf`.

**Environment variables used:**

| Variable | Purpose |
|----------|---------|
| `INNER_CMD` | Command to start the variant's inner service |
| `INNER_PORT` | Port the inner service listens on |
| `IFRAME_SRC` | URL path for the iframe src (e.g., `/` or `/lab`) |
| `BOOTH_CONTAINER_NAME` | Displayed in the page title |
| `BOOTH_HOST_PORT` | Displayed in the page title |
| `BOOTH_CODE_PORT` | Outer nginx port (default: 10000) |
| `BOOTH_MSG_API_PORT` | API server port (default: 10007) |

---

## Nginx Configuration

Nginx serves as the single entry point for the booth's browser UI. Its routing rules:

| Path | Behavior |
|------|----------|
| `/` | Redirects to `/booth` (unless `?_booth_inner=1` is set, which proxies to the inner service — used by the iframe itself) |
| `/booth` | Serves the wrapper HTML page |
| `/__booth/health`, `/__booth/info` | Liveness probe and metadata — see [BOOTH_HEALTH.md](BOOTH_HEALTH.md) |
| `/booth-messages/api/*` | Proxies to the API server |
| Everything else | Proxies to the inner service with WebSocket support |

Note what this table means for readiness: `/` and `/booth` are answered by nginx
alone. They come back the moment nginx binds, with the inner service still starting,
so neither is evidence that the booth is up — which is what the readiness gate below
exists for.

The `_booth_inner` query parameter prevents redirect loops — when the iframe loads `/`, it includes this parameter so nginx proxies directly to the inner service instead of redirecting back to `/booth`.

WebSocket support is enabled for all proxied requests to the inner service, which is required by VS Code, Jupyter, and desktop VNC connections.

---

## Readiness Gate

nginx binds the booth's port before the inner service is listening, so a wrapper page
that loads its iframe with the page shows nginx's `502 Bad Gateway` rather than the
variant's UI. The same gap reopens later: `booth restart` restarts the inner service
under a tab that is already open.

`booth-ready.js` closes both. It is injected into `<head>` — by `start-booth-wrapped`
for the wrapped variants and by `start-ttyd-split` for the terminal UI, from the one
copy at `variants/base/setups/booth-ready.js` — and polls `/__booth/health` until the
inner service answers. The page holds its frames back until then, showing a small
"starting the booth" panel instead.

Pages use it through one call:

```js
BoothReady.onUp(function () { iframe.src = wherever; });
```

`onUp` fires on every transition to serving, the first one included, so the same
handler does the initial load and every reload after a restart. `BoothReady.isUp()`
reports the current state for code deciding whether to point a frame somewhere right
now. Because the frames are loaded by script rather than markup, a gated `<iframe>`
carries its target in a data attribute (`data-booth-src` on the wrapper page,
`data-default-src` on the terminal UI's panes) and has no `src` of its own.

### Booth identity

Readiness is not enough on its own, because a booth is reached by port and ports get
reused. Stop one booth, start another on the same port, and the browser hands the URL
to a tab that is already open — which still shows the first booth's page, now driving
a booth that never served it. A terminal UI left over from a base booth asks a
notebook booth for `/s1/` and gets Jupyter's 404; readiness alone reports "up" and
loads it anyway.

So each container start mints a random `BOOTH_INSTANCE_ID`. It goes two places:

- into the page, as `window.BOOTH_INSTANCE_ID`, declared just ahead of the gate;
- onto every `/__booth/health` response, as the `X-Booth-Instance` header — with
  `always`, so it rides the 502 too and a swap is caught before the new booth has
  finished starting.

Every probe compares them. A mismatch means this page belongs to a booth that is
gone, so the gate navigates to the booth's root — the one address every variant
answers for itself — rather than reloading in place, since the path in the bar
belongs to the booth that left.

Both ids must be well-formed hex for a mismatch to count. An image too old to send
the header, or a template that failed to substitute, leaves the check switched off
rather than reloading on a loop; a `sessionStorage` guard backs that up by allowing
at most one reload per booth.

A restart mints a new id as well, so `booth restart` reloads the page outright
instead of only its frames. That is the more correct outcome — the page is
regenerated from the booth's current configuration — and the pane layout survives in
`localStorage`.

---

## API Server

The API server (`booth-message-api-server`) is a lightweight HTTP server built with bash and socat. It bridges between the overlay JavaScript and the host filesystem via bind-mounted directories.

**Current endpoints:**

| Method | Path | Description |
|--------|------|-------------|
| GET | `/booth-messages/api/list` | Returns pending items as a JSON array |
| POST | `/booth-messages/api/respond/<id>` | Writes a response file for the given ID |

The server reads and writes JSON files in `.booth/.tmp/messages/` (bind-mounted from the host). This file-based approach means the CLI on the host and the API server inside the container share state without any network communication between host and container.

**Request/response flow:**

```
Overlay JS                 API Server              Filesystem (.booth/.tmp/messages/)
    |                          |                          |
    |-- GET /list ------------>|                          |
    |                          |-- read *.msg.json ------>|
    |                          |-- skip if .response.json exists
    |<-- JSON array -----------|                          |
    |                          |                          |
    |-- POST /respond/<id> --->|                          |
    |                          |-- write .response.json ->|
    |<-- {"ok":true} ----------|                          |
```

As the overlay is extended with new features, the API server can be extended with additional endpoints under different path prefixes.

---

## Overlay HTML Injection

The overlay HTML is a self-contained snippet (`booth-message-overlay.html`) containing `<style>`, `<div>`, and `<script>` elements. It is injected directly into the wrapper page body, after the iframe.

The overlay uses two rendering modes:

- **Modal** — A fixed-position backdrop (`z-index: 10000`) covering the full viewport. When active, iframe interaction is blocked via `pointer-events: none`. Used for interactive dialogs that require a response.
- **Non-blocking** — Fixed-position elements that don't block iframe interaction. Used for toast notifications (bottom-right corner, `z-index: 10001`).

The overlay JavaScript polls the API server every 2 seconds and updates the DOM based on the response. The API base URL defaults to `/booth-messages/api` but can be overridden via `window.BOOTH_MSG_API_BASE`.

---

## Adding a Variant

To add overlay support to a new variant, create a small wrapper script that sets three environment variables and delegates to `start-booth-wrapped`:

```bash
#!/usr/bin/env bash
set -euo pipefail
export INNER_PORT=19999
export INNER_CMD="start-my-variant $INNER_PORT"
export IFRAME_SRC="/"
exec start-booth-wrapped
```

Existing examples:

| Variant | Script | Inner Port | Iframe Src |
|---------|--------|------------|------------|
| code-server | `start-codeserver-wrapped` | 19999 | `/?_booth_inner=1` |
| notebook | `start-notebook-wrapped` | 19999 | `/lab` |
| desktop | `start-desktop-wrapped` | 19999 | `/` |

The overlay infrastructure (`booth-message-wrapper--setup.sh`) must be installed first as a prerequisite setup.

---

## Extending the Overlay

The overlay is designed to support multiple independent features sharing the same injection point. To add a new overlay feature:

1. **Overlay UI** — Add HTML/CSS/JS to the overlay snippet (or a separate snippet injected alongside it). Use unique CSS class prefixes and high `z-index` values to avoid conflicts.

2. **API endpoints** — Add new endpoints to the API server under a distinct path prefix (e.g., `/booth-timeout/api/`, `/booth-chat/api/`). Update the nginx config template to route the new prefix to the appropriate handler.

3. **Filesystem convention** — Use a separate subdirectory under `.booth/.tmp/` for the new feature's data files (e.g., `.booth/.tmp/timeout/`, `.booth/.tmp/chat/`).

4. **Rendering mode** — Choose modal (blocks iframe) or non-blocking (floats over iframe) depending on the feature's interaction model. Multiple non-blocking elements can coexist; modal overlays should coordinate so only one is active at a time.
