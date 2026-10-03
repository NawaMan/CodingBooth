#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <x.y.z|latest>]

Examples:
  $0                        # newest stable, resolved from Google's release manifest
  $0 --version 3.44.9       # a specific stable release

Notes:
- Installs to /usr/local/flutter-<version>, with /usr/local/flutter-current
  pointing at it, so the last install wins without rewriting the profile.
- Brings the Dart SDK with it: both 'flutter' and 'dart' land on PATH. Do not
  also install a standalone Dart SDK — two Darts on PATH is a version-skew trap.
- Web is ready out of the box. Android and Linux-desktop targets need extra
  pieces: see flutter-android--setup.sh and flutter-linux-desktop--setup.sh.
- Google publishes the Linux SDK for x86_64 only, so on arm64 this warns and
  skips rather than failing the build.
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ This script must be run as root (use sudo)" >&2; exit 1; }

# This script will always be installed by root.
HOME=/root

# ---- defaults / args ----
REQ_VERSION="latest"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VERSION="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

LEVEL=61                          # languages band -- see docs/BOOTH_SETUP.md
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-flutter--profile.sh"
BIN_DIR=/usr/local/bin

RELEASES_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"
BASE_URL="https://storage.googleapis.com/flutter_infra_release/releases"

# ---- arch gate ----
# Checked against Google's own manifest: every stable release carries
# dart_sdk_arch "x64" and there has never been a linux-arm64 stable build. Warn
# and skip rather than fail, so the image still comes up -- same contract as
# unsupported-arch in the template.
dpkgArch="$(dpkg --print-architecture)"
if [[ "$dpkgArch" != "amd64" ]]; then
  echo "⚠️  The Flutter SDK for Linux is published for x86_64 only."
  echo "    Host architecture is '${dpkgArch}' — skipping the Flutter install."
  exit 0
fi

