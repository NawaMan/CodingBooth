#!/bin/bash
# anythingllm: COPY --from official image, port pin, expose, autostart, persist, project-fs, passwordless
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: default select
run booth config $prj --no-tui --select "anythingllm"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg ANYTHINGLLM_VERSION=' '1.16.1' \
    "default version is 1.16.1"
assert-line "$boothfile" 'arg ANYTHINGLLM_PORT=' '3001' \
    "default port is 3001"
assert-line "$boothfile" 'copy --from=mintplexlabs/anythingllm:' '${ANYTHINGLLM_VERSION} /app /opt/anythingllm' \
    "Boothfile copies official image"
assert-line "$boothfile" 'setup anythingllm --version ' '${ANYTHINGLLM_VERSION} --port ${ANYTHINGLLM_PORT}' \
    "Boothfile wires version and port"

# Test 2: version + port pin
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm:1.16.0,13001"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg ANYTHINGLLM_VERSION=' '1.16.0' \
    "custom version is 1.16.0"
assert-line "$boothfile" 'arg ANYTHINGLLM_PORT=' '13001' \
    "custom port is 13001"

# Test 3: +expose with default port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "3001:3001"]' \
    "expose uses default port 3001"

# Test 4: +expose with custom port — host follows service
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm:1.16.1,13001+expose"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "13001:13001"]' \
    "expose uses custom port 13001"

# Test 5: +expose:host-port publishes host:service
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm:1.16.1,13001+expose:19000"
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-p", "19000:13001"]' \
    "expose:19000 publishes 19000:13001"

# Test 6: +autostart writes startup with default port
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm+autostart"
startup="$prj/.booth/startups/65-anythingllm-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${ANYTHINGLLM_PORT:-3001}' \
    "startup uses param with default"

# Test 7: +persist creates the cache bind
# Template cache-dirs create .booth/cache/.../.mount-this; they are not
# written back as a config.toml cache-dirs key (same as claude-code+settings-cache).
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm+persist"
TEST_COUNT=$((TEST_COUNT + 1))
label="persist creates .mount-this marker "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.anythingllm/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $prj/.booth/cache/home/coder/.anythingllm/.mount-this to exist"
fi

# Test 8: version + custom port + expose + autostart
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm:1.16.0,13001+expose+autostart"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-anythingllm-autostart--startup.sh"
assert-line "$boothfile" 'arg ANYTHINGLLM_VERSION=' '1.16.0' \
    "full: version pin"
assert-line "$boothfile" 'arg ANYTHINGLLM_PORT=' '13001' \
    "full: custom port"
assert-line "$config"    'run-args = ' '["-p", "13001:13001"]' \
    "full: run-args uses 13001"
assert-line "$startup"   'PORT=' '${ANYTHINGLLM_PORT:-13001}' \
    "full: startup uses param with default 13001"

# Test 9: +project-fs bind-mounts the project into the fs jail
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm+project-fs"
startup="$prj/.booth/startups/60-anythingllm-project-fs--startup.sh"
config="$prj/.booth/config.toml"
assert-line "$startup" 'JAIL=' '"${STORAGE_DIR:-$HOME/.anythingllm}/anythingllm-fs"' \
    "project-fs jail is STORAGE_DIR/anythingllm-fs"
assert-line "$config" 'run-args = ' '["-v", "@code:/home/coder/.anythingllm/anythingllm-fs/code"]' \
    "project-fs bind-mounts @code into the fs jail"
enable="$prj/.booth/startups/70-anythingllm-project-fs--startup.sh"
assert-line "$enable" 'echo "AnythingLLM project-fs: enabling filesystem-agent in the background' ' (log: /tmp/anythingllm-project-fs.log)"' \
    "project-fs enables the filesystem-agent skill"

# Test 10: +persist does not write the project-fs startup
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm+persist"
TEST_COUNT=$((TEST_COUNT + 1))
label="persist does not write project-fs startup "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ ! -f "$prj/.booth/startups/60-anythingllm-project-fs--startup.sh" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: no $prj/.booth/startups/60-anythingllm-project-fs--startup.sh"
fi

# Test 11: persist + project-fs are independent and can combine
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm+persist+project-fs"
TEST_COUNT=$((TEST_COUNT + 1))
label="persist+project-fs keeps cache bind "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if [ -f "$prj/.booth/cache/home/coder/.anythingllm/.mount-this" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: file $prj/.booth/cache/home/coder/.anythingllm/.mount-this to exist"
fi
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["-v", "@code:/home/coder/.anythingllm/anythingllm-fs/code"]' \
    "persist+project-fs still bind-mounts the project"

# Test 12: +passwordless sets empty AUTH_TOKEN and strips .env on boot
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "anythingllm+passwordless"
config="$prj/.booth/config.toml"
startup55="$prj/.booth/startups/55-anythingllm-passwordless--startup.sh"
startup75="$prj/.booth/startups/75-anythingllm-passwordless--startup.sh"
assert-line "$config" 'run-args = ' '["-e", "AUTH_TOKEN="]' \
    "passwordless sets empty AUTH_TOKEN"
assert-line "$startup55" '    echo "AnythingLLM passwordless: removed AUTH_TOKEN from $f"' '' \
    "passwordless strips AUTH_TOKEN from .env"
assert-line "$startup75" 'echo "AnythingLLM passwordless: AUTH_TOKEN left empty' ' (log: /tmp/anythingllm-passwordless.log)"' \
    "passwordless disables password on the running server"

finally
