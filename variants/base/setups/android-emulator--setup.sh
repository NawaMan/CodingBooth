#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--api <level>] [--tag <default|google_apis>] [--abi <x86_64>] [--no-image]

Examples:
  $0                          # emulator + system-images;android-34;default;x86_64
  $0 --api 35                 # a different API level
  $0 --tag google_apis        # an image carrying Play services (much larger)
  $0 --no-image               # the emulator binary only, bring your own image

Notes:
- Requires android-sdk--setup.sh to have run first (this uses its sdkmanager).
- 'default' rather than 'google_apis': nothing in a plain booth needs Play
  services, and it is a substantially smaller image.
- A system image is multiple GB. This is why the emulator is a separate setup
  from the SDK rather than part of it.
- KVM is a RUNTIME concern, not a build one. Without /dev/kvm the emulator
  refuses to start outright; pass '-accel off' to fall back to software
  emulation. See the booth's kvm run-args for the fast path.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ This script must be run as root (use sudo)" >&2; exit 1; }

HOME=/root

# ---- defaults / args ----
ANDROID_API="34"
IMAGE_TAG="default"
IMAGE_ABI="x86_64"
WITH_IMAGE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --api)      shift; ANDROID_API="${1:-}"; shift ;;
    --tag)      shift; IMAGE_TAG="${1:-}";   shift ;;
    --abi)      shift; IMAGE_ABI="${1:-}";   shift ;;
    --no-image) WITH_IMAGE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

SDK_ROOT=/opt/android-sdk
SDKMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
BIN_DIR=/usr/local/bin

# ---- arch gate ----
# The Linux emulator is published for x86_64 only. Warn and skip so the image
# still builds, matching android-sdk--setup.sh.
dpkgArch="$(dpkg --print-architecture)"
if [[ "$dpkgArch" != "amd64" ]]; then
  echo "⚠️  The Android emulator is published for linux x86_64 only."
  echo "    Host architecture is '${dpkgArch}' — skipping the emulator install."
  exit 0
fi

# ---- prerequisite ----
if [[ ! -x "$SDKMANAGER" ]]; then
  echo "❌ sdkmanager not found at ${SDKMANAGER}." >&2
  echo "   Run 'setup android-sdk' before 'setup android-emulator'." >&2
  exit 1
fi

# ---- runtime libraries ----
# The emulator binary links against X11, GL and audio even with -no-window, so a
# headless run still needs the client libraries present. Without them it dies at
# load time with a missing-shared-object error, long before any AVD is read.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  libx11-6 libxcb1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 \
  libxrandr2 libxrender1 libxtst6 libgl1 libpulse0 libnss3 libxkbfile1
# libasound2 and libpng16-16 were renamed with a t64 suffix in the 64-bit-time_t
# transition; which name exists depends on the base image's Ubuntu release.
apt-get install -y --no-install-recommends libasound2t64 \
  || apt-get install -y --no-install-recommends libasound2 \
  || true
# libpng16 and libxkbfile are pulled in by the Qt libraries the emulator bundles.
# Missing them is easy to overlook because a plain `-no-window` boot still works —
# it is `emulator -version` and anything touching the UI path that dies with
# "libpng16.so.16: cannot open shared object file".
apt-get install -y --no-install-recommends libpng16-16t64 \
  || apt-get install -y --no-install-recommends libpng16-16 \
  || true
