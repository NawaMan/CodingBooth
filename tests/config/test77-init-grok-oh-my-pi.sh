#!/bin/bash
# Config generation for Grok Build + Oh My Pi templates and extensions.
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
# Grok Build — parent + auto extensions
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --select "grok"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GROK_VERSION=' 'latest'  "grok default version is latest"
assert-line "$boothfile" 'setup grok ' '--version ${GROK_VERSION}'  "Boothfile uses grok param reference"

config="$prj/.booth/config.toml"
has   "$config" '"~/.grok/auth.json:/etc/cb-home-seed/.grok/auth.json:ro"'     ; check $? "grok auto-seeds auth.json"
has   "$config" '"~/.grok/config.toml:/etc/cb-home-seed/.grok/config.toml:ro"' ; check $? "grok auto-seeds config.toml"
# plugins are opt-in — must NOT appear on bare select
! has "$config" '"~/.grok/installed-plugins:/etc/cb-home-seed/.grok/installed-plugins:ro"' ; check $? "grok does not auto-seed plugins"
! has "$config" '"~/.grok/skills:/etc/cb-home-seed/.grok/skills:ro"'                       ; check $? "grok does not auto-seed skills"
# settings-cache marker
[[ -f "$prj/.booth/cache/home/coder/.grok/.mount-this" ]]
check $? "grok settings-cache creates .mount-this"

# Pin a version
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "grok:0.2.111"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg GROK_VERSION=' '0.2.111'  "grok custom version is 0.2.111"

# Grok + plugins (opt-in)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "grok+plugins"
config="$prj/.booth/config.toml"
has   "$config" '"~/.grok/installed-plugins:/etc/cb-home-seed/.grok/installed-plugins:ro"' ; check $? "grok+plugins seeds installed-plugins"
has   "$config" '"~/.grok/skills:/etc/cb-home-seed/.grok/skills:ro"'                       ; check $? "grok+plugins seeds skills"
has   "$config" '"~/.grok/auth.json:/etc/cb-home-seed/.grok/auth.json:ro"'                 ; check $? "grok+plugins still seeds auth"
! has "$config" '"~/.grok:/etc/cb-home-seed/.grok:ro"'                                     ; check $? "grok+plugins does not seed all of ~/.grok"

# ---------------------------------------------------------------------------
# Oh My Pi — parent + auto extensions
# ---------------------------------------------------------------------------
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "oh-my-pi"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg OH_MY_PI_VERSION=' 'latest'  "oh-my-pi default version is latest"
assert-line "$boothfile" 'setup oh-my-pi ' '--version ${OH_MY_PI_VERSION}'  "Boothfile uses oh-my-pi param reference"

config="$prj/.booth/config.toml"
has   "$config" '"~/.omp/agent/agent.db:/etc/cb-home-seed/.omp/agent/agent.db:ro"'     ; check $? "oh-my-pi auto-seeds agent.db"
has   "$config" '"~/.omp/agent/config.yml:/etc/cb-home-seed/.omp/agent/config.yml:ro"' ; check $? "oh-my-pi auto-seeds config.yml"
! has "$config" '"~/.omp/plugins:/etc/cb-home-seed/.omp/plugins:ro"'                   ; check $? "oh-my-pi does not auto-seed plugins"
[[ -f "$prj/.booth/cache/home/coder/.omp/.mount-this" ]]
check $? "oh-my-pi settings-cache creates .mount-this"

run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "oh-my-pi:17.0.7"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg OH_MY_PI_VERSION=' '17.0.7'  "oh-my-pi custom version is 17.0.7"

# Oh My Pi + plugins (opt-in)
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "oh-my-pi+plugins"
config="$prj/.booth/config.toml"
has   "$config" '"~/.omp/plugins:/etc/cb-home-seed/.omp/plugins:ro"'                   ; check $? "oh-my-pi+plugins seeds plugins"
has   "$config" '"~/.omp/agent/agent.db:/etc/cb-home-seed/.omp/agent/agent.db:ro"'     ; check $? "oh-my-pi+plugins still seeds agent.db"
! has "$config" '"~/.omp:/etc/cb-home-seed/.omp:ro"'                                   ; check $? "oh-my-pi+plugins does not seed all of ~/.omp"

# Both together
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "grok/oh-my-pi"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'setup grok ' '--version ${GROK_VERSION}'  "combined Boothfile includes grok"
assert-line "$boothfile" 'setup oh-my-pi ' '--version ${OH_MY_PI_VERSION}'  "combined Boothfile includes oh-my-pi"

# Both with plugins
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "grok+plugins/oh-my-pi+plugins"
config="$prj/.booth/config.toml"
has   "$config" '"~/.grok/installed-plugins:/etc/cb-home-seed/.grok/installed-plugins:ro"' ; check $? "combined+plugins seeds grok plugins"
has   "$config" '"~/.omp/plugins:/etc/cb-home-seed/.omp/plugins:ro"'                       ; check $? "combined+plugins seeds omp plugins"

finally
