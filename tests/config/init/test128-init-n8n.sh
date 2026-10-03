#!/bin/bash
# n8n: version and port pins, expose, autostart, persist. Node comes along.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"

check() {
    local label="$1"; shift
    TEST_COUNT=$((TEST_COUNT + 1))
    local pad=$(printf '%*s' $((64 - ${#label} - 1)) '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label} ${pad} "
    if "$@"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

line_of() { grep -n "^$1" "$boothfile" | head -1 | cut -d: -f1; }
node_before_n8n() {
    local n e
    n="$(line_of 'setup nodejs ')"; e="$(line_of 'setup n8n ')"
    [[ -n "$n" && -n "$e" && "$n" -lt "$e" ]]
}

# --- bare n8n: pinned default, nodejs comes along ----------------------------
run booth config $prj --no-tui --select 'n8n'
assert-line "$boothfile" "setup n8n" " --version \${N8N_VERSION} --port \${N8N_PORT}" "n8n wires version and port"
assert-line "$boothfile" "arg N8N_VERSION=" "2.41.5" "N8N_VERSION defaults to 2.41.5"
assert-line "$boothfile" "arg N8N_PORT=" "21200" "N8N_PORT defaults to 21200"
assert-line "$boothfile" "setup nodejs" " \${NODE_VERSION}" "n8n pulls in the nodejs template"
check "setup nodejs runs before setup n8n" node_before_n8n

# --- version + port pin ------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n:2.40.0,5678'
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg N8N_VERSION=" "2.40.0" "n8n:2.40.0 pins N8N_VERSION"
assert-line "$boothfile" "arg N8N_PORT=" "5678" "n8n:,5678 pins N8N_PORT"

# --- +expose with default port -----------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n+expose'
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"21200:21200",' "expose uses default port 21200"

# --- +expose with custom port — host follows service -------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n:2.41.5,5678+expose'
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"5678:5678",' "expose uses custom port 5678"

# --- +expose:host-port publishes host:service --------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n:2.41.5,5678+expose:18000'
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"18000:5678",' "expose:18000 publishes 18000:5678"

# --- +autostart writes startup with default port -----------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n+autostart'
startup="$prj/.booth/startups/65-n8n-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${N8N_PORT:-21200}' "startup uses param with default"

# --- +persist creates the cache bind -----------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n+persist'
TEST_COUNT=$((TEST_COUNT + 1))
label="persist creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.n8n/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/cache/home/coder/.n8n/.mount-this"
fi

# --- +sandbox pulls in dind + compose, starts before +autostart --------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n+sandbox+autostart'
assert-line "$boothfile" "setup dind" ''                 "sandbox auto-selects dind setup"
assert-line "$boothfile" "setup docker-compose" ''       "sandbox auto-selects docker-compose"
assert-line "$config" "dind = " 'true'                   "sandbox sets dind = true"
assert-line "$config" '    "-e", "N8N_SANDBOX_PORT=' '21280",'      "sandbox passes N8N_SANDBOX_PORT"
assert-line "$config" '    "-e", "N8N_SANDBOX_VERSION=' '1.3.4",'   "sandbox passes N8N_SANDBOX_VERSION"
sandbox_startup="$prj/.booth/startups/64-n8n-sandbox--startup.sh"
assert-line "$sandbox_startup" 'if start-n8n-sandbox' ' --env-only; then' "sandbox startup writes n8n settings first"
sandbox_before_autostart() {
    [[ -f "$sandbox_startup" && -f "$prj/.booth/startups/65-n8n-autostart--startup.sh" ]]
}
check "sandbox startup (64) sorts before autostart (65)" sandbox_before_autostart

# --- +search pulls in dind + compose, starts before +autostart ---------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'n8n+search+autostart'
assert-line "$boothfile" "setup dind" ''                 "search auto-selects dind setup"
assert-line "$boothfile" "setup docker-compose" ''       "search auto-selects docker-compose"
assert-line "$config" "dind = " 'true'                   "search sets dind = true"
assert-line "$config" '    "-e", "N8N_SEARXNG_PORT=' '21281",'                   "search passes N8N_SEARXNG_PORT"
assert-line "$config" '    "-e", "N8N_SEARXNG_VERSION=' '2026.9.30-a9d990033",'  "search passes N8N_SEARXNG_VERSION"
search_startup="$prj/.booth/startups/64-n8n-search--startup.sh"
assert-line "$search_startup" '  > /tmp/n8n-search.log' ' 2>&1 &' "search startup starts SearXNG in the background"
search_before_autostart() {
    [[ -f "$search_startup" && -f "$prj/.booth/startups/65-n8n-autostart--startup.sh" ]]
}
check "search startup (64) sorts before autostart (65)" search_before_autostart

finally
