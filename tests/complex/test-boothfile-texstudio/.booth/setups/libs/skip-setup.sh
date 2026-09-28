#!/usr/bin/env bash
# skip-setup.sh — Helper for setup scripts to handle N/A conditions
#
# When a setup script's prerequisites aren't met (wrong variant, missing dependency),
# this function prints a skip message and exits with an appropriate code:
#   - In Dockerfile (no TTY): exit 0 (build continues smoothly)
#   - Interactive (has TTY): exit 42 (signals N/A to caller)
#
# Usage:
#   source "$SCRIPT_DIR/libs/skip-setup.sh"
#   skip_setup "script-name" "reason for skipping"
#
# Example:
#   if ! "$SCRIPT_DIR/cb-has-vscode.sh"; then
#       skip_setup "$SCRIPT_NAME" "code-server/VSCode not installed"
#   fi

skip_setup() {
    local script_name="${1:-setup}"
    local reason="${2:-prerequisite not met}"

    echo "SKIP: ${script_name} - ${reason}" >&2

    # Detect Dockerfile build context: no TTY on stdin or stdout
    if [[ -t 0 ]] || [[ -t 1 ]]; then
        # Interactive (has TTY) - return 42 to signal N/A
        exit 42
    else
        # Dockerfile build (no TTY) - return 0 so build continues
        exit 0
    fi
}
