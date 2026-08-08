#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# flutter-linux-desktop--setup.sh
# Adds the native toolchain and GTK headers Flutter's Linux desktop target
# compiles against, so `flutter build linux` works and `flutter doctor` stops
# reporting the Linux toolchain as incomplete.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Run after flutter--setup.sh; skips cleanly if Flutter is absent.
- A built Linux app is a GUI binary: it needs a desktop variant (or an X server
  on DISPLAY) to actually run. It still *builds* on the base variant.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ This script must be run as root (use sudo)" >&2; exit 1; }

# This script will always be installed by root.
HOME=/root

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(dirname "$0")"

# A script copied into a project's .booth/setups/ shadows the image's copy, but
# libs/ does not come with it -- so $SCRIPT_DIR/libs is simply absent on the very
# path the dev loop and the complex tests use.
SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
if [[ -r "$SCRIPT_DIR/libs/skip-setup.sh" ]]; then
    source "$SCRIPT_DIR/libs/skip-setup.sh"
else
    source "${SETUP_LIBS_DIR}/skip-setup.sh"
fi

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
esac

# ---- guard ----
if ! command -v flutter >/dev/null 2>&1; then
  skip_setup "$SCRIPT_NAME" "Flutter not installed (run flutter--setup.sh first)"
fi

export FLUTTER_SUPPRESS_ANALYTICS=true

# ---- toolchain ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libglu1-mesa

# Flutter's own docs name libstdc++-12-dev, but the package is tied to the
# distro's default GCC -- 24.04 ships 13, and older/newer bases ship something
# else. Take whichever exists rather than pinning a number that rots.
libstdcxx_dev=""
for v in 14 13 12; do
  if apt-cache show "libstdc++-${v}-dev" >/dev/null 2>&1; then
    libstdcxx_dev="libstdc++-${v}-dev"
    break
  fi
done
if [[ -n "$libstdcxx_dev" ]]; then
  apt-get install -y --no-install-recommends "$libstdcxx_dev"
else
  echo "⚠️  No libstdc++-*-dev found in apt; C++ headers may be incomplete."
fi
rm -rf /var/lib/apt/lists/*

# ---- engine artifacts ----
echo "Fetching the Flutter Linux desktop engine artifacts ..."
flutter precache --linux > /dev/null

# ---- summary ----
echo "✅ Flutter Linux desktop toolchain installed."
echo -n "   clang: "; clang --version 2>/dev/null | grep -m1 . || echo "?"
echo -n "   cmake: "; cmake --version 2>/dev/null | grep -m1 . || echo "?"

# ---- permissions (must be last) ----
# precache wrote into the SDK tree as root; re-open it for the booth user. Kept
# last on purpose: any root-run flutter command after this point would leave
# freshly written cache files root-owned and 0644, and the tool's runtime `mv`
# over such a file prompts and hangs with no output.
FLUTTER_DIR="$(readlink -f /usr/local/flutter-current)"
chmod -R a+rwX "${FLUTTER_DIR}/bin/cache"

cat <<'EON'
Ready to use:
- Build a Linux app:  flutter build linux
- Run it (needs a desktop variant, or DISPLAY set):
      flutter run -d linux
EON
