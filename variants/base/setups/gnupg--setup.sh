#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# gnupg--setup.sh — Build GnuPG 2.5 from the upstream release into /usr/local,
# so it shadows Ubuntu's gpg on PATH.
#
# Ubuntu 26.04 ships GnuPG 2.4, a series that has reached its upstream end of
# life; 2.5 is the stable line and adds post-quantum (Kyber / ML-KEM) keys.
# Ubuntu's 2.4 packages stay installed: apt and other packages depend on them,
# and only the binaries on PATH change. 26.04's own libgpg-error, libgcrypt,
# libassuan, libksba and npth are new enough, so only GnuPG itself is built.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>]

Examples:
  $0                       # GnuPG ${GNUPG_DEFAULT_VER:-2.5.24}
  $0 --version 2.5.24      # pin a release

Notes:
- Installs gpg, gpg-agent, gpgconf, dirmngr, ... to /usr/local/bin
- Checks the release signature against the GnuPG release keys, and the
  default version's tarball against its pinned SHA256
- Build tools and -dev packages are removed again after the build
USAGE
}

# ---- defaults / args ----
GNUPG_DEFAULT_VER="2.5.24"
GNUPG_DEFAULT_SHA256="bf149d01a2b9fcc0e4589b8ae8697d3d5c557ea48ed95a3fa55dd3b1187e6039"
VERSION="$GNUPG_DEFAULT_VER"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; VERSION="${1:-}"; shift || true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "❌ Not a GnuPG version: '${VERSION}' (expected X.Y.Z, for example ${GNUPG_DEFAULT_VER})" >&2
  exit 2
fi

# Release signing keys, from https://gnupg.org/signature_key.html. Fixed here
# rather than trusted from the download server, which also serves the tarball.
RELEASE_KEYS=(
  6DAA6E64A76D2840571B4902528897B826403ADA   # Werner Koch (dist signing 2020)
  AC8E115BF73E2D8D47FA9908E98E9B2D19C6C8BD   # NIIBE Yutaka (GnuPG Release Key)
)

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

SETUPS_DIR="$(dirname "$0")"
[ -x "${SETUPS_DIR}/apt--install.sh" ] || SETUPS_DIR=/opt/codingbooth/setups

BUILD_DEPS=(
  bzip2 ca-certificates curl gcc make pkgconf
  libgpg-error-dev libgcrypt20-dev libassuan-dev libksba-dev libnpth0-dev
  libgnutls28-dev libsqlite3-dev libbz2-dev zlib1g-dev libreadline-dev libldap-dev
)

