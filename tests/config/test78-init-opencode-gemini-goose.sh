#!/bin/bash
# Config generation for OpenCode, Gemini CLI, and Goose templates/extensions.
source "$(dirname "$0")/test-helpers--source.sh"

begin

function has() { grep -qF -- "${2}" "${1}" 2>/dev/null ; }

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
# OpenCode
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "opencode"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg OPENCODE_VERSION=' 'latest'  "opencode default version is latest"
assert-line "$boothfile" 'setup opencode ' '--version ${OPENCODE_VERSION}'  "Boothfile uses opencode param"

config="$prj/.booth/config.toml"
has   "$config" '"~/.local/share/opencode/auth.json:/etc/cb-home-seed/.local/share/opencode/auth.json:ro"' ; check $? "opencode auto-seeds auth.json"
has   "$config" '"~/.config/opencode/opencode.json:/etc/cb-home-seed/.config/opencode/opencode.json:ro"'   ; check $? "opencode auto-seeds opencode.json"
! has "$config" '"~/.config/opencode/plugins:/etc/cb-home-seed/.config/opencode/plugins:ro"'               ; check $? "opencode does not auto-seed plugins"
[[ -f "$prj/.booth/cache/home/coder/.config/opencode/.mount-this" ]] || [[ -f "$prj/.booth/cache/home/coder/.local/share/opencode/.mount-this" ]]
check $? "opencode settings-cache creates .mount-this"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "opencode:1.18.4"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg OPENCODE_VERSION=' '1.18.4'  "opencode custom version"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "opencode+plugins"
config="$prj/.booth/config.toml"
has   "$config" '"~/.config/opencode/plugins:/etc/cb-home-seed/.config/opencode/plugins:ro"' ; check $? "opencode+plugins seeds plugins"
has   "$config" '"~/.local/share/opencode/auth.json:/etc/cb-home-seed/.local/share/opencode/auth.json:ro"' ; check $? "opencode+plugins still seeds auth"
! has "$config" '"~/.config/opencode:/etc/cb-home-seed/.config/opencode:ro"' ; check $? "opencode+plugins does not seed all of ~/.config/opencode"

# ---------------------------------------------------------------------------
# Gemini CLI (pulls nodejs via requires)
# ---------------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "gemini-cli"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GEMINI_CLI_VERSION=' 'latest'  "gemini-cli default version is latest"
assert-line "$boothfile" 'setup gemini-cli ' '${GEMINI_CLI_VERSION}'  "Boothfile uses gemini-cli param"

config="$prj/.booth/config.toml"
has   "$config" '"~/.gemini/settings.json:/etc/cb-home-seed/.gemini/settings.json:ro"'         ; check $? "gemini-cli auto-seeds settings.json"
has   "$config" '"~/.gemini/oauth_creds.json:/etc/cb-home-seed/.gemini/oauth_creds.json:ro"' ; check $? "gemini-cli auto-seeds oauth_creds.json"
! has "$config" '"~/.gemini/extensions:/etc/cb-home-seed/.gemini/extensions:ro"'               ; check $? "gemini-cli does not auto-seed extensions"
! has "$config" '"~/.gemini:/etc/cb-home-seed/.gemini:ro"'                                     ; check $? "gemini-cli does not seed all of ~/.gemini"
[[ -f "$prj/.booth/cache/home/coder/.gemini/.mount-this" ]]
check $? "gemini-cli settings-cache creates .mount-this"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "gemini-cli:0.52.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GEMINI_CLI_VERSION=' '0.52.0'  "gemini-cli custom version"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "gemini-cli+plugins"
config="$prj/.booth/config.toml"
has   "$config" '"~/.gemini/extensions:/etc/cb-home-seed/.gemini/extensions:ro"' ; check $? "gemini-cli+plugins seeds extensions"
has   "$config" '"~/.gemini/settings.json:/etc/cb-home-seed/.gemini/settings.json:ro"' ; check $? "gemini-cli+plugins still seeds settings"

# ---------------------------------------------------------------------------
# Goose
# ---------------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "goose"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GOOSE_VERSION=' 'latest'  "goose default version is latest"
assert-line "$boothfile" 'setup goose ' '--version ${GOOSE_VERSION}'  "Boothfile uses goose param"

config="$prj/.booth/config.toml"
has   "$config" '"~/.config/goose/config.yaml:/etc/cb-home-seed/.config/goose/config.yaml:ro"'   ; check $? "goose auto-seeds config.yaml"
has   "$config" '"~/.config/goose/secrets.yaml:/etc/cb-home-seed/.config/goose/secrets.yaml:ro"' ; check $? "goose auto-seeds secrets.yaml"
! has "$config" '"~/.config/goose/extensions:/etc/cb-home-seed/.config/goose/extensions:ro"'     ; check $? "goose does not auto-seed extensions"
! has "$config" '"~/.config/goose:/etc/cb-home-seed/.config/goose:ro"'                           ; check $? "goose does not seed all of ~/.config/goose"
[[ -f "$prj/.booth/cache/home/coder/.config/goose/.mount-this" ]]
check $? "goose settings-cache creates .mount-this"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "goose:1.43.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GOOSE_VERSION=' '1.43.0'  "goose custom version"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "goose+plugins"
config="$prj/.booth/config.toml"
has   "$config" '"~/.config/goose/extensions:/etc/cb-home-seed/.config/goose/extensions:ro"' ; check $? "goose+plugins seeds extensions"
has   "$config" '"~/.config/goose/config.yaml:/etc/cb-home-seed/.config/goose/config.yaml:ro"' ; check $? "goose+plugins still seeds config"

# Combined select
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "opencode/gemini-cli/goose"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'setup opencode ' '--version ${OPENCODE_VERSION}'  "combined includes opencode"
assert-line "$boothfile" 'setup gemini-cli ' '${GEMINI_CLI_VERSION}'  "combined includes gemini-cli"
assert-line "$boothfile" 'setup goose ' '--version ${GOOSE_VERSION}'  "combined includes goose"

finally
