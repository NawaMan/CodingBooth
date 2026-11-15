#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# missing_required_env (requires-env--source.sh) decides whether
# run-example-tests.sh skips an example for want of host environment variables
# (.cb-tests/requires-env.txt). A wrong answer either fails an example on a host
# that simply lacks credentials, or skips one that could have run — coverage
# that silently did not happen. Each case writes a small file and checks what
# the helper reports missing.
#
# It lives with the setups tests because they are the host-side suite that
# needs no container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh
source ../requires-env--source.sh

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

FAILED=0
N=0
expect() {  # expect <description> <wanted-output> <actual-output>
    N=$((N + 1))
    if [[ "$3" == "$2" ]]; then
        print_test_result true "$0" "$N" "$1"
    else
        print_test_result false "$0" "$N" "$1 (wanted '$2', got '$3')"
        FAILED=$((FAILED + 1))
    fi
}

P="CB_TEST_REQENV_$$"
unset "${P}_A" "${P}_B" "${P}_C" "${P}_EMPTY"
export "${P}_SET=1"
export "${P}_EMPTY="

f="$WORK/requires-env.txt"

expect "a missing file requires nothing" "" "$(missing_required_env "$WORK/none.txt")"

printf '%s\n' "${P}_SET" > "$f"
expect "a set variable satisfies its line" "" "$(missing_required_env "$f")"

printf '%s\n' "${P}_A" > "$f"
expect "an unset variable is reported" "${P}_A" "$(missing_required_env "$f")"

printf '%s\n' "${P}_EMPTY" > "$f"
expect "a set-but-empty variable counts as missing" "${P}_EMPTY" "$(missing_required_env "$f")"

printf '%s\n' "${P}_A|${P}_SET" > "$f"
expect "A|B is satisfied by either" "" "$(missing_required_env "$f")"

printf '%s\n' "${P}_A|${P}_B" > "$f"
expect "A|B with neither set is reported as the whole line" "${P}_A|${P}_B" "$(missing_required_env "$f")"

printf '%s\n' "# a comment" "" "  ${P}_SET  # trailing comment" "${P}_A" "${P}_C" > "$f"
expect "comments, blanks and spaces are ignored; all misses listed" "${P}_A ${P}_C" "$(missing_required_env "$f")"

printf '%s' "${P}_A" > "$f"   # no trailing newline
expect "a last line without a newline is still read" "${P}_A" "$(missing_required_env "$f")"

# The file the example actually ships: with the AWS variables unset it must
# report all three lines; with them set, nothing.
real="../../examples/workspaces/aws-env-example/.cb-tests/requires-env.txt"
expect "aws-env-example: nothing set -> all three missing" \
    "AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION|AWS_DEFAULT_REGION" \
    "$(env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_REGION -u AWS_DEFAULT_REGION \
        bash -c 'source ../requires-env--source.sh; missing_required_env "$1"' _ "$real")"
expect "aws-env-example: keys + AWS_DEFAULT_REGION -> nothing missing" "" \
    "$(env -u AWS_REGION AWS_ACCESS_KEY_ID=x AWS_SECRET_ACCESS_KEY=y AWS_DEFAULT_REGION=z \
        bash -c 'source ../requires-env--source.sh; missing_required_env "$1"' _ "$real")"

exit $FAILED
