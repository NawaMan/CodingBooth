# AnythingLLM Example

This example is a booth that runs [AnythingLLM](https://anythingllm.com) — a
self-hosted RAG chat UI — so you can talk to documents with a local or cloud
LLM. One selector copies the official image, installs `start-anythingllm`, and
(with `+autostart+expose+project-fs+passwordless`) brings the UI up on port 3001 and links
the project into AnythingLLM's file-system agent jail. `just run` waits for
`/api/ping`, which is the same health check AnythingLLM's own Docker image uses.

**Stack:** AnythingLLM 1.16.1, port 3001

The first build copies a **large official image**. Later builds reuse it. Pair
with `ollama+autostart` and point the UI at `http://127.0.0.1:11434` for a fully
local stack — both processes share the booth, so no `host.docker.internal`.

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/anythingllm-example
booth

# 2. Inside the booth — wait for /api/ping
just --list
just run                 # ./demo.sh
```

The UI is at [http://localhost:3001](http://localhost:3001) (`+expose`) and at
`http://booth:3001/` in the globe pane. React Router's basename follows the
page URL (`/` on the host, `/proxy/3001` in the pane). `+passwordless` skips
the login password. This example is **ephemeral** data — every `booth` is a
new AnythingLLM. `+persist` keeps `~/.anythingllm` in `.booth/cache` on this
machine.

## What to try

Once `just run` has printed the ping JSON, open the UI and:

1. Create a workspace.
2. Upload `notes/sample.md` (a short note in this folder).
3. Chat with it. For a local model, select `ollama+autostart` in `booth config`
   and set the LLM provider to Ollama at `http://127.0.0.1:11434`.
4. In chat type `@agent list files in code`. `+project-fs` bind-mounts the
   project at `~/.anythingllm/anythingllm-fs/code` and enables the
   filesystem-agent skill (plain `@agent list files` is workspace RAG and
   stays empty until you upload). Not `+persist`.

`just run` is the scripted health check (`./demo.sh`). The typed path is how you
would actually use AnythingLLM in a project.

## What's included

| Component   | Details                                              |
|-------------|------------------------------------------------------|
| Server      | AnythingLLM (port 3001, copied from the official image) |
| Persistence | ephemeral (default). `+persist` binds `.booth/cache`    |
| Sample      | `notes/sample.md` — a document to upload                |
| Smoke       | `demo.sh` — `/api/ping` round-trip                      |

## Params and env

| Name | Where | Default | Meaning |
|------|--------|---------|---------|
| `ANYTHINGLLM_VERSION` | `booth config` param | `1.16.1` | Official image tag (`COPY --from`) |
| `ANYTHINGLLM_PORT` | param | `3001` | Listen port inside the booth |
| `ANYTHINGLLM_HOST_PORT` | `+expose` param | same as `ANYTHINGLLM_PORT` | Host publish port |
| `AUTH_TOKEN` | AnythingLLM env | unset | Single-user password. Empty = no login (`+passwordless`) |
| `JWT_SECRET` | AnythingLLM env | unset | Session signing; set when a password is enabled |
| `STORAGE_DIR` | AnythingLLM env | `~/.anythingllm` | Workspaces, uploads, SQLite. `+persist` bind-mounts this |
| `SERVER_PORT` | set by `start-anythingllm` | `ANYTHINGLLM_PORT` | Process listen port |
| `ANYTHING_LLM_RUNTIME` | set by `start-anythingllm` | `docker` | Filesystem agent is hidden unless this is `docker` |

Host LM Studio is `http://host.docker.internal:1234/v1`, not `localhost`. Ollama
in the same booth is `http://127.0.0.1:11434`.

Pin via `booth config`: `anythingllm:1.16.1,13001` or `anythingllm+expose:19000`.

`.booth/setups/` copies `anythingllm--setup.sh` so this example builds against a
released base image that does not yet ship it. Keep that copy byte-identical
with `variants/base/setups/`.
