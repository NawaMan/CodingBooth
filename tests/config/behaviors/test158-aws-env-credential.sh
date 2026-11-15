#!/bin/bash
# aws-cli+env passes the AWS credential variables in by name, and combines with or
# replaces the file-based aws-cli+credential.
#
# The extension is the environment route (CI runners, `folio exec`): bare `-e NAME`
# entries only, so no value is ever written to config.toml, and booth drops any the
# host has not set (dryrun/test034). AWS_PROFILE must stay out: it names a profile in
# ~/.aws/config, which an env-only booth does not have, and the CLI fails on a
# profile it cannot find.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
config="$prj/.booth/config.toml"

# has <file> <substring> — 0 when the file contains it
function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }

# check <0-if-ok> <message>
function check() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="${1}" message="${2}" width=64
    local label="${message} "
    local pad_len=$((width - ${#label}))
    if (( pad_len < 3 )); then pad_len=3; fi
    local pad
    pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    local test="Test ${TEST_COUNT}: ${label}"
    echo -n "${test}${pad} "
    if [[ "${ok}" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAIL_TESTS+=("${test}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

VARS=(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_REGION AWS_DEFAULT_REGION)

# ---------------------------------------------------------------------------
# env only — aws-cli+env~credential
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "aws-cli+env~credential"
for v in "${VARS[@]}"; do
    has "$config" "\"-e\", \"$v\"" ; check $? "env only: passes $v by name"
done
! has "$config" 'AWS_PROFILE'      ; check $? "env only: does not pass AWS_PROFILE"
! has "$config" '.aws/'            ; check $? "env only: mounts no ~/.aws file"
! grep -qE '"AWS_[A-Z_]+=' "$config" ; check $? "env only: writes no AWS_* value"
has "$prj/.booth/Boothfile" 'setup aws-cli' ; check $? "env only: still installs the AWS CLI"

# ---------------------------------------------------------------------------
# both — aws-cli+env keeps the auto-selected file seeding
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "aws-cli+env"
has "$config" '"-e", "AWS_ACCESS_KEY_ID"'                               ; check $? "both: passes AWS_ACCESS_KEY_ID"
has "$config" '"~/.aws/credentials:/etc/cb-home-seed/.aws/credentials:ro"' ; check $? "both: still seeds ~/.aws/credentials"

# ---------------------------------------------------------------------------
# default — aws-cli alone does not pass any AWS_* variable
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "aws-cli"
! has "$config" '"-e", "AWS_' ; check $? "aws-cli alone passes no AWS_* variable"

finally
