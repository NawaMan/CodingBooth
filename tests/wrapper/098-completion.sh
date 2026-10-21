#!/usr/bin/env bash
# 098 — tab completion: the wrapper answers `__complete` itself when there is no
#       binary to ask, hands it to the binary when there is, prints a script per
#       shell, and shell-config installs and removes the scripts with its block.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -euo pipefail

export HOME=/tmp/home-completion
rm -rf "$HOME"
mkdir -p "$HOME"

cp /booth/booth ./booth
chmod +x ./booth

echo "=== NO BINARY ==="
./booth __complete ""
./booth __complete shell-config ""

echo "=== SCRIPTS ==="
./booth completion bash | grep -q 'complete -F _booth_completion booth' && echo "bash-script"
./booth completion zsh  | grep -q 'compdef _booth booth' && echo "zsh-script"
./booth completion fish | grep -q 'complete -c booth' && echo "fish-script"
./booth completion tcsh >/dev/null 2>&1 && echo "tcsh accepted" || echo "tcsh rejected"

# The local build, installed the way `install` lays it out, so the wrapper
# verifies and runs it without a download.
version=$(tr -d ' \t\r\n' < /booth/version.txt)
cache="$HOME/.cache/codingbooth/versions/$version"
mkdir -p "$cache" .booth/tools
cp /booth/bin/codingbooth-linux-* "$cache/"
(cd "$cache" && sha256sum codingbooth-linux-* > codingbooth.sha256)
printf 'version=%s\ncache=shared\n' "$version" > .booth/tools/codingbooth.lock
touch .booth/gpu--config.toml

echo "=== BINARY ==="
./booth __complete st
./booth __complete stop --engine=p

echo "=== SHELL-CONFIG ==="
./booth shell-config install >/dev/null
data="$HOME/.local/share/codingbooth"
ls "$data"
grep -q '__booth_complete' "$HOME/.config/fish/completions/booth.fish" && echo "fish-installed"

echo "=== BASH TAB ==="
# What bash does on Tab after `booth --profile `: the rc block sources the
# script, which asks the central wrapper, which hands off to this project.
bash -c '
    source "$HOME/.bashrc"
    COMP_LINE="booth --profile "; COMP_POINT=${#COMP_LINE}
    COMP_WORDS=(booth --profile ""); COMP_CWORD=2
    _booth_completion
    printf "reply:%s\n" "${COMPREPLY[@]}"
'

echo "=== UNINSTALL ==="
./booth shell-config uninstall >/dev/null
ls "$data" 2>/dev/null || echo "data dir gone"
grep -q '__booth_complete' "$HOME/.config/fish/completions/booth.fish" && echo "fish-still-there" || true
BASH
)

no_binary="${LAST_OUTPUT#*=== NO BINARY ===}";       no_binary="${no_binary%%=== SCRIPTS ===*}"
scripts="${LAST_OUTPUT#*=== SCRIPTS ===}";           scripts="${scripts%%=== BINARY ===*}"
binary="${LAST_OUTPUT#*=== BINARY ===}";             binary="${binary%%=== SHELL-CONFIG ===*}"
shell_config="${LAST_OUTPUT#*=== SHELL-CONFIG ===}"; shell_config="${shell_config%%=== BASH TAB ===*}"
bash_tab="${LAST_OUTPUT#*=== BASH TAB ===}";         bash_tab="${bash_tab%%=== UNINSTALL ===*}"
uninstall="${LAST_OUTPUT#*=== UNINSTALL ===}"

# No binary: the wrapper's own commands, then its subcommands.
assert_contains "$no_binary" "shell-config"
assert_contains "$no_binary" "completion"
assert_contains "$no_binary" "status"
assert_contains "$no_binary" ":words"
assert_not_contains "$no_binary" "not installed"

assert_contains "$scripts" "bash-script"
assert_contains "$scripts" "zsh-script"
assert_contains "$scripts" "fish-script"
assert_contains "$scripts" "tcsh rejected"

# With the binary: its commands and descriptions, and flag values.
assert_contains "$binary" $'stop\tStop a running booth'
assert_contains "$binary" "--engine=podman"

assert_contains "$shell_config" "completion.bash"
assert_contains "$shell_config" "completion.zsh"
assert_contains "$shell_config" "fish-installed"

assert_contains "$bash_tab" "reply:gpu"

assert_contains "$uninstall" "data dir gone"
assert_not_contains "$uninstall" "completion.bash"
assert_not_contains "$uninstall" "fish-still-there"
pass
