#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}ℹ${NC} $1"; }

echo "=== Sandbox Envoy Policy Container Tests ==="

echo
info "Check proxy env vars are present"
[[ -n "${HTTP_PROXY:-}" ]] || fail "HTTP_PROXY is not set"
[[ -n "${HTTPS_PROXY:-}" ]] || fail "HTTPS_PROXY is not set"
pass "Proxy environment variables are set"

echo
info "Allowed domain via explicit proxy: pypi.org"
if curl -4 -I -sS --max-time 12 -x http://127.0.0.1:15001 https://pypi.org >/tmp/firewall-allow.out; then
    pass "pypi.org is reachable via sandbox proxy"
else
    fail "pypi.org should be reachable via sandbox proxy"
fi

echo
info "Blocked domain via explicit proxy: example.com"
if curl -4 -I -sS --max-time 12 -x http://127.0.0.1:15001 https://example.com >/tmp/firewall-blocked.out; then
    fail "example.com should be blocked by proxy policy"
else
    pass "example.com blocked by proxy policy (expected)"
fi

echo
info "Direct no-proxy bypass attempt should fail"
if HTTPS_PROXY= HTTP_PROXY= curl -4 -I -sS --max-time 8 https://google.com >/tmp/firewall-bypass.out; then
    fail "direct bypass should be blocked by firewall"
else
    pass "direct bypass blocked by firewall (expected)"
fi

echo
if [[ -n "${DOCKER_HOST:-}" ]]; then
    info "DinD mode checks"
    [[ "${DOCKER_HOST}" == "tcp://localhost:2375" ]] || fail "DOCKER_HOST should be tcp://localhost:2375 in DinD mode"
    pass "DOCKER_HOST is correctly configured for DinD reuse"

    if docker version >/tmp/firewall-dind-version.out 2>&1; then
        pass "docker command works against DinD daemon"
    else
        info "docker command did not complete in DinD mode (acceptable for this egress test)"
    fi
else
    info "Non-DinD mode checks"
    pass "DOCKER_HOST not set in non-DinD mode"
fi

echo
echo -e "${GREEN}=== All container tests passed! ===${NC}"