# ---- base deps ----
# git is not optional: the SDK ships as a git checkout and the flutter tool
# shells out to git to work out which version it is. xz-utils unpacks the
# tarball; zip/unzip are what the tool itself reaches for when building.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  curl ca-certificates git unzip xz-utils zip
rm -rf /var/lib/apt/lists/*

# ---- resolve the version ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Resolving Flutter ${REQ_VERSION} ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "$RELEASES_URL" -o "$TMP/releases.json"

if [[ "$REQ_VERSION" == "latest" ]]; then
  # current_release.stable is a build hash, not a version -- it has to be looked
  # up in the releases list to get the version and the archive path.
  STABLE_HASH="$(jq -r '.current_release.stable' "$TMP/releases.json")"
  VERSION="$(jq -r --arg h "$STABLE_HASH" \
    'first(.releases[] | select(.hash == $h and .channel == "stable")) | .version' "$TMP/releases.json")"
  ARCHIVE="$(jq -r --arg h "$STABLE_HASH" \
    'first(.releases[] | select(.hash == $h and .channel == "stable")) | .archive' "$TMP/releases.json")"
else
  VERSION="$REQ_VERSION"
  ARCHIVE="$(jq -r --arg v "$VERSION" \
    'first(.releases[] | select(.version == $v and .channel == "stable")) | .archive' "$TMP/releases.json")"
fi

if [[ -z "$VERSION" || "$VERSION" == "null" || -z "$ARCHIVE" || "$ARCHIVE" == "null" ]]; then
  echo "❌ No stable Linux release of Flutter '${REQ_VERSION}' in Google's manifest." >&2
  echo "   Recent stable versions:" >&2
  jq -r '[.releases[] | select(.channel == "stable") | .version] | .[0:8] | join(", ")' \
    "$TMP/releases.json" >&2
  exit 1
fi

INSTALL_DIR="/usr/local/flutter-${VERSION}"

# ---- download + install ----
echo "Downloading Flutter ${VERSION} ..."
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/${ARCHIVE}" -o "$TMP/flutter.tar.xz"

echo "Installing Flutter to ${INSTALL_DIR} ..."
# The tarball unpacks to a plain 'flutter/', so extract to a scratch dir and
# move it into place under its version.
rm -rf "$INSTALL_DIR" "$TMP/unpack"
mkdir -p "$TMP/unpack"
tar -C "$TMP/unpack" -xJf "$TMP/flutter.tar.xz"
mv "$TMP/unpack/flutter" "$INSTALL_DIR"
ln -sfn "$INSTALL_DIR" /usr/local/flutter-current

# ---- git ownership ----
# The SDK is a git checkout owned by root, and the booth runs as coder, so git
# refuses it with "detected dubious ownership" and the flutter tool dies before
# it does anything. This is the whole fix; it must come before the first run.
git config --system --add safe.directory "$INSTALL_DIR"

# ---- first run + precache ----
# The tarball ships without the Dart SDK or the engine artifacts; the first
# invocation downloads them. Doing it here means a booth starts ready instead of
# stalling on a multi-hundred-megabyte download the first time anyone types
# 'flutter'.
export FLUTTER_SUPPRESS_ANALYTICS=true
echo "Fetching the Dart SDK and engine artifacts ..."
"${INSTALL_DIR}/bin/flutter" --version > /dev/null
"${INSTALL_DIR}/bin/flutter" precache --universal --web > /dev/null

# ---- login-shell env ----
export VERSION
envsubst '$VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: Flutter: $VERSION

# Prefer the "current" symlink so the last installed wins.
case ":$PATH:" in
  *":/usr/local/flutter-current/bin:"*) ;;
  *) export PATH="/usr/local/flutter-current/bin:$PATH";;
esac

# 'dart pub global activate' drops executables here.
case ":$PATH:" in
  *":$HOME/.pub-cache/bin:"*) ;;
  *) export PATH="$HOME/.pub-cache/bin:$PATH";;
esac

export FLUTTER_ROOT="/usr/local/flutter-current"

# A booth is not a machine anyone opted in from; do not phone home, and do not
# open the first-run analytics prompt in front of someone who just wants a build.
export FLUTTER_SUPPRESS_ANALYTICS=true
EOF
chmod 0644 "${PROFILE_FILE}"

# ---- non-login wrappers ----
# Build scripts and IDE tasks run in non-login shells, which never source
# profile.d -- without these, 'flutter' and 'dart' are simply not found.
install -d "$BIN_DIR" /etc/cb-flutter.d
for t in flutter dart; do
  cat >"${BIN_DIR}/$t" <<EOF
#!/bin/sh
export FLUTTER_ROOT="\${FLUTTER_ROOT:-/usr/local/flutter-current}"
export FLUTTER_SUPPRESS_ANALYTICS="\${FLUTTER_SUPPRESS_ANALYTICS:-true}"

# Per-target environment (the Android SDK root, and so on) is contributed as
# drop-ins by the add-on setups, so this wrapper does not have to know which of
# them are installed -- and so a non-login shell gets the same env a login one
# would have picked up from /etc/profile.d.
for f in /etc/cb-flutter.d/*.sh; do
  [ -r "\$f" ] && . "\$f"
done

exec /usr/local/flutter-current/bin/$t "\$@"
EOF
  chmod 755 "${BIN_DIR}/$t"
done

# ---- summary ----
# Deliberately BEFORE the permission pass below. Every `flutter` invocation can
# rewrite bin/cache -- `flutter --version` re-runs update_engine_version.sh and
# replaces engine.stamp -- and anything root touches after the chmod is left
# root-owned and 0644. That is not a cosmetic leftover: at runtime the tool
# regenerates the stamp with `mv`, which on an unwritable target *prompts*
# ("overriding mode 0644") and, with no TTY to answer, hangs forever with no
# output. So: run everything that invokes flutter first, fix modes last.
echo "✅ Flutter installed at ${INSTALL_DIR}."
echo -n "   flutter: "; "${BIN_DIR}/flutter" --version 2>/dev/null | grep -m1 . || echo "?"
# dart reports its version on stderr, so the streams have to be folded -- but
# then a plain `grep -m1 .` picks up Flutter's "you are running as root" warning
# instead of the version. Match the line that is actually wanted.
echo -n "   dart:    "; "${BIN_DIR}/dart" --version 2>&1 | grep -m1 -iE "^Dart SDK version" || echo "?"

# ---- permissions (must be last) ----
# Installed by root, used by coder -- and 'chown coder' is wrong here, because
# booth-entry remaps coder's UID to the host user's at container start, so a
# build-time owner only matches by luck. Mode bits are UID-agnostic, which is
# why the rest of the catalog (conda, code-server, cypress) does it this way.
chmod -R a+rX "$INSTALL_DIR"
# The tool writes back into its own tree at runtime: artifact downloads and
# stamps under bin/cache, a lockfile beside them, and .dart_tool for its own
# package. Read-only there turns any first use into a permission error -- or, for
# the stamp files, an unanswerable `mv` prompt.
chmod -R a+rwX "${INSTALL_DIR}/bin/cache"
chmod -R a+rwX "${INSTALL_DIR}/packages/flutter_tools"
chmod    a+rwX "$INSTALL_DIR"
echo "   Profile file (every user shell): ${PROFILE_FILE}"
echo "   Current symlink                : /usr/local/flutter-current -> ${INSTALL_DIR}"

cat <<'EON'
Ready to use:
- Start an app:   flutter create myapp && cd myapp
- Build for web:  flutter build web
- Serve it in the booth, then open it from the web pane:
      flutter run -d web-server --web-port 8080 --web-hostname 0.0.0.0
  and browse to /proxy/8080/ on the booth port.
- Android and Linux-desktop targets are separate setups:
      flutter-android, flutter-linux-desktop
EON
