#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: postgrest alone auto-selects postgresql via `requires`, and the two
# setup lines land in alphabetical order (postgresql < postgrest) since both
# default to Boothfile order 60.
run booth config $prj --no-tui --select "postgrest"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg POSTGREST_VERSION=' 'latest'  "default PostgREST version is latest"
assert-line "$boothfile" 'arg POSTGREST_PORT=' '3000'  "default PostgREST port is 3000"
assert-line "$boothfile" 'setup postgrest --version ' '${POSTGREST_VERSION}'  "Boothfile wires postgrest version"
assert-line "$boothfile" 'setup postgresql ' '--version ${PG_VERSION}'  "requires auto-selects postgresql"

TEST_COUNT=$((TEST_COUNT + 1))
label="postgresql line precedes postgrest line "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
pg_line=$(grep -n '^setup postgresql ' "$boothfile" | head -1 | cut -d: -f1)
rest_line=$(grep -n '^setup postgrest ' "$boothfile" | head -1 | cut -d: -f1)
if [[ -n "$pg_line" && -n "$rest_line" && "$pg_line" -lt "$rest_line" ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: setup postgresql (line $pg_line) before setup postgrest (line $rest_line)"
fi

# Test 2: pg-ext-pkg installs both requested extensions and writes the
# level-52 startup hook that enables them once the server is up.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "postgresql+pg-ext-pkg:pgvector,pg_trgm"
boothfile="$prj/.booth/Boothfile"
startup="$prj/.booth/startups/52-postgresql-pg-ext-pkg--startup.sh"

assert-line "$boothfile" 'install pg-ext ' '${PG_EXTS}'  "Boothfile wires the extension list as a param"

TEST_COUNT=$((TEST_COUNT + 1))
label="PG_EXTS arg names both requested extensions "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
arg_line=$(grep '^arg PG_EXTS=' "$boothfile" | head -1)
if [[ "$arg_line" == *"pgvector"* && "$arg_line" == *"pg_trgm"* ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: both pgvector and pg_trgm in '$arg_line'"
fi

TEST_COUNT=$((TEST_COUNT + 1))
label="startup hook reads the extensions manifest "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -qF '/opt/codingbooth/postgresql/extensions.list' "$startup" 2>/dev/null; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: extensions.list reference in $startup"
fi

TEST_COUNT=$((TEST_COUNT + 1))
label="startup hook enables extensions with CREATE EXTENSION "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -qF 'CREATE EXTENSION IF NOT EXISTS' "$startup" 2>/dev/null; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: CREATE EXTENSION IF NOT EXISTS in $startup"
fi

# Test 3: +autostart+expose wires the port through consistently.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "postgrest+autostart+expose"
config="$prj/.booth/config.toml"
startup="$prj/.booth/startups/65-postgrest-autostart--startup.sh"
assert-line "$startup" 'PORT=' '${POSTGREST_PORT:-3000}'  "startup uses param with default port"
assert-line "$config"  '    "-p", ' '"3000:3000",'  "expose uses default port 3000 on both sides"

TEST_COUNT=$((TEST_COUNT + 1))
label="startup exports PGRST_DB_URI with a default "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -qF 'PGRST_DB_URI="${PGRST_DB_URI:-postgres:///postgres}"' "$startup" 2>/dev/null; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: PGRST_DB_URI default export in $startup"
fi

# Test 4: everything selected together — postgresql, pg-ext-pkg, and postgrest
# all land in one Boothfile, and run-args merge (dedup) the pgdata volume with
# the postgrest port publish.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "postgresql+pg-ext-pkg:pgvector,pg_trgm,postgis" --select "postgrest+autostart+expose"
boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"

TEST_COUNT=$((TEST_COUNT + 1))
label="combined Boothfile has all three directives "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -q '^setup postgresql ' "$boothfile" && grep -q '^install pg-ext ' "$boothfile" \
   && grep -q '^setup postgrest ' "$boothfile"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: setup postgresql, install pg-ext, and setup postgrest all in $boothfile"
fi

TEST_COUNT=$((TEST_COUNT + 1))
label="run-args merge the pgdata volume and the postgrest port "
pad=$(printf '%*s' $((64 - ${#label})) '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if grep -qF '"booth-pgdata:/var/lib/postgresql"' "$config" && grep -qF '"3000:3000"' "$config"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo -e "\033[32mPASSED\033[0m"
else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
    echo -e "\033[31mFAILED\033[0m"
    echo "  EXPECTED: both the pgdata volume and 3000:3000 publish in $config"
fi

finally
