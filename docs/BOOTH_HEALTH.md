# booth health & info

> Two HTTP endpoints served by the wrapper nginx that let external callers check whether a booth is actually serving — and read basic metadata about it.

Every booth variant exposes:

- `GET /__booth/health` — liveness probe. 200 when the service behind nginx is reachable, 5xx/timeout when it isn't.

Every wrapped variant (codeserver, desktop-xfce, desktop-kde, desktop-lxqt, notebook) additionally exposes:

- `GET /__booth/info` — metadata blob (container name, variant, version, port). Always 200 as long as the wrapper nginx is up.

For the wrapped variants both endpoints come from the shared wrapper nginx template, so adding a variant that uses `start-booth-wrapped` gets them for free. The terminal-only (ttyd-split) variant serves `/__booth/health` from its own template, probing session 1's ttyd; it has no inner web service to describe, so it does not serve `/__booth/info`.

Back to [README](../README.md)

---

## Table of Contents

- [Why not just check the port?](#why-not-just-check-the-port)
- [`/__booth/health`](#__boothhealth)
- [`/__booth/info`](#__boothinfo)
- [Usage examples](#usage-examples)
- [Known limitation: XFCE / KDE desktop](#known-limitation-xfce--kde-desktop)
- [Implementation](#implementation)

---

## Why not just check the port?

A bare `curl http://localhost:PORT/` may return 200 even when the booth is not truly ready — and on every variant, it does. nginx answers the root itself, without touching the service behind it: the terminal UI's root is a file on disk, and a wrapped variant's is a bare `return 302 /booth`. Both come back the instant nginx binds, while ttyd or code-server is still starting, so a page opened on that signal fills its frames with nginx's 502 instead.

A dedicated health endpoint:

- Proves the HTTP response came from the booth's own wrapper nginx (the `/__booth/*` namespace is reserved).
- Actively probes the inner service on every request, so it will fail when the inner is down.
- Ships `Cache-Control: no-store` and a dynamic timestamp, so intermediaries can't silently cache a stale "ok".

---

## `/__booth/health`

**Request:**

```
GET /__booth/health
```

**Responses:**

| HTTP status | Meaning |
|-------------|---------|
| `200 OK`    | Inner service responded (any 2xx/3xx/4xx is normalized to 200). |
| `502 Bad Gateway` | The wrapper tried to proxy to the inner service and the connection was refused. |
| `504 Gateway Timeout` | The inner service did not respond within the probe timeout. |

**Body (on 200):**

```
ok 2026-04-19T00:53:30+00:00
```

Format: `ok <ISO-8601 UTC timestamp>\n`. The timestamp is regenerated on every request — if it doesn't change between two calls, something is caching.

**Headers:**

- `Cache-Control: no-store`
- `Content-Type: text/plain`
- `X-Booth-Instance: <hex>` — identifies this container start. Sent on the 502/504 responses too (`always`). Ports get reused, so this is how a browser tab tells the booth it was served by from whatever booth is on that port now; the UI's readiness gate reloads itself when it stops matching. A restart mints a new one.

**Probe details:**

- Connect timeout: 2 seconds.
- Read timeout: 3 seconds.
- Statuses treated as "alive": `200, 301, 302, 303, 304, 307, 308, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 415, 416, 417, 418, 422, 429`. All rewritten to 200.

---

## `/__booth/info`

**Request:**

```
GET /__booth/info
```

**Response:** always `200 OK` (independent of the inner service — this endpoint is served by nginx directly).

**Body:**

```json
{"booth":"<container-name>","variant":"<variant-tag>","version":"<version-tag>","port":"<host-port>"}
```

Example:

```json
{"booth":"playground2","variant":"codeserver","version":"0.45.0--rc1","port":"10000"}
```

**Fields:**

| Field     | Source env var         | Example              |
|-----------|------------------------|----------------------|
| `booth`   | `BOOTH_CONTAINER_NAME` | `playground2`        |
| `variant` | `BOOTH_VARIANT_TAG`    | `codeserver`         |
| `version` | `BOOTH_VERSION_TAG`    | `0.45.0--rc1`        |
| `port`    | `BOOTH_HOST_PORT`      | `10000`              |

Missing values render as `unknown` (for variant/version) or the empty string.

---

## Usage examples

**Quick liveness check:**

```bash
curl -i http://localhost:10000/__booth/health
```

Exit code of curl is 0 if any response arrived; for a shell-friendly "is it up?" use:

```bash
if curl -fsS --max-time 5 http://localhost:10000/__booth/health >/dev/null; then
  echo "booth is up"
else
  echo "booth is down"
fi
```

**Poll until ready (e.g. in CI):**

```bash
for _ in $(seq 1 60); do
  curl -fsS --max-time 4 http://localhost:10000/__booth/health >/dev/null && break
  sleep 1
done
```

**Read metadata:**

```bash
curl -s http://localhost:10000/__booth/info | jq .
```

---

## Known limitation: XFCE / KDE desktop

For desktop variants, the wrapper's inner service is a noVNC / web-VNC front-end. Those static pages respond 200 even when the VNC backend is dead or disconnected. `/__booth/health` will therefore report "up" as long as the web layer is serving, even if no desktop session is actually running.

A future per-variant probe can address this (e.g. TCP-connect to the VNC socket, or call a desktop-internal endpoint). For now, treat desktop health as "the web front-end is up" rather than "the desktop session is interactive".

The desktop variants also return the wrong *body*. `error_page` can only intercept the statuses listed above, and noVNC answers the probe with a 200 — so nginx passes its page straight through, and the response is ~5 KB of `text/html` rather than `ok <timestamp>`. The status is still correct (200 up, 502/504 down), so callers that check the status — `booth run`'s wait and `booth-ready.js` — work as documented; only a caller parsing the body would be surprised. The wrapped variants whose inner service answers with a redirect (codeserver, notebook) are unaffected.

`codeserver` and `notebook` variants do not have this limitation — their inner service is the application itself, so a reachable inner means the application is actually answering.

---

## Implementation

The endpoints are defined in the shared wrapper nginx template:

- Template source: [`variants/base/setups/booth-message-wrapper--setup.sh`](../variants/base/setups/booth-message-wrapper--setup.sh)
- Rendered at container start by `start-booth-wrapped` using `envsubst` against the runtime environment.
- Inner service URL is `http://127.0.0.1:${INNER_PORT}/`, where `INNER_PORT` is set by the variant-specific `start-<variant>-wrapped` script.

For the terminal (ttyd-split) variant:

- Template source: [`variants/base/web-ttyd-split/nginx.conf.template`](../variants/base/web-ttyd-split/nginx.conf.template), rendered by `start-ttyd-split`.
- It probes `http://127.0.0.1:10001/s1` — session 1's ttyd, at the un-slashed base path. ttyd answers that with an empty 302, which the `error_page` list turns into this endpoint's own `ok` body; asking for `/s1/` would get a 200 instead, and `error_page` cannot intercept a 200, so the whole terminal page would come back as the health response.

**Who reads it:** `booth run` waits on this endpoint before opening a browser, and every variant's UI polls it to decide when to load its frames (`variants/base/setups/booth-ready.js`). Both exist because the root cannot answer the question.

Test: [`tests/basic/test012--booth-health.sh`](../tests/basic/test012--booth-health.sh) starts a codeserver booth, polls `/__booth/health` until 200, and asserts the `/__booth/info` payload shape.
