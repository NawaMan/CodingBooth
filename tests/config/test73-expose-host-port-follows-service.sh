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
# A host port may be base-relative: "+4567" means offset base + 4567, left in
# run-args as "+4567:5672" and resolved against the base at container start — the
# booth port unless --offset-base moved it (tests/dryrun/test019 and test030 cover
# both resolutions). The "+" has to survive the DSL,
# which splits an item on "+" to find its extensions — it used to read "+4567" as
# an extension named "4567".
# ---------------------------------------------------------------------------
# Start from a clean .booth: the pins the previous block wrote (RABBIT_MGMT_HOST_PORT
# =25672) are carried over on reconfigure by design, and would mask what is asserted here.
rm -rf "$prj/.booth"
boothfile="$prj/.booth/Boothfile"

run booth config $prj --no-tui --overwrite --select "rabbitmq+start+expose:+4567"
has "$config" '"+4567:5672"'  ; check $? "rabbitmq+expose:+4567 keeps the relative host port"
has "$config" '"15672:15672"' ; check $? "the un-overridden UI port stays absolute"

# A bare number is still an absolute host port — the "+" is what makes it relative.
rm -rf "$prj/.booth"
run booth config $prj --no-tui --overwrite --select "cloudbeaver+expose:19000"
has   "$config" '"19000:8978"' ; check $? "a bare host port is still absolute"
! has "$config" '"+'           ; check $? "no relative mapping appears without a '+'"

# An extension after a relative param must still parse as an extension, not as more of
# the param: "+start" begins with a letter, "+4567" does not. The +start extension is
# what provisions the dev user, so its RABBIT_USER arg is the proof that it applied.
rm -rf "$prj/.booth"
run booth config $prj --no-tui --overwrite --select "rabbitmq+expose:+4567+start"
has "$config"    '"+4567:5672"'    ; check $? "an extension can follow a relative port param"
has "$boothfile" 'arg RABBIT_USER=' ; check $? "the +start extension after it still applies"

# The recorded "Configured by" line has to survive a round-trip through the parser —
# the TUI regenerates its selection from it.
has "$boothfile" 'rabbitmq+expose:+4567+start' ; check $? "the relative port round-trips into the adjust line"

# The relative value is a choice, not a derivation, so it must survive re-configuration.
rm -rf "$prj/.booth"
run booth config $prj --no-tui --overwrite --select "rabbitmq+start+expose:+4567"
run booth config $prj --no-tui --overwrite --select "rabbitmq+start+expose/go"
has "$config" '"+4567:5672"' ; check $? "a relative host port survives re-configuration"

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
