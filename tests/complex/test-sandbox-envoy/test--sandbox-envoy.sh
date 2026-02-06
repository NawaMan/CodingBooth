#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Complex test: --sandboxed with custom envoy.yaml
# Verifies allowlisted domain is reachable and non-allowlisted is blocked.

set -euo pipefail

source ../../common--source.sh

# ---- Config -------------------------------------------------------------------
CB_SCRIPT="${CB_SCRIPT:-../../../codingbooth}"
if command -v readlink >/dev/null 2>&1; then
  CB_SCRIPT="$(readlink -f "$CB_SCRIPT")"
else
  CB_SCRIPT="$(cd "$(dirname "$CB_SCRIPT")" && pwd -P)/$(basename "$CB_SCRIPT")"
fi

RUN_ID="$(date +%s)-$$"
CONTAINER_NAME="cb-test-sandbox-envoy-${RUN_ID}"
IMAGE_NAME="${CB_IMAGE_NAME:-nawaman/codingbooth:base-latest}"

# ---- Preconditions ------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found in PATH"
  exit 1
fi

if [[ ! -x "$CB_SCRIPT" ]]; then
  echo "ERROR: CB_SCRIPT not executable or not found: $CB_SCRIPT" >&2
  exit 1
fi

# ---- Test booth -----------------------------------------------------------
TMPDIR="$(mktemp -d "$HOME/cb-test-sandbox-envoy.XXXXXX")"
cleanup() {
  rm -rf "$TMPDIR" || true
}
trap cleanup EXIT

pushd "$TMPDIR" >/dev/null

mkdir -p .booth/sandbox
cat > .booth/sandbox/envoy.yaml <<'EOF'
static_resources:
  listeners:
  - name: egress_proxy
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 15001
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: egress_http
          codec_type: AUTO
          route_config:
            name: proxy_routes
            virtual_hosts:
            - name: forward_proxy
              domains: ["*"]
              routes:
              - match:
                  connect_matcher: {}
                route:
                  cluster: dynamic_forward_proxy_cluster
                  upgrade_configs:
                  - upgrade_type: CONNECT
                    connect_config: {}
              - match:
                  prefix: "/"
                route:
                  cluster: dynamic_forward_proxy_cluster
          http_filters:
          - name: envoy.filters.http.rbac
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.rbac.v3.RBAC
              rules:
                action: ALLOW
                policies:
                  allow_pypi:
                    permissions:
                    - header:
                        name: ":authority"
                        string_match:
                          safe_regex:
                            google_re2: {}
                            regex: "(^|.*\\.)pypi\\.org(:[0-9]+)?$"
                    principals:
                    - any: true
          - name: envoy.filters.http.dynamic_forward_proxy
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.dynamic_forward_proxy.v3.FilterConfig
              dns_cache_config:
                name: dynamic_forward_proxy_cache_config
                dns_lookup_family: V4_ONLY
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router
          upgrade_configs:
          - upgrade_type: CONNECT

  clusters:
  - name: dynamic_forward_proxy_cluster
    connect_timeout: 5s
    lb_policy: CLUSTER_PROVIDED
    cluster_type:
      name: envoy.clusters.dynamic_forward_proxy
      typed_config:
        "@type": type.googleapis.com/envoy.extensions.clusters.dynamic_forward_proxy.v3.ClusterConfig
        dns_cache_config:
          name: dynamic_forward_proxy_cache_config
          dns_lookup_family: V4_ONLY

admin:
  address:
    socket_address:
      address: 127.0.0.1
      port_value: 9901
EOF

run_cb() {
  echo -e "${COLOR_BOOTH:-}> codingbooth --sandboxed --image $IMAGE_NAME --name $CONTAINER_NAME -- $*${COLOR_RESET:-}" >&2
  "$CB_SCRIPT" --sandboxed --image "$IMAGE_NAME" --name "$CONTAINER_NAME" -- "$@"
}

# ---- Assertions ---------------------------------------------------------------
total_checks=0
failed_checks=0
failed_msgs=()

pass() {
  total_checks=$((total_checks + 1))
  print_test_result "true" "$0" "$total_checks" "$*"
}

fail() {
  total_checks=$((total_checks + 1))
  failed_checks=$((failed_checks + 1))
  failed_msgs+=("$*")
  print_test_result "false" "$0" "$total_checks" "$*"
}

http_code() {
  run_cb "curl -s -o /dev/null -w \"%{http_code}\" --max-time 8 $1" | tr -d '\r'
}

code="$(http_code "https://pypi.org")"
if [[ "$code" == "000" || "$code" == "403" ]]; then
  fail "allowlisted domain blocked (pypi.org) -> HTTP $code"
else
  pass "allowlisted domain reachable (pypi.org) -> HTTP $code"
fi

code="$(http_code "https://example.com")"
if [[ "$code" == "000" || "$code" == "403" ]]; then
  pass "non-allowlisted domain blocked (example.com) -> HTTP $code"
else
  fail "non-allowlisted domain reachable (example.com) -> HTTP $code"
fi

popd >/dev/null

# ---- Summary ------------------------------------------------------------------
if (( failed_checks == 0 )); then
  echo "✅ All $total_checks checks passed."
  exit 0
else
  echo "❌ $failed_checks out of $total_checks checks failed."
  echo "Failed checks:"
  for msg in "${failed_msgs[@]}"; do
    echo "  - $msg"
  done
  exit 1
fi
