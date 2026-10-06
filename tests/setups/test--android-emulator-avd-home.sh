#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: cb-android-emulator keeps the AVD where the emulator looks
#
# Clicked from the desktop, the launcher inherits the session's XDG_CONFIG_HOME.
# avdmanager then files the AVD under $XDG_CONFIG_HOME/.android, while the
# emulator only looks in ~/.android — so the first click created an AVD nothing
# could find, and the launcher died writing its recipe stamp:
#   line 163: /home/coder/.android/avd/booth.avd/.cb-recipe: No such file or directory
# A terminal or `docker exec` has no XDG_CONFIG_HOME, which is why nothing caught it.
#
# The launcher is extracted from android-emulator--setup.sh the same way
# test--android-emulator-arch-guard.sh does it, and run against a fake SDK. The
# stub avdmanager resolves its AVD home the way cmdline-tools 12 was measured to
# (ANDROID_AVD_HOME, then ANDROID_USER_HOME/avd, then XDG_CONFIG_HOME/.android/avd,
# then ~/.android/avd); the stub emulator records how it was started.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUP_SCRIPT="$REPO_ROOT/variants/base/setups/android-emulator--setup.sh"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

LAUNCHER="$WORK/cb-android-emulator"
awk '/^cat >"\$LAUNCHER" <<.LAUNCHEOF./{flag=1;next}/^LAUNCHEOF$/{flag=0}flag' \
    "$SETUP_SCRIPT" > "$LAUNCHER"
if [ ! -s "$LAUNCHER" ]; then
    echo "❌ Could not extract the LAUNCHEOF heredoc from $SETUP_SCRIPT"
    exit 1
fi

# A fake SDK with one installed system image is all the launcher reads from it.
SDK="$WORK/sdk"
mkdir -p "$SDK/system-images/android-34/default/x86_64" "$WORK/bin"
EMU_LOG="$WORK/emulator.log"

cat > "$WORK/bin/avdmanager" <<'EOF'
#!/bin/sh
cat >/dev/null   # the launcher pipes "no" into the hardware-profile prompt
home="${ANDROID_AVD_HOME:-}"
if [ -z "$home" ]; then
  if   [ -n "${ANDROID_USER_HOME:-}" ]; then home="$ANDROID_USER_HOME/avd"
  elif [ -n "${XDG_CONFIG_HOME:-}" ];   then home="$XDG_CONFIG_HOME/.android/avd"
  else                                       home="$HOME/.android/avd"
  fi
fi
[ -n "${STUB_AVD_HOME:-}" ] && home="$STUB_AVD_HOME"   # a tool that writes elsewhere
case "$1 $2" in
  "list avd")
    for ini in "$home"/*.ini; do [ -e "$ini" ] && echo "    Name: $(basename "$ini" .ini)"; done
    exit 0 ;;
  "create avd")
    shift 2
    while [ $# -gt 0 ]; do [ "$1" = "-n" ] && name="$2"; shift; done
    mkdir -p "$home/$name.avd"
    printf 'hw.keyboard=no\nhw.gpu.enabled=no\nhw.gpu.mode=auto\n' > "$home/$name.avd/config.ini"
    echo "path=$home/$name.avd" > "$home/$name.ini"
    exit 0 ;;
esac
exit 1
EOF
printf '#!/bin/sh\necho "emulator $*" >> "%s"\n' "$EMU_LOG" > "$WORK/bin/emulator"
chmod +x "$WORK/bin/avdmanager" "$WORK/bin/emulator"

ALL_PASSED=true
TEST_NUM=0
check() {
    local ok="$1" desc="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    print_test_result "$ok" "$0" "$TEST_NUM" "$desc"
    if [[ "$ok" != "true" ]]; then
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -8
        ALL_PASSED=false
    fi
}

# run_launcher <home> [VAR=value…] — the desktop session's environment, nothing
# from the host's. Empty stdin so pause_on_error's `read` never blocks.
RUN_OUT=""
RUN_EXIT=0
run_launcher() {
    local home="$1"; shift
    mkdir -p "$home"
    : > "$EMU_LOG"
    RUN_OUT=$(cd "$home" && env -i HOME="$home" USER=coder \
        PATH="$WORK/bin:/usr/bin:/bin" ANDROID_SDK_ROOT="$SDK" \
        CB_ROSETTA_MARKER="$WORK/no-rosetta" "$@" \
        bash "$LAUNCHER" 2>&1 </dev/null) && RUN_EXIT=0 || RUN_EXIT=$?
}

# ---- From the desktop: XDG_CONFIG_HOME set ----------------------------------
H="$WORK/desktop"
run_launcher "$H" XDG_CONFIG_HOME="$H/.config"
[[ "$RUN_EXIT" -eq 0 ]] \
    && check "true"  "first launch from the desktop succeeds" \
    || check "false" "first launch from the desktop succeeds" "exit=$RUN_EXIT"$'\n'"$RUN_OUT"
[[ -f "$H/.android/avd/booth.avd/.cb-recipe" ]] \
    && check "true"  "the AVD and its recipe stamp are in ~/.android, not under XDG_CONFIG_HOME" \
    || check "false" "the AVD and its recipe stamp are in ~/.android, not under XDG_CONFIG_HOME" "$(find "$H" -name '*.avd')"
[[ ! -e "$H/.config/.android" ]] \
    && check "true"  "nothing is created under \$XDG_CONFIG_HOME/.android" \
    || check "false" "nothing is created under \$XDG_CONFIG_HOME/.android"
grep -qx 'hw.keyboard=yes' "$H/.android/avd/booth.avd/config.ini" 2>/dev/null \
    && grep -qx 'hw.gpu.enabled=yes' "$H/.android/avd/booth.avd/config.ini" \
    && ! grep -q 'swiftshader_indirect' "$H/.android/avd/booth.avd/config.ini" \
    && check "true"  "the launcher's config.ini edits reached the AVD" \
    || check "false" "the launcher's config.ini edits reached the AVD" "$(cat "$H/.android/avd/booth.avd/config.ini" 2>&1)"
grep -q -- '-avd booth' "$EMU_LOG" \
    && check "true"  "the emulator is started on that AVD" \
    || check "false" "the emulator is started on that AVD" "$(cat "$EMU_LOG")"

# ---- A home the user chose wins ---------------------------------------------
H="$WORK/custom"
run_launcher "$H" XDG_CONFIG_HOME="$H/.config" ANDROID_USER_HOME="$H/android-home"
[[ "$RUN_EXIT" -eq 0 && -f "$H/android-home/avd/booth.avd/.cb-recipe" && ! -e "$H/.android" ]] \
    && check "true"  "an ANDROID_USER_HOME set by the user is kept" \
    || check "false" "an ANDROID_USER_HOME set by the user is kept" "exit=$RUN_EXIT"$'\n'"$(find "$H" -name '*.avd')"

# ---- avdmanager reports success but writes elsewhere ------------------------
H="$WORK/elsewhere"
run_launcher "$H" STUB_AVD_HOME="$H/somewhere-else"
[[ "$RUN_EXIT" -ne 0 ]] && grep -qF "avdmanager did not create the AVD in $H/.android/avd" <<< "$RUN_OUT" \
    && check "true"  "an AVD that lands elsewhere is reported, with where it was expected" \
    || check "false" "an AVD that lands elsewhere is reported, with where it was expected" "exit=$RUN_EXIT"$'\n'"$RUN_OUT"

$ALL_PASSED || exit 1
