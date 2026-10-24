#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Live check: every TLS client in each image must REFUSE the compromised eMudhra
# chains (Oct 2026). Connects to the incident's own test hosts, so it needs the
# network and depends on a third-party site staying up — which is why it is a
# manual test. tests/basic/test038--trust-store-distrust.sh is the offline guard.
#
# Usage: tests/manual/run-emudhra-live-manual-test.sh [image ...]
#   default: base, codeserver and notebook at this checkout's version.txt
#
# Per client and host: "rejected" (a certificate error) passes; "VULNERABLE"
# (it connected) fails; "inconclusive" (DNS, timeout, anything else) also fails,
# because it proves nothing.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(tr -d ' \t\n\r' < "$SCRIPT_DIR/../../version.txt")

if [[ $# -gt 0 ]]; then
  IMAGES=("$@")
else
  IMAGES=()
  for v in base codeserver notebook; do IMAGES+=("nawaman/codingbooth:${v}-${VERSION}"); done
fi

# Runs inside the image, as root, with no booth around it: only the clients.
read -r -d '' PROBE <<'PROBE'
HOSTS="dv-g3b-emudhra dv-g3b-aaa-emudhra dv-g3b-noct-emudhra dv-g3b-aaa-noct-emudhra"
report() { printf '  %-22s %-26s %s\n' "$1" "$2" "$3"; }
verdict() {  # <ok-to-connect exit/marker> — reads the client's output on stdin
  local out; out=$(cat)
  case "$out" in
    *CONNECTED*)                                                    echo VULNERABLE ;;
    *[Cc]ertificate*|*CERT*|*SSL*|*PKIX*|*certification*|*issuer*) echo rejected ;;
    *)                                                              echo "inconclusive: ${out:0:80}" ;;
  esac
}
NODE_JS='require("https").get(process.argv[1],()=>{console.log("CONNECTED");process.exit()}).on("error",e=>{console.log(e.code||e.message);process.exit()})'
for h in $HOSTS; do
  url="https://$h.we-have-a-problem.com/"
  out=$(curl -sS -o /dev/null --max-time 20 "$url" 2>&1 && echo CONNECTED); report curl "$h" "$(verdict <<<"$out")"
  if command -v python3 >/dev/null; then
    out=$(python3 -c 'import sys,urllib.request; urllib.request.urlopen(sys.argv[1], timeout=20); print("CONNECTED")' "$url" 2>&1 | tail -1)
    report "python ssl" "$h" "$(verdict <<<"$out")"
    if python3 -c 'import certifi' 2>/dev/null; then
      out=$(python3 -c 'import sys,ssl,certifi,urllib.request; urllib.request.urlopen(sys.argv[1], timeout=20, context=ssl.create_default_context(cafile=certifi.where())); print("CONNECTED")' "$url" 2>&1 | tail -1)
      report "python certifi" "$h" "$(verdict <<<"$out")"
    fi
    if python3 -m pip --version >/dev/null 2>&1; then
      # No such index: reaching it at all ("No matching distribution") means pip trusted it.
      out=$(python3 -m pip download --no-deps --no-cache-dir --retries 0 --timeout 20 -d /tmp/cb-probe \
              --index-url "${url}simple/" cb-probe-none 2>&1)
      [[ "$out" == *"No matching distribution"* && "$out" != *SSL* ]] && out=CONNECTED
      report pip "$h" "$(verdict <<<"$out")"
    fi
  fi
  if command -v node >/dev/null; then
    report "node $(node -v)" "$h" "$(verdict <<<"$(timeout 30 node -e "$NODE_JS" "$url" 2>&1)")"
  fi
  CS_NODE=/usr/lib/code-server/lib/node
  if [[ -x "$CS_NODE" ]]; then
    # NODE_OPTIONS as start-codeserver sets it, taken from the launcher itself.
    opts=$(grep -o -- '--use-openssl-ca' /usr/local/bin/start-codeserver 2>/dev/null | head -1)
    report "code-server node" "$h" "$(verdict <<<"$(NODE_OPTIONS="$opts" timeout 30 "$CS_NODE" -e "$NODE_JS" "$url" 2>&1)")"
  fi
done
PROBE

status=0
for img in "${IMAGES[@]}"; do
  echo "== $img"
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    echo "  (image not present locally — skipped)"
    continue
  fi
  out=$(docker run --rm -u root --entrypoint bash "$img" -c "$PROBE" 2>&1)
  echo "$out"
  grep -qE 'VULNERABLE|inconclusive' <<<"$out" && status=1
done

echo ""
if [[ $status -eq 0 ]]; then
  echo "✅ Every client refused every compromised eMudhra chain."
else
  echo "❌ Some client connected, or could not be judged — see VULNERABLE / inconclusive above."
fi
exit $status