rm -rf /var/lib/apt/lists/*

# ---- emulator + system image ----
if [[ $WITH_IMAGE -eq 1 ]]; then
  SYSTEM_IMAGE="system-images;android-${ANDROID_API};${IMAGE_TAG};${IMAGE_ABI}"
  echo "Installing emulator and ${SYSTEM_IMAGE} (this is a large download) ..."
  "$SDKMANAGER" --install "emulator" "$SYSTEM_IMAGE" > /dev/null
else
  echo "Installing emulator ..."
  "$SDKMANAGER" --install "emulator" > /dev/null
fi

chmod -R a+rX "$SDK_ROOT"

# ---- login-shell env ----
cat >/etc/profile.d/64-cb-android-emulator--profile.sh <<EOF
# Android emulator under the SDK root
export PATH="\${ANDROID_SDK_ROOT:-${SDK_ROOT}}/emulator:\$PATH"
EOF
chmod 0644 /etc/profile.d/64-cb-android-emulator--profile.sh

# ---- non-login wrappers ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/emulatorwrap" <<'EOF'
#!/bin/sh
: "${ANDROID_SDK_ROOT:=/opt/android-sdk}"
tool="$(basename "$0")"
if [ -x "$ANDROID_SDK_ROOT/emulator/$tool" ]; then
  exec "$ANDROID_SDK_ROOT/emulator/$tool" "$@"
fi
echo "$tool: not found in the Android emulator at $ANDROID_SDK_ROOT/emulator" >&2
exit 127
EOF
chmod +x "${BIN_DIR}/emulatorwrap"
ln -sfn "${BIN_DIR}/emulatorwrap" "${BIN_DIR}/emulator"

# ---- desktop launcher ----
# A bare `emulator` with no AVD does nothing useful, so the launcher creates one
# on first run rather than making the icon a trap. It also picks the acceleration
# mode, because the emulator does not fall back on its own — without KVM it exits
# with "x86_64 emulation currently requires hardware acceleration!" instead of
# running slowly, which from a double-clicked icon would look like nothing
# happened at all.
LAUNCHER="${BIN_DIR}/cb-android-emulator"
cat >"$LAUNCHER" <<'LAUNCHEOF'
#!/bin/bash
# Launch the Android emulator, creating a default AVD the first time.
# Generated by android-emulator--setup.sh.

set -Eeuo pipefail

SDK_ROOT="${ANDROID_SDK_ROOT:-/opt/android-sdk}"
AVD_NAME="${CB_AVD_NAME:-booth}"
AVD_DEVICE="${CB_AVD_DEVICE:-pixel_6}"

# Launched from a desktop icon there is no DISPLAY in the environment.
export DISPLAY="${DISPLAY:-:1}"

# Keep a failure readable when this runs in its own terminal window, which would
# otherwise close the instant the emulator exits.
pause_on_error() {
  echo ""
  echo "The emulator exited with an error. Press Enter to close this window."
  read -r _
}
trap pause_on_error ERR

# When this container's own architecture doesn't match the physical CPU under it
# (e.g. an amd64 booth forced with --platform on Apple Silicon), every process
# in it — including this one — is transparently re-executed through a foreign-
# arch translator. That is normally invisible, but the emulator embeds its own
# QEMU-based hypervisor plus a Qt GUI, both of which make low-level syscalls
# (thread/futex extensions, ptrace) that neither translation backend fully
# implements — confirmed here as three distinct failures: an unimplemented-
# syscall abort under Rosetta, a ptrace ENOSYS abort under QEMU, and a hang
# resolving the virtual modem's address in between. It does not just run slowly
# under a second layer of translation, it does not run at all, so this is worth
# catching before spending a minute creating an AVD and booting toward a crash.
#
# This deliberately does not try to name which backend (Rosetta vs QEMU) is
# active: from inside the container the two are indistinguishable. binfmt_misc
# is not exposed to the container at all under either one (confirmed: the
# directory itself does not exist), and `ps aux` shows every process wrapped in
# a literal /usr/bin/qemu-x86_64 interpreter under BOTH — that name is Docker
# Desktop's generic label for cross-arch translation, not evidence of which
# engine is doing it. /sys/module/rosetta is the only signal that held up under
# direct testing, but it stayed present even after switching Docker Desktop's
# setting to QEMU and restarting, so it only proves "this Mac's Docker Desktop
# has cross-arch translation available," not which engine is currently active —
# which, for deciding whether the emulator can run, is the only thing that
# actually matters.
# CB_ROSETTA_MARKER overrides the path checked, purely so
# tests/setups/test--android-emulator-arch-guard.sh can simulate both states
# hermetically — normal runs never set it, so this checks the real path.
detect_cpu_translation() {
  [ -e "${CB_ROSETTA_MARKER:-/sys/module/rosetta}" ]
}

if detect_cpu_translation; then
  # A project can opt into naming its own real-device helper here rather than
  # this shared script guessing at one — only mentioned when it actually
  # exists, since this launcher is shared by projects that may not have one.
  DEVICE_CONNECT_SCRIPT=""
  for candidate in "$PWD/device-connect.sh" "$HOME/code/device-connect.sh"; do
    if [ -x "$candidate" ]; then
      DEVICE_CONNECT_SCRIPT="$candidate"
      break
    fi
  done

  cat <<EOM
❌ The Android emulator cannot run here.

This container's own architecture doesn't match the real CPU underneath it —
every process, including this one, is being transparently re-executed through
Docker Desktop's amd64-on-Apple-Silicon translation.

Building and signing an APK is unaffected by this, and so is testing on a REAL
device over adb — only the emulator's own embedded hypervisor and GUI hit
syscalls this translation cannot provide. This is a structural limitation of
running amd64 under translation on Apple Silicon, not something a flag here
can fix.
EOM

  if [ -n "$DEVICE_CONNECT_SCRIPT" ]; then
    cat <<EOM

Pair and connect to a real device instead:
  $DEVICE_CONNECT_SCRIPT <ip> <pairing-port> <pairing-code> [connect-port]
EOM
  else
    cat <<EOM

If this project's example ships a real-device helper script, check its README
for details on the confirmed failure modes and how to use it.
EOM
  fi

  cat <<EOM

Set CB_ANDROID_EMULATOR_FORCE=1 to attempt it anyway.
EOM
  if [ "${CB_ANDROID_EMULATOR_FORCE:-0}" != "1" ]; then
    pause_on_error
    exit 1
  fi
  echo ""
  echo "CB_ANDROID_EMULATOR_FORCE=1 is set — attempting to launch anyway ..."
fi

# Derive the package spec from whatever image is actually installed, so this
# keeps working when the booth is configured for a different API level:
#   /opt/android-sdk/system-images/android-34/default/x86_64
#     -> system-images;android-34;default;x86_64
IMAGE_PATH="$(ls -d "$SDK_ROOT"/system-images/*/*/* 2>/dev/null | sort | tail -n1)"
if [ -z "$IMAGE_PATH" ]; then
  echo "No Android system image is installed in $SDK_ROOT."
  echo "Reconfigure the booth with the +emulator extension to add one."
  exit 1
fi
SYSTEM_IMAGE="system-images;$(basename "$(dirname "$(dirname "$IMAGE_PATH")")");$(basename "$(dirname "$IMAGE_PATH")");$(basename "$IMAGE_PATH")"

# How this AVD was built. Bump whenever the recipe below changes in a way an
# existing AVD would not pick up — a new device profile, a new config.ini key.
AVD_RECIPE="2:${AVD_DEVICE}:${SYSTEM_IMAGE}"
STAMP="$HOME/.android/avd/${AVD_NAME}.avd/.cb-recipe"

AVD_EXISTS=0
avdmanager list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}$" && AVD_EXISTS=1

# "Create only when absent" is fine while ~/.android is ephemeral, but the
# avd-cache extension makes it permanent — and then an AVD built by an older,
# buggier launcher would survive every fix forever. That is not hypothetical:
# AVDs created before the device profile landed have hw.mainKeys=yes and no
# usable Back/Home button, and would never have been rebuilt. So compare the
# recipe and start over when it has moved on.
if [ "$AVD_EXISTS" = 1 ] && [ "$(cat "$STAMP" 2>/dev/null)" != "$AVD_RECIPE" ]; then
  echo "AVD '${AVD_NAME}' was built by an older launcher recipe — recreating it."
  echo "  (device state is lost; that is the cost of picking up the fix)"
  avdmanager delete avd -n "$AVD_NAME" >/dev/null 2>&1 || true
  rm -rf "$HOME/.android/avd/${AVD_NAME}.avd" "$HOME/.android/avd/${AVD_NAME}.ini"
  AVD_EXISTS=0
fi

if [ "$AVD_EXISTS" = 0 ]; then
  echo "Creating AVD '${AVD_NAME}' from ${SYSTEM_IMAGE} (first run only) ..."
  # -d is not optional in practice. With no device profile avdmanager writes
  # hw.mainKeys=yes, which means "this device has physical Back/Home keys, so do
  # not draw the on-screen navigation bar" — and an emulator window has no
  # physical keys, so there is then no way to press Back or Home at all. It also
  # defaults to a 320x640 mdpi screen, far smaller than anything Android 14's
  # system UI expects. A real device profile fixes both.
  echo no | avdmanager create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" -d "$AVD_DEVICE" >/dev/null
  CONFIG="$HOME/.android/avd/${AVD_NAME}.avd/config.ini"
  if [ -f "$CONFIG" ]; then
    # avdmanager has no flag for these, so set them in the config it just wrote.
    # hw.keyboard=no means the host keyboard does not reach the guest — you can
    # tap but not type, which is its own kind of stuck.
    sed -i 's/^hw\.keyboard=.*/hw.keyboard=yes/' "$CONFIG"
    grep -q '^hw\.keyboard=' "$CONFIG" || echo 'hw.keyboard=yes' >> "$CONFIG"
    # There is no GPU in a booth; naming the software rasterizer here is more
    # predictable than letting "auto" probe and fall back.
    sed -i 's/^hw\.gpu\.enabled=.*/hw.gpu.enabled=yes/' "$CONFIG"
    sed -i 's/^hw\.gpu\.mode=.*/hw.gpu.mode=swiftshader_indirect/' "$CONFIG"
  fi
  # Written last, so an interrupted creation leaves no stamp and is retried
  # rather than mistaken for a current AVD.
  printf '%s\n' "$AVD_RECIPE" > "$STAMP"
  echo "AVD created (${AVD_DEVICE}, on-screen navigation bar, hardware keyboard)."
