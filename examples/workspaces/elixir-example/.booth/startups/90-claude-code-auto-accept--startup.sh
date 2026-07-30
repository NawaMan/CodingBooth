#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --variant codeserver --select elixir+vscode-ext+repl-history/claude-code+auto-accept+credential+settings-cache

# Detect user-bound volumes and protect them from accidental rm -rf
# by patching Claude Code's deny rules with jq.
settings="$HOME/.claude/settings.json"
if [ -f "$settings" ] && command -v jq &>/dev/null; then
    # Collect non-system mount points from mountinfo.
    # These are likely user-bound persistent volumes.
    protected=$(awk '{print $5}' /proc/self/mountinfo 2>/dev/null | sort -u | grep -v -xE '/' | grep -v -E '^/(proc|sys|dev|run|tmp)(/|$)' | grep -v -E '^/etc/(resolv\.conf|hostname|hosts)$' || true)
    if [ -n "$protected" ]; then
        deny_rules='[]'
        while IFS= read -r mp; do
            deny_rules=$(echo "$deny_rules" | jq --arg p "$mp" '. + ["Bash(rm -rf \($p))", "Bash(rm -rf \($p)/*)"]')
        done <<< "$protected"
        jq --argjson new_deny "$deny_rules" '
            .permissions.deny = ((.permissions.deny // []) + $new_deny | unique)
        ' "$settings" > "${settings}.tmp" && command mv -f "${settings}.tmp" "$settings"
    fi
fi
