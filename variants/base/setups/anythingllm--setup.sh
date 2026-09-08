#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <tag>] [--port <port>]
  $0 [PORT]

Arguments:
  --version TAG  Image tag that was copied in (default: 1.16.1; display only)
  --port PORT    Port for the AnythingLLM web UI (default: 3001)

Examples:
  $0
  $0 --port 13001
  $0 --version 1.16.1 --port 3001

Prerequisites:
- AnythingLLM must be pre-installed at /opt/anythingllm
  (typically via COPY --from=mintplexlabs/anythingllm:<tag> /app /opt/anythingllm)

Notes:
- Creates a starter script at /usr/local/bin/start-anythingllm
- The server is NOT started during build; add the autostart extension
- Workspaces, documents, and the SQLite DB live in ~/.anythingllm
  (STORAGE_DIR, default ~/.anythingllm; +persist bind-mounts it)
- AUTH_TOKEN is the single-user password. Empty/unset = no login
  (+passwordless). JWT_SECRET is set when a password is enabled.
- start-anythingllm sets SERVER_PORT and ANYTHING_LLM_RUNTIME=docker
  (filesystem agent is hidden unless RUNTIME is docker)
- Pair with ollama+autostart and point the UI at http://127.0.0.1:11434
- Host LM Studio: http://host.docker.internal:1234/v1 (not localhost)
- AnythingLLM web UI is accessible at http://localhost:<PORT>
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
VERSION="1.16.1"
ANYTHINGLLM_PORT="3001"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; VERSION="${1:-1.16.1}"; shift ;;
    --port)    shift; ANYTHINGLLM_PORT="${1:-3001}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        ANYTHINGLLM_PORT="$1"; shift
      else
        echo "❌ Unknown arg: $1" >&2; usage; exit 2
      fi
      ;;
  esac
done
VERSION="${VERSION#v}"

ANYTHINGLLM_DIR="/opt/anythingllm"
PROFILE_FILE="/etc/profile.d/70-cb-anythingllm--profile.sh"
STARTUP_FILE="/usr/share/startup.d/70-cb-anythingllm--startup.sh"
STARTER_FILE="/usr/local/bin/start-anythingllm"

# ---- verify AnythingLLM is present ----
if [[ ! -f "$ANYTHINGLLM_DIR/server/index.js" ]]; then
  echo "❌ AnythingLLM not found at $ANYTHINGLLM_DIR"
  echo "   Use COPY --from=mintplexlabs/anythingllm:<version> /app /opt/anythingllm"
  exit 1
fi

# ---- Node.js 18 (native addons in the official image are built for it) ----
need_node=1
if command -v node >/dev/null 2>&1; then
  NODE_MAJOR="$(node -v | sed 's/^v//' | cut -d. -f1)"
  # Official image native addons are built for Node 18. Catalog nodejs now
  # defaults to 24 (current LTS); a different major is an ABI mismatch.
  if [[ "${NODE_MAJOR:-0}" -eq 18 ]]; then
    echo "• Node.js already installed: $(node --version)"
    need_node=0
  else
    echo "• Node.js $(node --version) is not 18 (AnythingLLM native addons need 18)"
  fi
fi
if [[ "$need_node" -eq 1 ]]; then
  SETUPS_DIR="/opt/codingbooth/setups"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -x "$SETUPS_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js 18 ..."
    "$SETUPS_DIR/nodejs--setup.sh" 18
  elif [[ -x "$SCRIPT_DIR/nodejs--setup.sh" ]]; then
    echo "• Installing Node.js 18 ..."
    "$SCRIPT_DIR/nodejs--setup.sh" 18
  else
    echo "❌ nodejs--setup.sh not found (need Node.js 18)"
    exit 1
  fi
fi

# ---- runtime libraries ----
export DEBIAN_FRONTEND=noninteractive
echo "• Installing OpenSSL (Prisma) ..."
apt-get update
apt-get install -y --no-install-recommends openssl ca-certificates

