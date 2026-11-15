# Share Example

This booth shows how to **give someone a temporary public link to a server running in your booth**,
for a demo, a webhook, or a quick look from a phone. It uses no port on the host, no firewall
change and no deploy. The link works until you press Ctrl+C.

It selects two tunnel tools. Each one comes with its auto-selected **Share** extension, which adds a
one-word command:

```bash
booth config --no-tui --select 'cloudflared/ngrok'
```

| Command | Tool | Account | URL looks like |
|---|---|---|---|
| `cloudflared-share <port>` | Cloudflare Tunnel (quick tunnel) | **none** | `https://<words>.trycloudflare.com` |
| `ngrok-share <port>` | ngrok agent | free ngrok account (`NGROK_AUTHTOKEN`) | `https://<id>.ngrok-free.app` |

You only need one of them. `--select cloudflared` or `--select ngrok` on its own works the same.
`~share` (e.g. `--select 'ngrok~share'`) drops the command and keeps just the tool.

## Table of Contents

- [Quick Start](#quick-start)
- [Sharing your own server](#sharing-your-own-server)
- [ngrok authtoken](#ngrok-authtoken)
- [Tests](#tests)
- [Security Notes](#security-notes)

## Quick Start

```bash
just share-cloudflare   # serve ./site and share it: prints 🌐 Shared: https://....trycloudflare.com
just share-ngrok        # the same through ngrok (needs NGROK_AUTHTOKEN, see below)
just serve              # only serve ./site on port 8080 in the booth, no sharing
```

Each recipe starts the booth if none is running. Open the printed URL anywhere, on any device.
Ctrl+C stops the tunnel and the server.

## Sharing your own server

Inside any booth that has the tools selected, start your server and share its port:

```bash
npm run dev -- --port 5173 &
cloudflared-share 5173                    # or: ngrok-share 5173
cloudflared-share http://localhost:5173   # a full origin URL works too (https://localhost:8443 ...)
```

- `--verbose` shows the tool's own log lines. Without it you see only the URL and errors.
- Arguments after `--` go to the tool as they are. For example, to put a password on an ngrok link:
  `ngrok-share 8080 -- --basic-auth 'me:a-long-password'`.
- `ngrok-share` also prints ngrok's request inspector, `http://localhost:4040`, which runs inside
  the booth. `booth--expose 4040` shows it on the host.
- Many dev servers (Vite, webpack, Angular) reject requests for an unknown `Host` header. Allow the
  tunnel's host in the server's config, e.g. Vite `server.allowedHosts: ['.trycloudflare.com']`.

## ngrok authtoken

ngrok needs a free account. Copy the token from
<https://dashboard.ngrok.com/get-started/your-authtoken>, then do one of these:

- **From the host:** `NGROK_AUTHTOKEN=<token> just share-ngrok`. The ngrok template passes
  `NGROK_AUTHTOKEN` into the booth when the host has it (`run-args` in `.booth/config.toml`). It
  can also go in `.booth/.env` (git-ignored).
- **In the booth:** `ngrok config add-authtoken <token>`. This saves it in the booth's home, which
  is lost when the booth is removed.

Without a token, `ngrok-share` stops and says how to get one. On the free plan, a browser sees an
ngrok warning page once before your site.

## Tests

```bash
just test                                                    # in the booth
../run-example-tests.sh --example share-example              # from the host
```

- `test001` (Cloudflare) serves the site, shares it, and fetches the public URL back **over the
  internet** to check that it serves this page. It also checks that the booth's own port is refused.
- `test002` (ngrok) checks the missing-token message and the refused port. The live share runs only
  when `NGROK_AUTHTOKEN` is set on the host. Otherwise it is skipped.

Both need internet access from the booth.

## Security Notes

- **Anyone who has the URL can reach the server**, with no password unless you add one (ngrok
  `--basic-auth`). The URLs are random, but treat them as public.
- Both commands **refuse port 10000**, the booth's own terminal / IDE. Sharing that port gives a
  shell in the booth to anyone with the link. `--ok-booth` overrides the refusal. Use it only if
  you mean it, and put a password on the link.
- The tunnel connects outward from the booth, so whatever booth isolation you use, the shared
  server is still public.
- `NGROK_AUTHTOKEN` is in the container's environment, so `docker inspect` on the booth shows it.
