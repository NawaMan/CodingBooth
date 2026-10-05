#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# tty-owner: give the booth user ownership of their own terminal device.
#
# The foreground shell of `booth run` gets its pty from `docker run -it` while the container is still
# root; booth-entry then drops to the user with `runuser`, which keeps that terminal. So the user's
# shell sits on a pty owned root:tty, mode 0620: it can write to it but not read from it. Anything
# that opens the terminal by name then fails with "Permission denied" — notably gpg's passphrase
# prompt (pinentry, via $GPG_TTY), which breaks `gpg --quick-generate-key`, `pass show`, and so on.
# (`booth shell` is unaffected: `docker exec -it -u coder` allocates the pty as the user.)
#
# Build time (this script, as root): install a profile script. Run time (each login shell, as the
# user): if the shell's terminal isn't owned by the user, `sudo chown` it to them.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

LEVEL=54                          # Core base range (50-54): must run before anything uses the tty
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-tty-owner--profile.sh"

mkdir -p -- "$(dirname -- "$PROFILE_FILE")"

# Sourced by every login shell (possibly sh, not bash) — POSIX only, fast, and never fails the
# shell: no network, no set -e, every failure swallowed.
cat > "$PROFILE_FILE" <<'EOF'
# Profile: tty-owner — make the user own this shell's terminal (see setup script).
_cb_tty=$(tty 2>/dev/null) || _cb_tty=
case $_cb_tty in
    /dev/pts/*)
        # Ownership, not [ -r ]/[ -w ]: those can pass while pinentry still gets EACCES.
        if [ "$(stat -c %u "$_cb_tty" 2>/dev/null)" != "$(id -u)" ]; then
            sudo -n chown "$(id -un)" "$_cb_tty" 2>/dev/null || true
        fi
        ;;
esac
unset _cb_tty
EOF
chmod 644 "$PROFILE_FILE"

echo "✅ tty-owner profile installed: ${PROFILE_FILE}"
