# n8n Example

[n8n](https://n8n.io/) 2.41.5, installed with npm onto catalog Node.js 24. Workflows live in SQLite under `~/.n8n`. This booth selects `+autostart`, `+expose`, `+persist`, `+sandbox`, and `+search`: the editor starts on boot, host port 21200 publishes container port 21200, `~/.n8n` is kept in `.booth/cache` (gitignored, this machine only), and the n8n Assistant gets its code sandbox and web search. A fresh clone does not contain that cache directory. Run `../../../codingbooth config --no-tui --overwrite` once and the header's `+persist` recreates the mount marker.

**Stack:** n8n 2.41.5, Node.js 24, SQLite, port 21200, n8n sandbox service 1.3.4 and SearXNG on Docker-in-Docker

`+sandbox` and `+search` run on Docker-in-Docker, a privileged sidecar, so booth asks `[y/N]` before it starts. `--dind-allowed` skips the question.

## Quick start

```bash
cd examples/workspaces/n8n-example
../../../codingbooth

# the editor is already starting
curl http://localhost:21200/healthz
just health
```

Open http://localhost:21200 . `N8N_SECURE_COOKIE` is false so plain HTTP from the host is accepted.

`workflows/forty-two.json` is a one-node workflow that returns 42. Stop the server before importing, so SQLite is not locked:

```bash
stop-n8n
n8n import:workflow --input=workflows/forty-two.json
n8n list:workflow
```

## What's included

| Component | Details |
|-----------|---------|
| Editor | n8n 2.41.5 (`start-n8n` / `stop-n8n`) |
| Data | `~/.n8n` via `+persist` |
| Code nodes | JavaScript and Python, both in internal task runners (no Docker) |
| Assistant sandbox | n8n's sandbox service on `127.0.0.1:21280` inside the booth (`+sandbox`, `start-n8n-sandbox` / `stop-n8n-sandbox`); first boot pulls three images, log in `/tmp/n8n-sandbox.log` |
| Assistant web search | SearXNG on `127.0.0.1:21281` inside the booth (`+search`, `start-n8n-search` / `stop-n8n-search`), log in `/tmp/n8n-search.log`. For steadier results put a Brave Search key in `.booth/.env` as `INSTANCE_AI_BRAVE_SEARCH_API_KEY`; it takes priority |
| Port | 21200 on the host and in the container |
| Sample | `workflows/forty-two.json` |

`n8n:2.41.5,5678` is the upstream port. The recipe is `.booth/recipes/n8n.recipe` (`@n8n`).
