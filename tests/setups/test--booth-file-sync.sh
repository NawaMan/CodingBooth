#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: booth--file-sync, which keeps single Cache/Shared files rename-safe.
#
# The CLI stages such a file under /var/lib/codingbooth/file-sync/<path>;
# `init` copies it to <path>, and the watcher copies back whichever side
# changed. Here it runs on a copy with the staging root and the target root
# pointed into a temp dir (the real paths are not overridable on purpose: init
# runs as root). `once` is one watcher pass, so each direction is checked
# without a background loop. chown is stubbed: the test is not root.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SYNC_SRC="$REPO_ROOT/variants/base/booth--file-sync"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

STAGE="$WORK/stage"
TARGET="$WORK/target"
SYNC="$WORK/booth--file-sync"
sed -e "s|^ROOT=\"/var/lib/codingbooth/file-sync\"$|ROOT=\"$STAGE\"|" \
    -e "s|^TARGET_ROOT=\"\"$|TARGET_ROOT=\"$TARGET\"|" "$SYNC_SRC" > "$SYNC"
chmod +x "$SYNC"
if ! grep -q "^ROOT=\"$STAGE\"$" "$SYNC" || ! grep -q "^TARGET_ROOT=\"$TARGET\"$" "$SYNC"; then
    echo "❌ Could not point booth--file-sync at test paths (its ROOT/TARGET_ROOT lines may have changed)"
    exit 1
fi

mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/chown"
chmod +x "$WORK/bin/chown"
export PATH="$WORK/bin:$PATH"

FAILED=0
check() { # number, description, expected, actual
    if [[ "$3" == "$4" ]]; then
        print_test_result "true" "$0" "$1" "$2"
    else
        print_test_result "false" "$0" "$1" "$2"
        echo "  Expected: $3"
        echo "  Actual:   $4"
        FAILED=$((FAILED + 1))
    fi
}

H=home/coder
mkdir -p "$STAGE/$H/.config" "$TARGET/$H"
echo "HOST_HISTORY" > "$STAGE/$H/.zsh_history"
chmod 600 "$STAGE/$H/.zsh_history"
echo "HOST_SHORTCUTS" > "$STAGE/$H/.config/shortcuts.xml"
# A symlink left at a target must be replaced, never written through.
echo "DO_NOT_TOUCH" > "$WORK/elsewhere"
ln -s "$WORK/elsewhere" "$TARGET/$H/.zsh_history"

"$SYNC" init

check 1 "init: copies a staged file to its path" "HOST_HISTORY" "$(cat "$TARGET/$H/.zsh_history")"
check 2 "init: creates missing parent folders" "HOST_SHORTCUTS" "$(cat "$TARGET/$H/.config/shortcuts.xml")"
check 3 "init: replaces a symlink instead of writing through it" "DO_NOT_TOUCH|regular" \
    "$(cat "$WORK/elsewhere")|$([ -L "$TARGET/$H/.zsh_history" ] && echo link || echo regular)"
check 4 "init: keeps the staged file's mode" "600" "$(stat -c '%a' "$TARGET/$H/.zsh_history")"

# The case this exists for: a tool saves by writing a new file and renaming it.
echo "SAVED_BY_RENAME" > "$TARGET/$H/.zsh_history.new"
mv "$TARGET/$H/.zsh_history.new" "$TARGET/$H/.zsh_history"
"$SYNC" once
check 5 "once: a rename-saved file is copied back to the staged file" "SAVED_BY_RENAME" "$(cat "$STAGE/$H/.zsh_history")"

# A host-side edit (an editor, a git pull) with the booth side unchanged comes in.
# Needs the watcher's memory of the last sync, so it runs as watch.
cp "$STAGE/$H/.config/shortcuts.xml" "$TARGET/$H/.config/shortcuts.xml"
BOOTH_FILE_SYNC_INTERVAL=1 "$SYNC" watch &
pid=$!
sleep 1
echo "HOST_EDIT" > "$STAGE/$H/.config/shortcuts.xml"
sleep 2
kill -TERM "$pid"
wait "$pid" || true
check 6 "watch: an edit on the host side reaches the booth" "HOST_EDIT" "$(cat "$TARGET/$H/.config/shortcuts.xml")"

# A tool that deleted its file gives nothing back: the host copy survives.
rm "$TARGET/$H/.zsh_history"
"$SYNC" once
check 7 "once: a deleted target leaves the staged file alone" "SAVED_BY_RENAME" "$(cat "$STAGE/$H/.zsh_history")"

# watch flushes on TERM, so a stop right after a save loses nothing.
echo "BEFORE_STOP" > "$TARGET/$H/.config/shortcuts.xml.tmp"
BOOTH_FILE_SYNC_INTERVAL=30 "$SYNC" watch &
pid=$!
sleep 1
mv "$TARGET/$H/.config/shortcuts.xml.tmp" "$TARGET/$H/.config/shortcuts.xml"
kill -TERM "$pid"
wait "$pid" || true
check 8 "watch: copies once more on TERM" "BEFORE_STOP" "$(cat "$STAGE/$H/.config/shortcuts.xml")"

# Nothing staged: watch exits at once rather than idling.
rm -rf "$STAGE"
if timeout 5 "$SYNC" watch; then rc=0; else rc=$?; fi
check 9 "watch: exits when nothing is staged" "0" "$rc"

exit $FAILED