# Everything installed only for the build is removed after it: list what is
# already there, so only the packages this run adds are candidates.
BEFORE=$(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' | awk '$1 == "ii" { print $2 }' | LC_ALL=C sort -u)

echo "⬇️  Installing GnuPG ${VERSION} build dependencies ..."
"${SETUPS_DIR}/apt--install.sh" "${BUILD_DEPS[@]}"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

URL="https://gnupg.org/ftp/gcrypt/gnupg/gnupg-${VERSION}.tar.bz2"
echo "⬇️  Downloading ${URL} ..."
for f in "gnupg-${VERSION}.tar.bz2" "gnupg-${VERSION}.tar.bz2.sig"; do
  if ! curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${URL%/*}/${f}" -o "$TMP/$f"; then
    echo "❌ Download failed: ${URL%/*}/${f}" >&2
    exit 1
  fi
done

if [[ "$VERSION" == "$GNUPG_DEFAULT_VER" ]]; then
  ACTUAL="$(sha256sum "$TMP/gnupg-${VERSION}.tar.bz2" | awk '{ print $1 }')"
  if [[ "$ACTUAL" != "$GNUPG_DEFAULT_SHA256" ]]; then
    echo "❌ SHA256 mismatch for gnupg-${VERSION}.tar.bz2 (expected '${GNUPG_DEFAULT_SHA256}', got '${ACTUAL}')" >&2
    exit 1
  fi
fi

# Verify with the gpg already in the image (Ubuntu's 2.4) in a throwaway home.
# The key file comes from the server, so a signature only counts when its
# primary key is one of RELEASE_KEYS.
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL https://gnupg.org/signature_key.asc -o "$TMP/keys.asc"
mkdir -m 700 "$TMP/gnupghome"
gpg --batch --quiet --homedir "$TMP/gnupghome" --import "$TMP/keys.asc" 2>/dev/null || true
STATUS=$(gpg --batch --homedir "$TMP/gnupghome" --status-fd 1 \
           --verify "$TMP/gnupg-${VERSION}.tar.bz2.sig" "$TMP/gnupg-${VERSION}.tar.bz2" 2>/dev/null || true)
SIGNED_BY=$(awk '$2 == "VALIDSIG" { print $NF }' <<< "$STATUS")
TRUSTED=""
for fpr in $SIGNED_BY; do
  for key in "${RELEASE_KEYS[@]}"; do
    [[ "$fpr" == "$key" ]] && TRUSTED="$fpr"
  done
done
if [[ -z "$TRUSTED" ]]; then
  echo "❌ gnupg-${VERSION}.tar.bz2 has no valid signature from a GnuPG release key; refusing to build it." >&2
  exit 1
fi
echo "🔏 Signature good (${TRUSTED})"

echo "🔨 Building GnuPG ${VERSION} ..."
tar -xjf "$TMP/gnupg-${VERSION}.tar.bz2" -C "$TMP"
# --with-pinentry-pgm keeps gpg-agent on /usr/bin/pinentry, the alternative
# that pinentry--setup.sh repoints at a desktop flavour; the default would be
# /usr/local/bin/pinentry, which nothing provides.
# The compiler's warnings go to a log, shown only when the build fails.
if ! ( cd "$TMP/gnupg-${VERSION}" \
       && ./configure --prefix=/usr/local --sysconfdir=/etc --localstatedir=/var \
            --with-pinentry-pgm=/usr/bin/pinentry --disable-doc --disable-tests \
       && make -j"$(nproc)" \
       && make install ) > "$TMP/build.log" 2>&1; then
  tail -40 "$TMP/build.log" >&2
  echo "❌ GnuPG ${VERSION} build failed" >&2
  exit 1
fi
ldconfig

# Keep the runtime libraries the new binaries link against, then drop the rest
# of what this run added (compilers, headers).
LIBS=$(for b in /usr/local/bin/* /usr/local/libexec/*; do
         ldd "$b" 2>/dev/null || true
       done | awk '$3 ~ /^\// { print $3 }' | LC_ALL=C sort -u)
NEEDED=$(for lib in $LIBS; do
           dpkg -S "$(readlink -f "$lib")" 2>/dev/null || dpkg -S "$lib" 2>/dev/null || true
         done | cut -d: -f1 | LC_ALL=C sort -u)
AFTER=$(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' | awk '$1 == "ii" { print $2 }' | LC_ALL=C sort -u)
ADDED=$(LC_ALL=C comm -13 <(echo "$BEFORE") <(echo "$AFTER"))
if [[ -n "$ADDED" ]]; then
  # shellcheck disable=SC2086
  apt-mark auto $ADDED >/dev/null
  [[ -n "$NEEDED" ]] && apt-mark manual $NEEDED >/dev/null
  apt-get autoremove -y --purge >/dev/null
fi
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb

# configure leaves out a component whose dependency it cannot find (dirmngr
# without GnuTLS, keyboxd without SQLite) and still succeeds. A missing one
# would fall through to Ubuntu's 2.4 copy, so check each.
hash -r
for b in bin/gpg bin/gpg-agent bin/gpgsm bin/gpgconf bin/dirmngr libexec/keyboxd libexec/scdaemon; do
  if ! /usr/local/$b --version 2>/dev/null | head -1 | grep -qF "${VERSION}"; then
    echo "❌ /usr/local/$b is missing or does not report ${VERSION}" >&2
    exit 1
  fi
done

echo "✅ GnuPG ${VERSION} installed."
echo -n "   gpg → "; gpg --version | head -1

cat <<'EON'
ℹ️ Ready to use:
- gpg, gpg-agent, gpgconf, dirmngr from /usr/local/bin shadow Ubuntu's 2.4.
- Post-quantum key:   gpg --quick-gen-key you@example.com pqc
- If an older agent is still running:   gpgconf --kill all

Notes:
- Ubuntu's gnupg packages stay installed for apt; /usr/bin/gpg is still 2.4.
- Docs: https://gnupg.org/documentation/
EON
