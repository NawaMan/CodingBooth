#!/bin/bash
# An expose extension publishes HOST:CONTAINER. The container side is the port the
# service actually listens on; the host side must follow it by default and be
# overridable on its own.
#
# The host side used to be the same param as the container side, so the only way to
# move a busy host port was to move the service with it. Each expose extension now
# declares a *_HOST_PORT param whose default is "${SERVICE_PORT}" — a param default
# that references another param, resolved to a fixpoint by the compiler.
#
# Three properties are pinned here, and the middle one is the one that regresses
# silently: an earlier round of these templates hardcoded the host port (2222, 8978),
# so `openssh+server:2200+expose` published a port nothing was listening on.
source "$(dirname "$0")/test-helpers--source.sh"

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

# ---------------------------------------------------------------------------
# Default: host port equals the service port (unchanged from before *_HOST_PORT)
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "openssh+server+expose"
has "$config" '"2222:2222"' ; check $? "openssh+server+expose publishes 2222:2222"

run booth config $prj --no-tui --overwrite --select "cloudbeaver+expose"
has "$config" '"8978:8978"' ; check $? "cloudbeaver+expose publishes 8978:8978"

run booth config $prj --no-tui --overwrite --select "notebook+expose"
has "$config" '"18888:18888"' ; check $? "notebook+expose publishes 18888:18888"

# ---------------------------------------------------------------------------
# Move the service: the published host port must follow it, not stay behind
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "openssh+server:2200+expose"
has   "$config" '"2200:2200"' ; check $? "openssh+server:2200+expose publishes 2200:2200"
! has "$config" '"2222'       ; check $? "openssh does not publish the old hardcoded 2222"

run booth config $prj --no-tui --overwrite --select "cloudbeaver:25.3.5,9000+expose"
has   "$config" '"9000:9000"' ; check $? "cloudbeaver:...,9000+expose publishes 9000:9000"
! has "$config" '"8978'       ; check $? "cloudbeaver does not publish the old hardcoded 8978"

# ---------------------------------------------------------------------------
# Override the host side alone: service stays put, host port moves
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "openssh+server:22+expose:2222"
has "$config" '"2222:22"' ; check $? "openssh+server:22+expose:2222 publishes 2222:22"

run booth config $prj --no-tui --overwrite --select "cloudbeaver:25.3.5,9000+expose:19000"
has "$config" '"19000:9000"' ; check $? "cloudbeaver+expose:19000 publishes 19000:9000"

# Two ports, overridden positionally: AMQP first, management UI second.
run booth config $prj --no-tui --overwrite --select "rabbitmq+start+expose:15672,25672"
has "$config" '"15672:5672"'  ; check $? "rabbitmq+expose:15672,... publishes AMQP on 15672"
has "$config" '"25672:15672"' ; check $? "rabbitmq+expose:...,25672 publishes the UI on 25672"

# ---------------------------------------------------------------------------
# The reference itself must never reach the output — an unresolved ${SSH_PORT}
# in run-args is a port mapping docker rejects at start.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "openssh+server:2200+expose"
! has "$config" '${' ; check $? "no unresolved \${PARAM} reference survives into run-args"

# ---------------------------------------------------------------------------
# Re-configuration. Existing `arg` pins are carried over from the Boothfile, and
# a followed host port lands there as a resolved number — indistinguishable from
# a pin by string comparison. A derived value must re-derive; a chosen one must
# survive. Getting this backwards leaves the published port on the port the
# service *used* to listen on.
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "openssh+server:2200+expose"
run booth config $prj --no-tui --overwrite --select "openssh+server:22+expose"
has   "$config" '"22:22"'   ; check $? "a derived host port follows the service to its new port"
! has "$config" '"2200'     ; check $? "the derived host port does not stay behind on 2200"

run booth config $prj --no-tui --overwrite --select "openssh+server:22+expose:2222"
run booth config $prj --no-tui --overwrite --select "openssh+server:22+expose/go"
has "$config" '"2222:22"' ; check $? "an explicit host-port pin survives re-configuration"

finally