fi

# Clear locks left by a previous run. The emulator records a running instance in
# avd/running/ and takes .lock files beside the AVD; when the process dies with
# the container none of that is cleaned up, and the next start refuses with
# "A snapshot operation for 'booth' is pending and timeout has expired" — a dead
# emulator holding the door shut. Harmless without the avd-cache extension
# (nothing survives to be stale), and essential with it: every container exit is
# an unclean exit as far as the emulator is concerned.
if ! pgrep -f "qemu-system-x86_64.*${AVD_NAME}" >/dev/null 2>&1; then
  rm -rf "$HOME/.android/avd/running"
  find "$HOME/.android/avd/${AVD_NAME}.avd" -maxdepth 1 -name "*.lock" -exec rm -rf {} + 2>/dev/null || true
fi

ACCEL_ARGS=()
if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
  echo "KVM is available — starting hardware-accelerated."
else
  echo "No usable /dev/kvm — starting in software emulation (much slower to boot)."
  echo "For hardware acceleration, reconfigure the booth with the +kvm extension"
  echo "on a Linux host that has /dev/kvm."
  ACCEL_ARGS=(-accel off -gpu swiftshader_indirect)
fi

echo "Starting the emulator. The window may take a minute to appear."
exec emulator -avd "$AVD_NAME" "${ACCEL_ARGS[@]}" "$@"
LAUNCHEOF
chmod +x "$LAUNCHER"

