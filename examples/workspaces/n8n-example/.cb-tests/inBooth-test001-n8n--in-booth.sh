#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# +autostart already launched n8n. Wait until /healthz answers, then leave
# the server up so the host test can curl the published port.

set -euo pipefail

echo "=== n8n version and /healthz ==="
ver="$(n8n --version 2>&1 || true)"
echo "$ver" | grep -q "2.41.5" || { echo "expected 2.41.5, got: $ver"; exit 1; }

ok=0
i=0
while [[ "$i" -lt 40 ]]; do
    if curl -fsS http://127.0.0.1:21200/healthz > /tmp/n8n-health.txt 2>/dev/null; then
        if grep -Eq '"status"[[:space:]]*:[[:space:]]*"ok"' /tmp/n8n-health.txt; then
            ok=1
            break
        fi
    fi
    i=$((i + 1))
    sleep 3
done

if [[ "$ok" != 1 ]]; then
    echo "n8n did not answer /healthz"
    cat /tmp/n8n-health.txt 2>/dev/null || true
    cat /tmp/n8n.log 2>/dev/null || true
    exit 1
fi
echo "health: $(cat /tmp/n8n-health.txt)"

# +persist mounts ~/.n8n, so the database has to be there, not one level down.
[[ -f "$HOME/.n8n/database.sqlite" ]] || { echo "expected ~/.n8n/database.sqlite"; ls -la "$HOME/.n8n" || true; exit 1; }
[[ ! -e "$HOME/.n8n/.n8n" ]] || { echo "unexpected nested ~/.n8n/.n8n"; exit 1; }
echo "data: ~/.n8n/database.sqlite"

# +sandbox: n8n must carry the sandbox settings, and the sandbox service must
# run a command. The service is called with n8n's own client, as the Assistant
# would. First boot pulls three images, so the wait is long.
echo "=== n8n Assistant sandbox ==="
env_of_n8n="$(tr '\0' '\n' < "/proc/$(cat /tmp/n8n.pid)/environ")"
grep -qx 'N8N_INSTANCE_AI_SANDBOX_ENABLED=true' <<< "$env_of_n8n" \
    || { echo "n8n started without N8N_INSTANCE_AI_SANDBOX_ENABLED=true"; exit 1; }
grep -qx "N8N_SANDBOX_SERVICE_URL=http://127.0.0.1:${N8N_SANDBOX_PORT}" <<< "$env_of_n8n" \
    || { echo "n8n started without N8N_SANDBOX_SERVICE_URL"; exit 1; }

ok=0
for _ in $(seq 300); do
    if curl -fsS "http://127.0.0.1:${N8N_SANDBOX_PORT}/healthz" >/dev/null 2>&1; then
        ok=1
        break
    fi
    sleep 2
done
if [[ "$ok" != 1 ]]; then
    echo "sandbox service did not answer /healthz"
    cat /tmp/n8n-sandbox.log 2>/dev/null || true
    exit 1
fi

result="$(cd /usr/local/lib/node_modules/n8n && node -e '
const { SandboxClient } = require("@n8n/sandbox-client");
const env = Object.fromEntries(require("fs")
    .readFileSync(process.env.HOME + "/.n8n/sandbox/n8n.env", "utf8")
    .split("\n").filter(Boolean).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));
(async () => {
    const client = new SandboxClient({ baseUrl: env.N8N_SANDBOX_SERVICE_URL, apiKey: env.N8N_SANDBOX_SERVICE_API_KEY });
    // The runner registers after the API is healthy and its own Docker is up.
    let box;
    for (let i = 0; ; i++) {
        try { box = await client.createSandbox({ ephemeral: true }); break; }
        catch (e) {
            if (i >= 120 || !/no sandbox runners/.test(String(e))) throw e;
            await new Promise((r) => setTimeout(r, 5000));
        }
    }
    const out = await client.exec(box.id, { command: "echo sandbox=$((6 * 7))", timeoutMs: 120000 });
    await client.deleteSandbox(box.id).catch(() => {});
    console.log(out.stdout.trim());
})().catch((e) => { console.error(e); process.exit(1); });
' 2>&1)" || true
echo "$result"
if [[ "$result" != *"sandbox=42"* ]]; then
    echo "sandbox exec should print sandbox=42"
    tail -30 /tmp/n8n-sandbox.log 2>/dev/null || true
    docker compose -f "$HOME/.n8n/sandbox/compose.yml" ps 2>&1 || true
    docker compose -f "$HOME/.n8n/sandbox/compose.yml" logs --tail 40 sandbox-runner-1 2>&1 || true
    exit 1
fi

# +search: n8n must carry the SearXNG URL, and SearXNG must answer its JSON
# API. Only the shape is checked; live engines can rate-limit or be down.
echo "=== n8n Assistant web search ==="
grep -qx "N8N_INSTANCE_AI_SEARXNG_URL=http://127.0.0.1:${N8N_SEARXNG_PORT}" <<< "$env_of_n8n" \
    || { echo "n8n started without N8N_INSTANCE_AI_SEARXNG_URL"; exit 1; }
ok=0
for _ in $(seq 150); do
    if curl -fsS "http://127.0.0.1:${N8N_SEARXNG_PORT}/healthz" >/dev/null 2>&1; then
        ok=1
        break
    fi
    sleep 2
done
if [[ "$ok" != 1 ]]; then
    echo "SearXNG did not answer /healthz"
    cat /tmp/n8n-search.log 2>/dev/null || true
    exit 1
fi
search="$(curl -fsS "http://127.0.0.1:${N8N_SEARXNG_PORT}/search?q=n8n&format=json" \
    | python3 -c 'import json, sys; d = json.load(sys.stdin); print("query=%s results=%d" % (d["query"], len(d["results"])))' 2>&1)" || true
echo "search: $search"
[[ "$search" == "query=n8n results="* ]] || { echo "SearXNG should answer format=json"; exit 1; }
echo "ok"
