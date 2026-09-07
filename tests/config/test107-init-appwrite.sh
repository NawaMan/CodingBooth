#!/bin/bash
# appwrite-cli + appwrite-server: CLI setup, server requires CLI, autostart
# pulls dind+compose, expose publishes the console port.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: CLI default select
run booth config $prj --no-tui --select "appwrite-cli"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" "arg APPWRITE_CLI_VERSION=" 'latest' \
    "default APPWRITE_CLI_VERSION is latest"
assert-line "$boothfile" "setup appwrite-cli --version " '${APPWRITE_CLI_VERSION}' \
    "Boothfile uses APPWRITE_CLI_VERSION"
assert-line "$config" '    "-v", ' '"~/.appwrite:/etc/cb-home-seed/.appwrite:ro",' \
    "CLI auto-selects credential mount"

# Test 2: CLI version pin
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "appwrite-cli:27.3.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg APPWRITE_CLI_VERSION=" '27.3.0' \
    "appwrite-cli version pin"

# Test 3: server requires CLI and stamps version + ports
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "appwrite-server"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" "setup appwrite-cli --version " '${APPWRITE_CLI_VERSION}' \
    "server auto-selects appwrite-cli"
assert-line "$boothfile" "arg APPWRITE_VERSION=" '1.9.6' \
    "default APPWRITE_VERSION is 1.9.6"
assert-line "$boothfile" "arg APPWRITE_PORT=" '8080' \
    "default APPWRITE_PORT is 8080"
assert-line "$boothfile" "arg APPWRITE_HTTPS_PORT=" '8443' \
    "default APPWRITE_HTTPS_PORT is 8443"
assert-line "$boothfile" "arg APPWRITE_DATA=" 'clean' \
    "default APPWRITE_DATA is clean"
assert-line "$boothfile" "setup appwrite-server --version " '${APPWRITE_VERSION} --http-port ${APPWRITE_PORT} --https-port ${APPWRITE_HTTPS_PORT} --data ${APPWRITE_DATA}' \
    "Boothfile wires version, ports, and data mode"
assert-line "$config" '    "-e", "APPWRITE_DATA=' 'clean",' \
    "clean mode is passed through as APPWRITE_DATA"

# Test 4: expose publishes the default HTTP port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "appwrite-server+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"8080:8080",' \
    "expose uses default port 8080"

# Test 5: autostart pulls in dind + docker-compose and writes a startup script
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "appwrite-server+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-appwrite-server-autostart--startup.sh"
assert-line "$boothfile" "setup dind" '' \
    "autostart auto-selects dind setup"
assert-line "$boothfile" "setup docker-compose" '' \
    "autostart auto-selects docker-compose setup"
assert-line "$config" "dind = " 'true' \
    "autostart sets dind = true"
assert-line "$startup" 'PORT=' '${APPWRITE_PORT:-8080}' \
    "startup uses APPWRITE_PORT with default"

# Test 6: version + custom HTTP port + expose
# 8081 is 4 digits — the official installer rejects ports longer than that.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "appwrite-server:1.8.1,8081+expose"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
assert-line "$boothfile" "arg APPWRITE_VERSION=" '1.8.1' \
    "full: version pin"
assert-line "$boothfile" "arg APPWRITE_PORT=" '8081' \
    "full: custom APPWRITE_PORT"
assert-line "$config" '    "-p", ' '"8081:8081",' \
    "full: expose uses custom port"

# Test 7: +persist uses CodingBooth cache (directory tree, not a config.toml key)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "appwrite-server+persist"
config="$prj/.booth/config.toml"
TEST_COUNT=$((TEST_COUNT + 1))
label="+persist creates cache dir with .mount-this "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.appwrite-server/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/cache/home/coder/.appwrite-server/.mount-this"
fi
TEST_COUNT=$((TEST_COUNT + 1))
label="+persist run-args pin APPWRITE_DATA=persist "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q '"APPWRITE_DATA=persist"' "$config"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: APPWRITE_DATA=persist in $config"
fi

# Test 8: +seed uses home-seed (CodingBooth seed) and pins APPWRITE_DATA
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "appwrite-server+seed"
config="$prj/.booth/config.toml"
TEST_COUNT=$((TEST_COUNT + 1))
label="+seed writes home-seed/.appwrite-server/.keep "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/home-seed/.appwrite-server/.keep" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/home-seed/.appwrite-server/.keep"
fi
TEST_COUNT=$((TEST_COUNT + 1))
label="+seed run-args pin APPWRITE_DATA=seed "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q '"APPWRITE_DATA=seed"' "$config"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: APPWRITE_DATA=seed in $config"
fi

finally