# Stopping the emulator is not symmetrical with starting it. The emulator does
# not reliably write a Quick Boot snapshot on its own way out — measured here,
# neither `adb emu kill` nor a SIGTERM leaves one behind, so the next start
# restores whatever snapshot was last written and silently rolls back everything
# since. An explicit save first is what makes device state actually persist
# (see the avd-cache extension).
STOPPER="${BIN_DIR}/cb-android-emulator-stop"
cat >"$STOPPER" <<'STOPEOF'
#!/bin/bash
# Stop the Android emulator, saving its state first.
# Generated by android-emulator--setup.sh.

set -uo pipefail

if ! adb devices 2>/dev/null | grep -q "emulator-.*device$"; then
  echo "No running emulator found."
  exit 0
fi

# Only worth saving when the AVD is persisted; otherwise it is 2+ GB written to
# a directory that disappears with the container.
if [ -d "$HOME/.android/avd" ] && mountpoint -q "$HOME/.android" 2>/dev/null; then
  SAVE=1
else
  SAVE="${CB_AVD_SAVE_STATE:-0}"
fi

if [ "$SAVE" = "1" ]; then
  echo "Saving device state (this writes a multi-GB snapshot) ..."
  adb emu avd snapshot save default_boot >/dev/null 2>&1 \
    && echo "State saved — the next start restores it in a few seconds." \
    || echo "⚠️  Snapshot save failed; the next start will be a cold boot."
