#!/bin/bash
# Credential extensions must seed credentials, not whole application-state directories.
#
# Each of these used to mount the tool's entire home directory into /etc/cb-home-seed —
# `~/.aws`, `~/.azure`, `~/.kube`, `~/.codex`, `~/.config/gcloud`. booth-entry copies
# that seed into the container home on every start, so the copy included whatever else
# lived there: gcloud writes a log file per invocation, az writes a telemetry file per
# invocation and unpacks extensions as full Python packages, kubectl caches a discovery
# document per cluster, and ~/.codex keeps a transcript of every conversation. All of it
# was copied into every container, and none of it is a credential.
#
# These assertions pin the narrow form. The whole-directory mount is what must not
# come back, so each case asserts the absence of the bare `~/.dir:` spec as well.
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
# kubectl — the kubeconfig, not ~/.kube/cache + ~/.kube/http-cache
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "kubectl+credential"
has   "$config" '"~/.kube/config:/etc/cb-home-seed/.kube/config:ro"' ; check $? "kubectl seeds ~/.kube/config"
! has "$config" '"~/.kube:/etc/cb-home-seed/.kube:ro"'               ; check $? "kubectl does not seed all of ~/.kube"

# ---------------------------------------------------------------------------
# aws — config + credentials + the SSO session, not the assumed-role cache
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "aws-cli+credential"
has   "$config" '"~/.aws/credentials:/etc/cb-home-seed/.aws/credentials:ro"' ; check $? "aws seeds ~/.aws/credentials"
has   "$config" '"~/.aws/config:/etc/cb-home-seed/.aws/config:ro"'           ; check $? "aws seeds ~/.aws/config"
has   "$config" '"~/.aws/sso/cache:/etc/cb-home-seed/.aws/sso/cache:ro"'     ; check $? "aws seeds the SSO session cache"
! has "$config" '"~/.aws:/etc/cb-home-seed/.aws:ro"'                         ; check $? "aws does not seed all of ~/.aws"

# ---------------------------------------------------------------------------
# azure — the account + token cache, not cliextensions/ or the per-command logs
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "azure-cli+credential"
has   "$config" '"~/.azure/azureProfile.json:/etc/cb-home-seed/.azure/azureProfile.json:ro"'         ; check $? "azure seeds the signed-in account"
has   "$config" '"~/.azure/msal_token_cache.json:/etc/cb-home-seed/.azure/msal_token_cache.json:ro"' ; check $? "azure seeds the token cache"
! has "$config" '"~/.azure:/etc/cb-home-seed/.azure:ro"'                                             ; check $? "azure does not seed all of ~/.azure"

# ---------------------------------------------------------------------------
# gcloud — the credential stores, not logs/ (a new file per gcloud invocation)
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "gcloud+credential"
has   "$config" '"~/.config/gcloud/credentials.db:/etc/cb-home-seed/.config/gcloud/credentials.db:ro"' ; check $? "gcloud seeds credentials.db"
has   "$config" '"~/.config/gcloud/configurations:/etc/cb-home-seed/.config/gcloud/configurations:ro"' ; check $? "gcloud seeds the active configuration"
! has "$config" '"~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro"'                               ; check $? "gcloud does not seed all of ~/.config/gcloud"

# ---------------------------------------------------------------------------
# codex — auth + settings, not sessions/ (a transcript of every conversation)
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "codex+credential"
has   "$config" '"~/.codex/auth.json:/etc/cb-home-seed/.codex/auth.json:ro"'     ; check $? "codex seeds auth.json"
has   "$config" '"~/.codex/config.toml:/etc/cb-home-seed/.codex/config.toml:ro"' ; check $? "codex seeds config.toml"
! has "$config" '"~/.codex:/etc/cb-home-seed/.codex:ro"'                         ; check $? "codex does not seed all of ~/.codex"

# ---------------------------------------------------------------------------
# grok — auth + settings, not sessions/worktrees/downloads
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "grok+credential"
has   "$config" '"~/.grok/auth.json:/etc/cb-home-seed/.grok/auth.json:ro"'     ; check $? "grok seeds auth.json"
has   "$config" '"~/.grok/config.toml:/etc/cb-home-seed/.grok/config.toml:ro"' ; check $? "grok seeds config.toml"
! has "$config" '"~/.grok:/etc/cb-home-seed/.grok:ro"'                         ; check $? "grok does not seed all of ~/.grok"

# ---------------------------------------------------------------------------
# oh-my-pi — agent.db + config.yml, not sessions/logs/natives
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "oh-my-pi+credential"
has   "$config" '"~/.omp/agent/agent.db:/etc/cb-home-seed/.omp/agent/agent.db:ro"'     ; check $? "oh-my-pi seeds agent.db"
has   "$config" '"~/.omp/agent/config.yml:/etc/cb-home-seed/.omp/agent/config.yml:ro"' ; check $? "oh-my-pi seeds config.yml"
! has "$config" '"~/.omp:/etc/cb-home-seed/.omp:ro"'                                   ; check $? "oh-my-pi does not seed all of ~/.omp"

# ---------------------------------------------------------------------------
# opencode — auth + config, not full share/config trees
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "opencode+credential"
has   "$config" '"~/.local/share/opencode/auth.json:/etc/cb-home-seed/.local/share/opencode/auth.json:ro"' ; check $? "opencode seeds auth.json"
has   "$config" '"~/.config/opencode/opencode.json:/etc/cb-home-seed/.config/opencode/opencode.json:ro"'   ; check $? "opencode seeds opencode.json"
! has "$config" '"~/.config/opencode:/etc/cb-home-seed/.config/opencode:ro"'                               ; check $? "opencode does not seed all of ~/.config/opencode"
! has "$config" '"~/.local/share/opencode:/etc/cb-home-seed/.local/share/opencode:ro"'                     ; check $? "opencode does not seed all of share/opencode"

# ---------------------------------------------------------------------------
# gemini-cli — settings + oauth only, not whole ~/.gemini (Antigravity lives there)
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "gemini-cli+credential"
has   "$config" '"~/.gemini/settings.json:/etc/cb-home-seed/.gemini/settings.json:ro"'         ; check $? "gemini-cli seeds settings.json"
has   "$config" '"~/.gemini/oauth_creds.json:/etc/cb-home-seed/.gemini/oauth_creds.json:ro"' ; check $? "gemini-cli seeds oauth_creds.json"
! has "$config" '"~/.gemini:/etc/cb-home-seed/.gemini:ro"'                                     ; check $? "gemini-cli does not seed all of ~/.gemini"

# ---------------------------------------------------------------------------
# goose — config + secrets, not whole ~/.config/goose
# ---------------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select "goose+credential"
has   "$config" '"~/.config/goose/config.yaml:/etc/cb-home-seed/.config/goose/config.yaml:ro"'   ; check $? "goose seeds config.yaml"
has   "$config" '"~/.config/goose/secrets.yaml:/etc/cb-home-seed/.config/goose/secrets.yaml:ro"' ; check $? "goose seeds secrets.yaml"
! has "$config" '"~/.config/goose:/etc/cb-home-seed/.config/goose:ro"'                           ; check $? "goose does not seed all of ~/.config/goose"

finally
