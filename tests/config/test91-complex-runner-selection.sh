#!/bin/bash
# Guard: the complex runner's test selection. CI shards the suite across jobs so a
# flaky shard can be re-run on its own, which is only safe if the shards are an
# exact partition — a test that lands in no shard is silently never run, and CI
# stays green while covering less than it claims.
#
# Everything here uses `--list`, which resolves the selection and exits before the
# Docker check, so this stays a config-suite test: no daemon, no images, no builds.
source "$(dirname "$0")/test-helpers--source.sh"

# Locate repo root (the directory that holds templates/ and variants/).
root="$(pwd)"
while [[ "$root" != "/" && ! -d "$root/templates" ]]; do root="$(dirname "$root")"; done
runner="$root/tests/complex/run-complex-tests.sh"

# assert-true <condition-result> <message>: pass when the first arg is "0".
function assert-true() {
    TEST_COUNT=$((TEST_COUNT + 1))
    local ok="$1" message="$2"
    local width=64 label="${message} "
    local pad_len=$((width - ${#label})); (( pad_len < 3 )) && pad_len=3
    local pad; pad=$(printf '%*s' "$pad_len" '' | tr ' ' '.')
    echo -n "Test ${TEST_COUNT}: ${label}${pad} "
    if [[ "$ok" == "0" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1)); echo -e "\033[32mPASSED\033[0m"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1)); FAIL_TESTS+=("Test ${TEST_COUNT}: ${message}")
        echo -e "\033[31mFAILED\033[0m"
    fi
}

begin

[[ -x "$runner" ]]; assert-true "$?" "complex runner is executable"

# --list must agree with what is actually on disk.
on_disk="$(cd "$root/tests/complex" && ls -d test-*/ 2>/dev/null | sed 's#/$##' | sort)"
listed="$(bash "$runner" --list | sort)"
[[ "$listed" == "$on_disk" ]]
assert-true "$?" "--list matches the test-*/ dirs on disk"

count="$(printf '%s\n' "$listed" | grep -c .)"
(( count > 0 )); assert-true "$?" "discovery finds tests (${count})"

# The partition invariant, at several shard counts — CI uses 4, but the runner
# must not quietly drop or duplicate a test at any width.
for total in 2 3 4 5 8; do
    union=""
    balanced=true
    min=999999; max=0
    for (( i = 1; i <= total; i++ )); do
        shard="$(bash "$runner" --shard "${i}/${total}" --list)"
        n="$(printf '%s\n' "$shard" | grep -c .)"
        (( n < min )) && min=$n
        (( n > max )) && max=$n
        union+="${shard}"$'\n'
    done
    union="$(printf '%s' "$union" | grep . | sort)"

    [[ "$union" == "$listed" ]]
    assert-true "$?" "${total} shards cover every test exactly once"

    dupes="$(printf '%s\n' "$union" | uniq -d | grep -c . || true)"
    [[ "$dupes" == "0" ]]
    assert-true "$?" "${total} shards do not overlap"

    # Round-robin over a sorted list can never differ by more than one.
    (( max - min <= 1 )); assert-true "$?" "${total} shards are balanced (${min}..${max})"
done

# Named selection — this is what the failure summary tells you to paste back.
first="$(printf '%s\n' "$listed" | head -1)"
second="$(printf '%s\n' "$listed" | sed -n 2p)"
picked="$(bash "$runner" --list "$first" "$second")"
[[ "$picked" == "${first}"$'\n'"${second}" ]]
assert-true "$?" "named selection runs exactly the named tests"

# A trailing slash is what tab-completion produces — it must not break the lookup.
bash "$runner" --list "${first}/" >/dev/null 2>&1
assert-true "$?" "a trailing slash on a test name is accepted"

# Bad input must be rejected, not silently reinterpreted as "run everything" —
# that would turn a typo in the CI matrix into a suite that quietly runs nothing
# or, worse, runs the full 23min suite in every shard.
bash "$runner" --shard 5/4  --list >/dev/null 2>&1; [[ $? -eq 2 ]]
assert-true "$?" "out-of-range shard is rejected"

bash "$runner" --shard 0/4  --list >/dev/null 2>&1; [[ $? -eq 2 ]]
assert-true "$?" "zero shard index is rejected"

bash "$runner" --shard 2-4  --list >/dev/null 2>&1; [[ $? -eq 2 ]]
assert-true "$?" "malformed shard spec is rejected"

bash "$runner" --shard 1/4 "$first" --list >/dev/null 2>&1; [[ $? -eq 2 ]]
assert-true "$?" "--shard combined with test names is rejected"

bash "$runner" --list test-does-not-exist >/dev/null 2>&1; [[ $? -eq 2 ]]
assert-true "$?" "unknown test name is rejected"

bash "$runner" --bogus-flag --list >/dev/null 2>&1; [[ $? -eq 2 ]]
assert-true "$?" "unknown option is rejected"

finally