else
  echo "AVD is not cached, so device state is not saved."
  echo "Add the avd-cache extension to keep it across restarts."
fi

adb emu kill >/dev/null 2>&1
echo "Emulator stopped."
STOPEOF
chmod +x "$STOPPER"

# The emulator ships no application icon of its own (only scene textures), so
# draw a simple device glyph rather than leaving the launcher iconless.
ICON_DIR=/usr/share/icons/hicolor/scalable/apps
ICON_FILE="${ICON_DIR}/cb-android-emulator.svg"
mkdir -p "$ICON_DIR"
cat >"$ICON_FILE" <<'ICONEOF'
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <rect x="16" y="4" width="32" height="56" rx="5" fill="#37474f"/>
  <rect x="20" y="11" width="24" height="38" rx="2" fill="#a5d6a7"/>
  <circle cx="32" cy="55" r="2.6" fill="#90a4ae"/>
  <g fill="#37474f">
    <circle cx="27" cy="26" r="2"/>
    <circle cx="37" cy="26" r="2"/>
    <rect x="25" y="33" width="14" height="3" rx="1.5"/>
  </g>
</svg>
ICONEOF
chmod 644 "$ICON_FILE"

# /usr/share/applications is the start menu; cb-desktop-icon.sh additionally puts
# it on the desktop. Categories places it under Development.
DESKTOP_FILE=/usr/share/applications/cb-android-emulator.desktop
cat >"$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Android Emulator
GenericName=Android Virtual Device
Comment=Start the Android emulator (creates a default AVD on first run)
Exec=${LAUNCHER}
Icon=${ICON_FILE}
Terminal=true
Categories=Development;Emulator;
Keywords=android;emulator;avd;adb;mobile;
StartupNotify=true
EOF
chmod 644 "$DESKTOP_FILE"
update-desktop-database /usr/share/applications 2>/dev/null || true

# Register the desktop icon (no-ops on non-desktop variants).
cb-desktop-icon.sh cb-android-emulator.desktop || true

# ---- summary ----
echo "Android emulator installed under ${SDK_ROOT}/emulator."
# See android-sdk--setup.sh: first non-empty line, both streams folded in.
echo -n "   emulator: "; "${BIN_DIR}/emulator" -version 2>&1 | grep -m1 . || echo "?"
if [[ $WITH_IMAGE -eq 1 ]]; then
  echo "   system image: ${SYSTEM_IMAGE}"
fi

cat <<'EON'
Ready to use:
- On a desktop variant: the "Android Emulator" icon / Development menu entry
  (creates an AVD named "booth" on first run and picks the acceleration mode)
- By hand: cb-android-emulator
- Or fully manual:
    avdmanager create avd -n dev -k "system-images;android-34;default;x86_64"
    emulator -avd dev -no-window                            # with /dev/kvm
    emulator -avd dev -no-window -accel off -gpu swiftshader_indirect   # without
EON
