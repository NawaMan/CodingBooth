#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: AFFiNE Server with defaults — pulls nodejs, postgresql, redis
run booth config $prj --no-tui --select "affine-server"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg AFFINE_SERVER_VERSION=' 'stable'  "default image tag is stable"
assert-line "$boothfile" 'arg AFFINE_SERVER_PORT=' '13010'  "default port is 13010"
assert-line "$boothfile" 'arg AFFINE_SERVER_DATA=' 'clean'  "default data mode is clean"
assert-line "$boothfile" 'copy --from=ghcr.io/toeverything/affine:' '${AFFINE_SERVER_VERSION} /app /opt/affine'  "copies official image"
assert-line "$boothfile" 'setup affine-server --port ' '${AFFINE_SERVER_PORT} --data ${AFFINE_SERVER_DATA}'  "Boothfile wires port and data mode"
assert-line "$boothfile" 'setup nodejs ' '${NODE_VERSION}'  "requires auto-selects nodejs"
assert-line "$boothfile" 'setup postgresql ' '--version ${PG_VERSION}'  "requires auto-selects postgresql"
assert-line "$boothfile" 'setup redis ' '--version ${REDIS_VERSION}'  "requires auto-selects redis"

# Test 2: custom image tag and port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-server:canary,18010"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg AFFINE_SERVER_VERSION=' 'canary'  "custom image tag is canary"
assert-line "$boothfile" 'arg AFFINE_SERVER_PORT=' '18010'  "custom port is 18010"

# Test 3: +expose with default port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-server+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"13010:13010",'  "expose uses default port 13010"

# Test 4: +expose with custom port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-server:stable,18010+expose"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' '"18010:18010",'  "expose uses custom port 18010"

# Test 5: +autostart writes a startup that calls the starter
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-server+autostart"
startup="$prj/.booth/startups/70-affine-server-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${AFFINE_SERVER_PORT:-13010}'  "startup uses param with default"

# Test 6: custom port + expose + autostart stay consistent
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-server:stable,18010+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/70-affine-server-autostart--startup.sh"
assert-line "$boothfile" 'arg AFFINE_SERVER_PORT=' '18010'  "full: Boothfile param is 18010"
assert-line "$config"    '    "-p", ' '"18010:18010",'  "full: run-args uses 18010"
assert-line "$startup"   'PORT=' '${AFFINE_SERVER_PORT:-18010}'  "full: startup uses param with default 18010"

# Test 7: +persist uses CodingBooth cache
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-server+persist"
config="$prj/.booth/config.toml"
TEST_COUNT=$((TEST_COUNT + 1))
label="+persist creates cache dir with .mount-this "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.affine/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/cache/home/coder/.affine/.mount-this"
fi
TEST_COUNT=$((TEST_COUNT + 1))
label="+persist run-args pin AFFINE_SERVER_DATA=persist "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q '"AFFINE_SERVER_DATA=persist"' "$config"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: AFFINE_SERVER_DATA=persist in $config"
fi

# Test 8: +seed uses home-seed
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "affine-server+seed"
config="$prj/.booth/config.toml"
TEST_COUNT=$((TEST_COUNT + 1))
label="+seed writes home-seed/.affine/.keep "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/home-seed/.affine/.keep" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: $prj/.booth/home-seed/.affine/.keep"
fi
TEST_COUNT=$((TEST_COUNT + 1))
label="+seed run-args pin AFFINE_SERVER_DATA=seed "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q '"AFFINE_SERVER_DATA=seed"' "$config"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: AFFINE_SERVER_DATA=seed in $config"
fi

finally