# Puppeteer / ffmpeg only pay off on a real image (prisma schema present).
# A fixture used by tests has server/index.js and nothing else.
if [[ -f "$ANYTHINGLLM_DIR/server/prisma/schema.prisma" ]]; then
  echo "• Installing ffmpeg and Chromium runtime libraries ..."
  apt-get install -y --no-install-recommends \
    ffmpeg \
    fonts-liberation \
    libasound2t64 \
    libatk1.0-0 \
    libcups2 \
    libgbm1 \
    libnss3 \
    libpango-1.0-0 \
    libcairo2 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libxkbcommon0 || \
    echo "⚠️  Some Chromium/ffmpeg packages were unavailable — URL scraping may fail."
fi
rm -rf /var/lib/apt/lists/*

# Readable by the booth user; prisma generate may write under /opt/anythingllm.
chmod -R a+rX "$ANYTHINGLLM_DIR"
if id coder >/dev/null 2>&1; then
  chown -R coder:coder "$ANYTHINGLLM_DIR" || true
fi

# ---- SPA basename: host `/` and globe pane `/proxy/<port>` both work ----
# AnythingLLM's createBrowserRouter defaults to basename "/". The booth globe
# pane loads the app at /proxy/<port>/, which is not a route, so React 404s.
# Detect that prefix at runtime and pass it as basename. Host tabs stay "/".
if [[ -f "$ANYTHINGLLM_DIR/server/public/index.js" ]]; then
  echo "• Patching AnythingLLM SPA basename for the booth globe pane ..."
  node - "$ANYTHINGLLM_DIR" <<'PATCH'
const fs = require("fs");
const path = require("path");
const root = process.argv[2];
const snippet =
  '<script>window.__CB_BASENAME__=(function(){var p=String(location.pathname||"").split("/");if(p[1]==="proxy"&&/^[0-9]+$/.test(p[2]||""))return "/proxy/"+p[2];return "/";})();(function(){var B=window.__CB_BASENAME__;if(!B||B==="/")return;function prefix(u){if(typeof u!=="string"||u.charAt(0)!=="/"||u.charAt(1)==="/")return u;if(u.indexOf(B)===0||u.indexOf("/proxy/")===0)return u;if(u.indexOf("/booth")===0||u.indexOf("/s1")===0||u.indexOf("/s2")===0||u.indexOf("/s3")===0||u.indexOf("/s4")===0)return u;if(u.indexOf("/__booth")===0||u.indexOf("/booth-messages")===0)return u;return (B.charAt(B.length-1)==="/" ? B.slice(0,-1) : B)+u;}try{var proto=Object.getPrototypeOf(window.location);var desc=Object.getOwnPropertyDescriptor(proto,"href")||Object.getOwnPropertyDescriptor(Location.prototype,"href");if(desc&&desc.set){Object.defineProperty(proto,"href",{configurable:true,enumerable:true,get:desc.get,set:function(v){desc.set.call(this,prefix(v));}});}}catch(e){}try{var asg=window.location.assign.bind(window.location);var rep=window.location.replace.bind(window.location);window.location.assign=function(u){return asg(prefix(u));};window.location.replace=function(u){return rep(prefix(u));};}catch(e){}document.addEventListener("click",function(e){var el=e.target&&e.target.closest&&e.target.closest("a");if(!el)return;var h=el.getAttribute("href");if(!h)return;var p=prefix(h);if(p!==h)el.setAttribute("href",p);},true);})();</script>\n';
const scriptTag = '<script type="module" crossorigin src="/index.js"></script>';
const snippetRe =
  /<script>window\.__CB_BASENAME__=[\s\S]*?<\/script>\n?/;

function skipString(src, index) {
  const quote = src[index];
  index += 1;
  while (index < src.length) {
    if (src[index] === "\\") {
      index += 2;
      continue;
    }
    if (src[index] === quote) return index + 1;
    index += 1;
  }
  return index;
}

function matchBracket(src, index) {
  const open = src[index];
  const close = open === "[" ? "]" : open === "{" ? "}" : ")";
  let depth = 1;
  index += 1;
  while (index < src.length && depth > 0) {
    const char = src[index];
    if (char === '"' || char === "'" || char === "`") {
      index = skipString(src, index);
      continue;
    }
    if (char === open) depth += 1;
    else if (char === close) depth -= 1;
    if (depth > 0) index += 1;
  }
  return index;
}

function patchBundle(file) {
  let js = fs.readFileSync(file, "utf8");
  const notes = [];
  if (!js.includes('basename:(typeof window!="undefined"&&window.__CB_BASENAME__)')) {
    const match = js.match(/=\w+\(\[\{path:"\/",element:/);
    if (!match) throw new Error("createBrowserRouter call not found in " + file);
    const paren = js.indexOf("(", match.index);
    if (js[paren + 1] !== "[") throw new Error("router first arg is not an array");
    const closeArray = matchBracket(js, paren + 1);
    const closeCall = closeArray + 1;
    if (js[closeCall] !== ")") throw new Error("router call close not found");
    const insert =
      ',{basename:(typeof window!="undefined"&&window.__CB_BASENAME__)||"/"}';
    js = js.slice(0, closeCall) + insert + js.slice(closeCall);
    notes.push("basename");
  }
  const withApi = js.replace(
    /=\{\}\.VITE_API_BASE\|\|"\/api"/,
    '=(typeof window!="undefined"&&window.__CB_BASENAME__&&window.__CB_BASENAME__!=="/"?window.__CB_BASENAME__+"/api":"/api")'
  );
  if (withApi !== js) {
    js = withApi;
    notes.push("api-base");
  }
  const withHome = js.replace(
    /window\.location\.href=\w+\.home\(\)/g,
    'window.location.href=(window.__CB_BASENAME__&&window.__CB_BASENAME__!=="/"?window.__CB_BASENAME__+"/":"/")'
  );
  if (withHome !== js) {
    js = withHome;
    notes.push("home-nav");
  }
  const withWs = js.replace(
    'E==="/api"?`${e}//${window.location.host}`:`${e}//${new URL({}.VITE_API_BASE).host}`',
    '`${e}//${window.location.host}`'
  );
  if (withWs !== js) {
    js = withWs;
    notes.push("ws-host");
  }
  fs.writeFileSync(file, js);
  return notes.length ? "bundle patched (" + notes.join(", ") + ")" : "bundle already patched";
}

function patchHtml(file) {
  if (!fs.existsSync(file)) return path.basename(file) + " missing";
  let html = fs.readFileSync(file, "utf8");
  if (snippetRe.test(html)) {
    fs.writeFileSync(file, html.replace(snippetRe, snippet));
    return path.basename(file) + " snippet refreshed";
  }
  if (!html.includes(scriptTag)) throw new Error("index.js script tag not found in " + file);
  fs.writeFileSync(file, html.replace(scriptTag, snippet + "            " + scriptTag));
  return path.basename(file) + " patched";
}

console.log("  " + patchBundle(path.join(root, "server/public/index.js")));
console.log("  " + patchHtml(path.join(root, "server/utils/boot/MetaGenerator.js")));
console.log("  " + patchHtml(path.join(root, "server/public/_index.html")));
PATCH
fi

# ---- profile ----
export BAKED_PORT="$ANYTHINGLLM_PORT"
export BAKED_VERSION="$VERSION"
envsubst '$BAKED_PORT $BAKED_VERSION' <<'EOF' > "$PROFILE_FILE"
# AnythingLLM environment
export ANYTHINGLLM_HOME="/opt/anythingllm"
export ANYTHINGLLM_PORT="${ANYTHINGLLM_PORT:-$BAKED_PORT}"
export ANYTHINGLLM_VERSION="${ANYTHINGLLM_VERSION:-$BAKED_VERSION}"

anythingllm--info() {
  echo "AnythingLLM"
  echo "  Home:    /opt/anythingllm"
  echo "  Version: ${ANYTHINGLLM_VERSION}"
  echo "  Port:    ${ANYTHINGLLM_PORT}"
  echo "  Data:    ${STORAGE_DIR:-$HOME/.anythingllm}"
  echo "  Starter: /usr/local/bin/start-anythingllm"
  echo "  URL:     http://localhost:${ANYTHINGLLM_PORT}"
}
EOF
chmod 644 "$PROFILE_FILE"

# ---- startup: data dir for workspaces / SQLite / documents ----
mkdir -p "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'STARTUP'
#!/usr/bin/env bash
# AnythingLLM startup — data dir, and keep globe-pane /login on the app
set -euo pipefail
mkdir -p "${STORAGE_DIR:-$HOME/.anythingllm}"

# start-ttyd-split writes this from the base image. Until that image has the
# pane-referer /login redirect, patch it here so AnythingLLM's
# window.location="/login" does not nest the booth console in the iframe.
NGINX_CONF="/tmp/ttyd-split.nginx.conf"
if [[ -f "$NGINX_CONF" ]]; then
  node - "$NGINX_CONF" <<'JS' || true
const fs = require("fs");
const file = process.argv[2];
let text = fs.readFileSync(file, "utf8");
let changed = false;
const loginNeedle = "        location = /login {\n";
const loginInsert = loginNeedle
  + "            if ($cb_proxy_ref != \"\") {\n"
  + "                return 302 /proxy/$cb_proxy_ref/login$is_args$args;\n"
  + "            }\n";
if (text.includes(loginNeedle) && !text.includes("proxy/$cb_proxy_ref/login")) {
  text = text.replace(loginNeedle, loginInsert);
  changed = true;
}
const rootNeedle = "        location / {\n            if ($booth_auth_ok = 0) {\n                return 302 /login;\n            }\n            try_files $uri $uri/ @cb_root;\n        }\n";
const rootInsert = "        location = / {\n            if ($booth_auth_ok = 0) {\n                return 302 /login;\n            }\n            if ($cb_proxy_ref != \"\") {\n                return 302 /proxy/$cb_proxy_ref/;\n            }\n            rewrite ^ /index.html last;\n        }\n\n" + rootNeedle;
if (text.includes(rootNeedle) && !text.includes("location = / {")) {
  text = text.replace(rootNeedle, rootInsert);
  changed = true;
}
const apiNeedle = "        location ^~ /v1/ {\n";
const apiBlock = [
  "        location ^~ /api/ {",
  "            if ($booth_auth_ok = 0) {",
  "                return 302 /login;",
  "            }",
  "            set $cb_up $cookie_cb_proxy_port;",
  "            if ($cb_up = \"\") {",
  "                set $cb_up $cb_proxy_ref;",
  "            }",
  "            if ($cb_up = \"\") {",
  "                return 404;",
  "            }",
  "            proxy_pass http://127.0.0.1:$cb_up;",
  "            proxy_http_version 1.1;",
  "            proxy_set_header Upgrade $http_upgrade;",
  "            proxy_set_header Connection $connection_upgrade;",
  "            proxy_set_header Host $host;",
  "            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;",
  "            proxy_set_header Accept-Encoding \"\";",
  "            proxy_read_timeout 24h;",
  "            proxy_buffering off;",
  "            proxy_hide_header X-Frame-Options;",
  "            proxy_hide_header Content-Security-Policy;",
  "        }",
  "",
  "",
].join("\n");
if (text.includes(apiNeedle) && !text.includes("location ^~ /api/")) {
  text = text.replace(apiNeedle, apiBlock + apiNeedle);
  changed = true;
}
if (changed) fs.writeFileSync(file, text);
JS
  nginx -t -c "$NGINX_CONF" >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1 || true
fi
STARTUP
chmod 755 "$STARTUP_FILE"

# ---- starter ----
export BAKED_PORT="$ANYTHINGLLM_PORT"
envsubst '$BAKED_PORT' <<'EOF' > "$STARTER_FILE"
#!/usr/bin/env bash
set -euo pipefail

PORT="${1:-${ANYTHINGLLM_PORT:-$BAKED_PORT}}"
APP="/opt/anythingllm"
STORAGE_DIR="${STORAGE_DIR:-$HOME/.anythingllm}"

export SERVER_PORT="$PORT"
export STORAGE_DIR
export NODE_ENV="${NODE_ENV:-production}"
# Official image sets this; filesystem and create-files agent skills
# are hidden unless it is "docker".
export ANYTHING_LLM_RUNTIME="${ANYTHING_LLM_RUNTIME:-docker}"
export CHECKPOINT_DISABLE=1
# Document scraping uses Puppeteer; skip the Chromium sandbox so we do not
# need Docker's SYS_ADMIN capability inside the booth.
export ANYTHINGLLM_CHROMIUM_ARGS="${ANYTHINGLLM_CHROMIUM_ARGS:---no-sandbox,--disable-setuid-sandbox}"

mkdir -p "$STORAGE_DIR"

if [[ ! -f "$APP/server/index.js" ]]; then
  echo "❌ AnythingLLM not found at $APP/server/index.js" >&2
  exit 1
fi

echo "Starting AnythingLLM on http://localhost:$PORT ..."
echo "  storage: $STORAGE_DIR"

cd "$APP/server"
if [[ -f prisma/schema.prisma ]]; then
  npx prisma generate --schema=./prisma/schema.prisma
  npx prisma migrate deploy --schema=./prisma/schema.prisma
fi

if [[ -f "$APP/collector/index.js" ]]; then
  node "$APP/server/index.js" &
  node "$APP/collector/index.js" &
  wait -n
  exit $?
fi

exec node "$APP/server/index.js"
EOF
chmod 755 "$STARTER_FILE"

# ---- desktop icon (no-op off-desktop) ----
ICON="applications-internet"
for cand in \
  "$ANYTHINGLLM_DIR/server/public/favicon.png" \
  "$ANYTHINGLLM_DIR/server/public/favicon.ico" \
  "$ANYTHINGLLM_DIR/server/public/anything-llm.png"; do
  if [[ -f "$cand" ]]; then
    ICON="$cand"
    break
  fi
done

echo ""
cb-web-icon.sh --id anythingllm --name "AnythingLLM" --icon "$ICON" \
  --port-env ANYTHINGLLM_PORT --port "${ANYTHINGLLM_PORT}" \
  --path / --start start-anythingllm

echo "✅ AnythingLLM installed."
echo "   Location:  ${ANYTHINGLLM_DIR}"
echo "   Version:   ${VERSION}"
echo "   Port:      ${ANYTHINGLLM_PORT}"
echo "   Starter:   ${STARTER_FILE}"
echo ""
echo "ℹ️ Ready to use:"
cat <<READY
- Start the UI:     start-anythingllm
- Open:             http://localhost:${ANYTHINGLLM_PORT}
- Data directory:   ~/.anythingllm  (STORAGE_DIR)
- Password:         AUTH_TOKEN (empty = no login; +passwordless)
- Local models:     ollama+autostart → http://127.0.0.1:11434
- Host LM Studio:   http://host.docker.internal:1234/v1
- Persist data:     anythingllm+persist (binds ~/.anythingllm from .booth/cache)
- Project files:    anythingllm+project-fs (jail at ~/.anythingllm/anythingllm-fs/code)

- Params: ANYTHINGLLM_VERSION, ANYTHINGLLM_PORT, ANYTHINGLLM_HOST_PORT (+expose)
- The server does not start on its own — add +autostart, or run start-anythingllm.
- +expose publishes the port on the host.
- +passwordless skips the login password (AUTH_TOKEN empty).
- +project-fs is not persist: persist keeps AnythingLLM data; the project is already the host folder.
- See: https://docs.anythingllm.com/
READY
