#!/bin/bash
# Package-download caches: each extension emits a machine-wide named volume
# and the env pin that makes the tool use that one path.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

config="$prj/.booth/config.toml"

assert_has() {
    local label="$1" needle="$2"
    TEST_COUNT=$((TEST_COUNT + 1))
    local pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
    if grep -qF "$needle" "$config"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
        echo "  EXPECTED in $config: $needle"
    fi
}

run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select 'go+mod-cache'
assert_has "go+mod-cache mounts the module cache" "booth-cache-gomod:/home/coder/go/pkg/mod"
assert_has "go+mod-cache mounts the build cache" "booth-cache-gobuild:/home/coder/.cache/go-build"
assert_has "go+mod-cache pins GOMODCACHE" "GOMODCACHE=/home/coder/go/pkg/mod"
assert_has "go+mod-cache pins GOCACHE" "GOCACHE=/home/coder/.cache/go-build"

run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select 'nodejs+npm-cache+pnpm-cache'
assert_has "nodejs+npm-cache mounts the npm cache" "booth-cache-npm:/home/coder/.npm"
assert_has "nodejs+npm-cache pins npm_config_cache" "npm_config_cache=/home/coder/.npm"
assert_has "nodejs+pnpm-cache mounts the pnpm store" "booth-cache-pnpm:/home/coder/.local/share/pnpm/store"
assert_has "nodejs+pnpm-cache pins pnpm_config_store_dir" "pnpm_config_store_dir=/home/coder/.local/share/pnpm/store"

run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select 'python+pip-cache+uv-cache'
assert_has "python+pip-cache mounts /opt/pip-cache" "booth-cache-pip:/opt/pip-cache"
assert_has "python+pip-cache pins PIP_CACHE_DIR" "PIP_CACHE_DIR=/opt/pip-cache"
assert_has "python+uv-cache mounts the uv cache" "booth-cache-uv:/home/coder/.cache/uv"
assert_has "python+uv-cache pins UV_CACHE_DIR" "UV_CACHE_DIR=/home/coder/.cache/uv"
TEST_COUNT=$((TEST_COUNT + 1))
echo -n "Test ${TEST_COUNT}: python+pip-cache writes owner-permission.yaml ..."
if grep -qF 'path: "/opt/pip-cache"' "$prj/.booth/owner-permission.yaml" \
   && grep -qF 'mode: "1777"' "$prj/.booth/owner-permission.yaml"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("${test_label}: Test ${TEST_COUNT}: owner-permission.yaml")
    echo -e "\033[31mFAILED\033[0m"
fi

run rm -Rf $prj ; mkdir -p $prj
run booth config $prj --no-tui --select 'java+gradle-cache'
assert_has "java+gradle-cache mounts modules-2" "booth-cache-gradle:/home/coder/.gradle/caches/modules-2"

finally
