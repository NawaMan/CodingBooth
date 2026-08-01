#!/bin/bash
set -e
# Configured by: booth config --no-tui --overwrite --select claude-code+auto-accept+credential+settings-cache

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

# Mark the project trusted so Claude Code skips its "Is this a project you
# trust?" gate. That gate is not a permission rule -- no entry in the allow
# list above can suppress it -- it is project state, recorded per path in
# ~/.claude.json. And ~/.claude.json is seeded fresh from the host on every
# start (the settings cache covers ~/.claude/, a directory; this is a file
# beside it), so the booth's own "yes" is written and then discarded at
# shutdown. Left alone, the prompt returns on every single start, forever.
#
# Stamped here rather than shipped in the seeded file because the path is
# only known at run time: the code directory is wherever the booth mounted
# the project, which CODE_NAME can move.
claude_json="$HOME/.claude.json"
if command -v jq &>/dev/null; then
    # Step aside when the file is a bind mount: cache/ or shared/ owns it, and
    # a persisted copy already carries the answer across restarts. Stamping it
    # would write a booth-local path back into state the host may also read.
    if awk -v p="$claude_json" '$5 == p { found = 1 } END { exit !found }' \
        /proc/self/mountinfo 2>/dev/null; then
        :
    else
        # The code dir is the startup script's cwd; fall back for odd layouts.
        code_dir="${PWD:-}"
        case "$code_dir" in
            "$HOME"/*) ;;
            *) code_dir="$HOME/code" ;;
        esac
        # Absent when the credential extension is deselected -- still worth a
        # file, so trust survives without the host's config being seeded in.
        [ -f "$claude_json" ] || echo '{}' > "$claude_json"
        jq --arg d "$code_dir" '
            .projects[$d].hasTrustDialogAccepted = true
        ' "$claude_json" > "${claude_json}.tmp" \
            && command mv -f "${claude_json}.tmp" "$claude_json" \
            || rm -f "${claude_json}.tmp"
    fi
fi
