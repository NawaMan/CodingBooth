#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Host-side ${NAME:-digits} on free-form --expose is kept literal in run-args
# and expanded at booth start from the host environment (see BOOTH_VARS.md).

# Test 1: bare ${NAME:-digits} → HOST:HOST
run booth config $prj --no-tui --select "go" --expose '${APP_PORT:-3000}'
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "${APP_PORT:-3000}:${APP_PORT:-3000}"]'  \
  "--expose \${APP_PORT:-3000} expands to HOST:HOST env form"

# Test 2: ${NAME:-digits}:CONTAINER kept as-is
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose '${SERVER_PORT:-12345}:1234'
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "${SERVER_PORT:-12345}:1234"]'  \
  "--expose \${SERVER_PORT:-12345}:1234 kept as-is"

# Test 3: bare ${NAME} without default
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --expose '${HTTP_PORT}:80'
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "${HTTP_PORT}:80"]'  \
  "--expose \${HTTP_PORT}:80 kept as-is"

# Test 4: IP:host-env:container
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --expose '127.0.0.1:${HTTP_PORT:-8080}:80'
config="$prj/.booth/config.toml"
assert-line "$config" 'run-args = ' '["--publish", "127.0.0.1:${HTTP_PORT:-8080}:80"]'  \
  "--expose IP:\${HOST:-n}:CONTAINER kept as-is"

# Test 5: env on container side is rejected
run rm -Rf $prj
mkdir -p $prj
TEST_COUNT=$((TEST_COUNT + 1))
label="--expose rejects env form on the container side "
pad_len=$((64 - ${#label}))
if (( pad_len < 3 )); then pad_len=3; fi
pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
echo -n "Test ${TEST_COUNT}: ${label}${pad} "
if booth config $prj --no-tui --expose '8080:${APP_PORT:-3000}' >>$log 2>&1; then
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAIL_TESTS+=("Test ${TEST_COUNT}: ${label}")
  echo -e "\033[31mFAILED\033[0m"
  echo "  expected command to fail, but it succeeded"
else
  PASS_COUNT=$((PASS_COUNT + 1))
  echo -e "\033[32mPASSED\033[0m"
fi

# Test 6: DSL host-port param still accepts env form (template path)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select 'postgresql+expose:${POSTGRES_PORT:-15432}'
config="$prj/.booth/config.toml"
# postgresql also contributes other run-args; match the publish line specifically
assert-line "$config" '    "-p", ' '"${POSTGRES_PORT:-15432}:5432"'  \
  "DSL +expose:\${NAME:-n} writes host env form into -p"

# Test 7: adjust command preserves the expression
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go" --expose '${APP_PORT:-3000}:3000'
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "# Configured by: " \
  'booth config --no-tui --overwrite --expose ${APP_PORT:-3000}:3000 --select go'  \
  "Adjust command includes host env expose"

finally
