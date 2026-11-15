# Share Example

You are building an app in a booth. It works and you want someone to see it, or it doesn't and
you want someone to look. This example shows how to **give them a temporary public link to the app
running in your booth**. There's no deploy, no host port to open and no firewall change. The link
works until you press Ctrl+C.

The app is a small **Notes Board** with the usual two dev servers:

| Server | Port | Code | What it is |
|---|---|---|---|
| API | 3001 | `api/server.js` | JSON notes API (`/api/notes`, `/api/health`), in memory |
| Front end | 8080 | `web/server.js` + `web/public/` | the page; forwards `/api/*` to the API, like a Vite dev proxy |

Both are plain Node.js with no `npm install`, run under `node --watch`. Edit a server and it
restarts. Edit `web/public/` and reload the page.

The booth is:

```bash
booth config --no-tui --select 'nodejs/cloudflared/ngrok' --expose +8080 --expose +3001
```

`cloudflared` and `ngrok` each bring an auto-selected **Share** extension, which adds
`cloudflared-share <port>` / `ngrok-share <port>`. You only need one. Cloudflare needs no account.

## Table of Contents

- [The workflow](#the-workflow)
- [Which one to share](#which-one-to-share)
- [Sharing your own app](#sharing-your-own-app)
- [ngrok authtoken](#ngrok-authtoken)
- [Tests](#tests)
- [Security Notes](#security-notes)

## The workflow

```bash
# Terminal 1: develop
just dev          # API on :3001 + front end on :8080, logs prefixed [api] / [web]; Ctrl+C stops both
just ports        # where they are on the host (published at booth port + 8080 / + 3001)

# Terminal 2: when you want someone to look
just share-web    # 🌐 Shared: https://<words>.trycloudflare.com  -> send that link
```

The person you send it to sees your running app and can add notes. You see their requests in the
`[api]` log, and their notes show up on your page within 3 seconds. Keep editing while they watch:
a reload on their side picks up your change. Ctrl+C in terminal 2 ends the share and the dev
servers keep running.

The recipes work from the host (they run in the booth through `./booth exec`) and from a shell
inside the booth.

| Recipe | Does |
|---|---|
| `just dev` | start the API and the front end for development |
| `just share-web` | share the front end, which is the whole app, on a Cloudflare URL |
| `just share-api` | share only the API on its own Cloudflare URL |
| `just share-web-ngrok` / `just share-api-ngrok` | the same through ngrok |
| `just ports` | the host addresses of the published ports |
| `just test` | the example's tests |

## Which one to share

- **`share-web` covers almost every case.** The front end calls the API on its own origin
  (`/api/...`), and `web/server.js` forwards those calls. One link gives the page *and* its API.
  It's the same reason a Vite or webpack dev server's proxy makes an app shareable from one port.
- **`share-api`** is for when someone needs the API by itself: a teammate's front end running on
  their machine, a mobile app, `curl`, or a webhook sender (Stripe, GitHub). The API sends open
  CORS headers, so a page on another origin can call it. Try `curl <url>/api/notes`.

The two links are independent, and you can run both at once.

## Sharing your own app

In any booth with the tools selected, start your servers and share the port people should open:

```bash
cloudflared-share 5173                    # or: ngrok-share 5173
cloudflared-share http://localhost:5173   # a full origin URL works too (https://localhost:8443 ...)
```

- `--verbose` shows the tool's own log lines. Without it you see only the URL and errors.
- Arguments after `--` go to the tool as they are. For example, to put a password on an ngrok link:
  `ngrok-share 8080 -- --basic-auth 'me:a-long-password'`.
- Many dev servers (Vite, webpack, Angular) reject requests for an unknown `Host` header. Allow the
  tunnel's host in the server's config, e.g. Vite `server.allowedHosts: ['.trycloudflare.com']`.
- If the front end calls the API by an absolute `http://localhost:3001` URL, it breaks for the
  person you shared with, because their localhost is not your booth. Use a dev-server proxy (as
  here) or a relative `/api` path.

## ngrok authtoken

ngrok needs a free account. Copy the token from
<https://dashboard.ngrok.com/get-started/your-authtoken>, then do one of these:

- **From the host:** start the booth with `NGROK_AUTHTOKEN=<token>` set, e.g.
  `NGROK_AUTHTOKEN=<token> just dev`. The ngrok template passes the variable into the booth when the
  host has it. It can also go in `.booth/.env` (git-ignored).
- **In the booth:** `ngrok config add-authtoken <token>`. This saves it in the booth's home, which
  is lost when the booth is removed.

Without a token, `ngrok-share` stops and says how to get one. On the free plan, a browser sees an
ngrok warning page once before your app. `ngrok-share` also prints ngrok's request inspector,
`http://localhost:4040` in the booth, which `booth--expose 4040` shows on the host.

## Tests

```bash
just test                                                    # in the booth
../run-example-tests.sh --example share-example              # from the host
```

- `test001` (Cloudflare) runs `dev.sh` on spare ports. It checks the page and the `/api` proxy
  locally, then shares the front end and the API and fetches **both public URLs back over the
  internet**. It also checks that the booth's own port is refused.
- `test002` (ngrok) checks the missing-token message and the refused port. The live share runs only
  when `NGROK_AUTHTOKEN` is set on the host. Otherwise it is skipped.

Both need internet access from the booth.

## Security Notes

- **Anyone who has the URL can reach the app**, with no password unless you add one (ngrok
  `--basic-auth`). The URLs are random, but treat them as public, and stop sharing when you're done.
- Both commands **refuse port 10000**, the booth's own terminal / IDE. Sharing that port gives a
  shell in the booth to anyone with the link. `--ok-booth` overrides the refusal. Use it only if
  you mean it, and put a password on the link.
- The tunnel connects outward from the booth, so the shared app is public whatever the booth's own
  port settings are.
- `NGROK_AUTHTOKEN` is in the container's environment, so `docker inspect` on the booth shows it.
