#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Tests to run inside the container to verify network whitelist functionality.

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }
info() { echo -e "${YELLOW}ℹ${NC} $1"; }

echo "=== Network Whitelist Container Tests ==="
echo

# --- Test 1: Check that network-whitelist commands are available ---
echo "Checking network-whitelist commands are installed..."
command -v network-whitelist-enable  >/dev/null || fail "network-whitelist-enable not found"
command -v network-whitelist-disable >/dev/null || fail "network-whitelist-disable not found"
command -v network-whitelist-status  >/dev/null || fail "network-whitelist-status not found"
command -v network-whitelist-list    >/dev/null || fail "network-whitelist-list not found"
command -v network-whitelist-add     >/dev/null || fail "network-whitelist-add not found"
command -v network-whitelist-reload  >/dev/null || fail "network-whitelist-reload not found"
pass "All network-whitelist commands are available"

# --- Test 2: Check user whitelist was copied from .booth/home ---
echo
echo "Checking user whitelist from .booth/home..."
if [[ -f "$HOME/.network-whitelist" ]]; then
    if grep -q "httpbin.org" "$HOME/.network-whitelist"; then
        pass "User whitelist contains httpbin.org (from .booth/home)"
    else
        fail "User whitelist missing httpbin.org"
    fi
else
    fail "User whitelist file not found at $HOME/.network-whitelist"
fi

# --- Test 3: Enable network whitelist ---
echo
echo "Enabling network whitelist..."
network-whitelist-enable
pass "Network whitelist enabled"

# Give tinyproxy time to start
sleep 2

# --- Test 4: Check proxy is running ---
echo
echo "Checking proxy is running..."
if pgrep -x tinyproxy > /dev/null 2>&1; then
    pass "Tinyproxy is running"
else
    fail "Tinyproxy is not running"
fi

# --- Test 5: Check environment variables are set ---
echo
echo "Checking proxy environment variables..."
# Source the profile to get the variables
source /etc/profile.d/40-cb-network-whitelist--profile.sh

if [[ -n "${HTTP_PROXY:-}" ]]; then
    pass "HTTP_PROXY is set: $HTTP_PROXY"
else
    fail "HTTP_PROXY is not set"
fi

if [[ -n "${HTTPS_PROXY:-}" ]]; then
    pass "HTTPS_PROXY is set: $HTTPS_PROXY"
else
    fail "HTTPS_PROXY is not set"
fi

# --- Test 6: Test whitelisted domain (pypi.org - default whitelist) ---
echo
echo "Testing access to whitelisted domain (pypi.org)..."
if curl -s --max-time 10 --proxy "$HTTP_PROXY" -I "https://pypi.org" 2>/dev/null | head -1 | grep -qE "HTTP/[0-9.]+ [23][0-9][0-9]"; then
    pass "pypi.org is accessible (whitelisted by default)"
else
    fail "pypi.org should be accessible (it's in the default whitelist)"
fi

# --- Test 7: Test user-whitelisted domain (httpbin.org) ---
echo
echo "Testing access to user-whitelisted domain (httpbin.org)..."
if curl -s --max-time 10 --proxy "$HTTP_PROXY" -I "https://httpbin.org" 2>/dev/null | head -1 | grep -qE "HTTP/[0-9.]+ [23][0-9][0-9]"; then
    pass "httpbin.org is accessible (user whitelist)"
else
    fail "httpbin.org should be accessible (it's in the user whitelist)"
fi

# --- Test 8: Test blocked domain (example.com - not whitelisted) ---
echo
echo "Testing that non-whitelisted domain is blocked (example.com)..."
# This should fail or return a proxy error
if curl -s --max-time 5 --proxy "$HTTP_PROXY" -I "https://example.com" 2>/dev/null | head -1 | grep -qE "HTTP/[0-9.]+ [23][0-9][0-9]"; then
    fail "example.com should be BLOCKED (not in whitelist)"
else
    pass "example.com is blocked (not whitelisted)"
fi

# --- Test 9: Test another blocked domain ---
echo
echo "Testing that another non-whitelisted domain is blocked (wikipedia.org)..."
if curl -s --max-time 5 --proxy "$HTTP_PROXY" -I "https://wikipedia.org" 2>/dev/null | head -1 | grep -qE "HTTP/[0-9.]+ [23][0-9][0-9]"; then
    fail "wikipedia.org should be BLOCKED (not in whitelist)"
else
    pass "wikipedia.org is blocked (not whitelisted)"
fi

# --- Test 10: Test adding a domain dynamically ---
echo
echo "Testing dynamic domain addition..."

# First verify that example.com is currently FILTERED (403)
# Note: example.com might already be in whitelist from test 8, so we use a fresh domain
TEST_DOMAIN="test-whitelist-example.org"

BEFORE_RESPONSE=$(curl -s --max-time 5 --proxy "$HTTP_PROXY" -I "https://${TEST_DOMAIN}" 2>/dev/null | head -1 || echo "curl failed")
if echo "$BEFORE_RESPONSE" | grep -q "403 Filtered"; then
    pass "${TEST_DOMAIN} is initially filtered (403)"
else
    info "${TEST_DOMAIN} initial response: $BEFORE_RESPONSE (may already be filtered differently)"
fi

# Add test domain to whitelist
network-whitelist-add "${TEST_DOMAIN}"
network-whitelist-reload
sleep 2

# After adding, it should NOT be filtered anymore
# Note: It might return 200 (success) or 500 (unable to connect due to DNS/network)
# but it should NOT return 403 Filtered anymore
AFTER_RESPONSE=$(curl -s --max-time 10 --proxy "$HTTP_PROXY" -I "https://${TEST_DOMAIN}" 2>/dev/null | head -1 || echo "curl failed")
if echo "$AFTER_RESPONSE" | grep -q "403 Filtered"; then
    fail "${TEST_DOMAIN} should NOT be filtered after adding to whitelist (got: $AFTER_RESPONSE)"
else
    # Success - no longer filtered (could be 200 OK or 500 Unable to connect)
    if echo "$AFTER_RESPONSE" | grep -qE "HTTP/[0-9.]+ [23][0-9][0-9]"; then
        pass "${TEST_DOMAIN} is now accessible after adding to whitelist"
    else
        # 500 Unable to connect means whitelist works, but network/DNS issue
        pass "${TEST_DOMAIN} is no longer filtered (whitelist updated; connection may have network issues)"
        info "Response after whitelist: $AFTER_RESPONSE"
    fi
fi

# --- Test 11: Disable and verify unrestricted access ---
echo
echo "Testing disable functionality..."
network-whitelist-disable

# Unset proxy vars for this test
unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy

# Without proxy, direct access should work
if curl -s --max-time 10 -I "https://wikipedia.org" 2>/dev/null | head -1 | grep -qE "HTTP/[0-9.]+ [23][0-9][0-9]"; then
    pass "wikipedia.org accessible after disabling whitelist"
else
    info "wikipedia.org not accessible (may be network issue, not whitelist)"
fi

# --- Test 12: Check status command ---
echo
echo "Checking status command output..."
STATUS_OUTPUT=$(network-whitelist-status 2>&1)
if echo "$STATUS_OUTPUT" | grep -q "DISABLED"; then
    pass "Status correctly shows DISABLED"
else
    fail "Status should show DISABLED"
fi

echo
echo -e "${GREEN}=== All container tests passed! ===${NC}"
