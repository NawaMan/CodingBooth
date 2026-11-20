#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.4.2

# gnupg--setup.sh — Install GnuPG 2.5 into /usr/local, so it shadows Ubuntu's
# gpg on PATH: prebuilt when CodingBoothPrebuilt has it, else from the release.
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
  $0                       # GnuPG 2.5.24
  $0 --version 2.5.24      # pin a release

Notes:
- Installs gpg, gpg-agent, gpgconf, dirmngr, ... to /usr/local/bin
- Comes prebuilt (sha256-checked) from https://github.com/NawaMan/CodingBoothPrebuilt,
  built there from the release tarball after the same signature check
- A version not prebuilt (yet) is built from source: the release signature is checked
  against the GnuPG release keys, the default version's tarball against its pinned
  SHA256, and build tools and -dev packages are removed again after the build
- Upstream fixes a release lacks are patched in (2.5.24: https://dev.gnupg.org/T8469,
  a secret key imported without a passphrase could not decrypt). A prebuilt asset
  from before a fix fails the check for it, and the release is built from source
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

# Upstream fixes a release lacks, "<commit> <sha256 of its .patch>" each, as Homebrew's
# formula applies them. Keep in step with CodingBoothPrebuilt's tools/gnupg/build.sh.
PATCHES=()
case "$VERSION" in
  2.5.24)
    # https://dev.gnupg.org/T8469: a secret key imported without a passphrase cannot
    # decrypt -- every EnvFolio .folio export's key (Homebrew 2.5.24_1).
    PATCHES=(
      "42386bcf8861f04c1bdec5cbb139a03da83d8ef9 93817449be3f93dcade3d79960e33e72959f54f95ff6108f22176bef28111f2b"
      "5523cec6913bcbd1a374d183899a6f298d2c0e32 0a0acd2f7f25723f3f84ec5c4ecf03b786d73ca61c48487d4d00c0559be89d66"
    ) ;;
esac

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# Where the install lands. CB_GNUPG_TEST_ROOT (tests only) puts /usr/local and the startup
# hook under a scratch folder; the build itself is always configured for /usr/local.
PREFIX="${CB_GNUPG_TEST_ROOT:-}/usr/local"

SETUPS_DIR="$(dirname "$0")"
[ -x "${SETUPS_DIR}/apt--install.sh" ] || SETUPS_DIR=/opt/codingbooth/setups

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The prebuilt asset is the installed /usr/local tree, built with this script's
# configure flags after the same signature check (CodingBoothPrebuilt's
# tools/gnupg/build.sh), plus RUNTIME-DEPS.txt: the Ubuntu packages holding the
# libraries it links.
install_prebuilt() {
  local src="$TMP/prebuilt" deps=() pkg
  # Ubuntu's own gnupg already pulls in most of them; install only what is missing.
  while read -r pkg; do
    [[ -n "$pkg" ]] && ! dpkg -s "$pkg" >/dev/null 2>&1 && deps+=("$pkg")
  done < "$src/RUNTIME-DEPS.txt"
  if [[ ${#deps[@]} -gt 0 ]]; then
    echo "⬇️  Installing GnuPG ${VERSION} runtime libraries ..."
    "${SETUPS_DIR}/apt--install.sh" "${deps[@]}"
  fi
  local d
  for d in bin sbin libexec share; do
    [[ -d "$src/$d" ]] && cp -a "$src/$d" "$PREFIX/"
  done
  mkdir -p "$PREFIX/share/doc/gnupg"
  cp "$src/BUILD-INFO.txt" "$src/COPYING" "$PREFIX/share/doc/gnupg/"
  ldconfig
}

build_from_source() {
  echo "ℹ️  GnuPG ${VERSION}: building from source..."
  BUILD_DEPS=(
    bzip2 ca-certificates curl gcc make patch pkgconf
    libgpg-error-dev libgcrypt20-dev libassuan-dev libksba-dev libnpth0-dev
    libgnutls28-dev libsqlite3-dev libbz2-dev zlib1g-dev libreadline-dev libldap-dev
  )

  # Everything installed only for the build is removed after it: list what is
  # already there, so only the packages this run adds are candidates.
  BEFORE=$(dpkg-query -W -f '${db:Status-Abbrev} ${Package}\n' | awk '$1 == "ii" { print $2 }' | LC_ALL=C sort -u)

  echo "⬇️  Installing GnuPG ${VERSION} build dependencies ..."
  "${SETUPS_DIR}/apt--install.sh" "${BUILD_DEPS[@]}"

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
  local entry commit sha256
  for entry in ${PATCHES[@]+"${PATCHES[@]}"}; do
    read -r commit sha256 <<< "$entry"
    # The fixes are kept beside this script (libs/gnupg-patches/): GitHub makes a commit's
    # .patch on request and answers 503 far more often than not, for minutes at a time, which
    # failed two image builds in a row. One that is not there is asked for, for up to five
    # minutes. Either way it has to match the SHA-256 pinned above.
    local try got=0
    if [ -r "${SETUP_LIBS_DIR}/gnupg-patches/${commit}.patch" ]; then
      cp "${SETUP_LIBS_DIR}/gnupg-patches/${commit}.patch" "$TMP/${commit}.patch"
      got=1
    fi
    for try in $(seq 1 60); do
      (( got )) && break
      if curl --connect-timeout 15 --retry 3 --retry-delay 2 -fsSL \
           "https://github.com/gpg/gnupg/commit/${commit}.patch?full_index=1" -o "$TMP/${commit}.patch" 2>/dev/null; then
        got=1
        break
      fi
      (( try % 6 == 0 )) && echo "   still waiting for GitHub to serve ${commit:0:12}.patch ..."
      sleep 5
    done
    if (( ! got )); then
      echo "❌ Download failed: upstream fix ${commit} (GitHub did not serve it in five minutes)" >&2
      exit 1
    fi
    ACTUAL="$(sha256sum "$TMP/${commit}.patch" | awk '{ print $1 }')"
    if [[ "$ACTUAL" != "$sha256" ]]; then
      echo "❌ SHA256 mismatch for ${commit}.patch (expected '${sha256}', got '${ACTUAL}')" >&2
      exit 1
    fi
    patch -s -d "$TMP/gnupg-${VERSION}" -p1 < "$TMP/${commit}.patch"
    echo "🩹 Applied upstream fix ${commit:0:12}"
  done
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
  LIBS=$(for b in "$PREFIX"/bin/* "$PREFIX"/libexec/*; do
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
}

SETUP_LIBS_DIR="${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}"
if [ ! -r "${SETUP_LIBS_DIR}/prebuilt-source.sh" ]; then
  SETUP_LIBS_DIR="$(dirname "$0")/libs"
fi
source "${SETUP_LIBS_DIR}/prebuilt-source.sh"

# A secret key made in one gpg home, exported and imported into another, has to
# decrypt there (T8469). Run with the installed gpg, in throwaway homes.
imported_key_decrypts() {
  local check="$TMP/check" ok=1 gpg="$PREFIX/bin/gpg"
  rm -rf "$check"
  mkdir -p "$check" && mkdir -m 700 "$check/a" "$check/b"
  GNUPGHOME="$check/a" "$gpg" --batch --quiet --passphrase '' \
      --quick-generate-key "Check <check@example.com>" default default never >/dev/null 2>&1 || true
  GNUPGHOME="$check/a" "$gpg" --batch --armor --export-secret-keys 2>/dev/null \
      | GNUPGHOME="$check/b" "$gpg" --batch --quiet --import >/dev/null 2>&1 || true
  if echo ok | GNUPGHOME="$check/b" "$gpg" --batch --trust-model always -e -r check@example.com 2>/dev/null \
       | GNUPGHOME="$check/b" "$gpg" --batch --quiet -d 2>/dev/null | grep -qx ok; then
    ok=0
  fi
  GNUPGHOME="$check/a" "$PREFIX/bin/gpgconf" --kill all >/dev/null 2>&1 || true
  GNUPGHOME="$check/b" "$PREFIX/bin/gpgconf" --kill all >/dev/null 2>&1 || true
  rm -rf "$check"
  return $ok
}

BUILT_FROM_SOURCE=0
if cb_prebuilt_install gnupg "$VERSION" native "$TMP/prebuilt"; then
  install_prebuilt
  # An asset published before a fix was added here does not have it.
  if ! imported_key_decrypts; then
    echo "⚠️  The prebuilt GnuPG ${VERSION} cannot decrypt with an imported secret key (an asset from before the fix)."
    BUILT_FROM_SOURCE=1
    build_from_source
  fi
else
  echo "ℹ️  GnuPG ${VERSION}: not prebuilt for this image."
  BUILT_FROM_SOURCE=1
  build_from_source
fi
if (( BUILT_FROM_SOURCE )) && ! imported_key_decrypts; then
  echo "❌ GnuPG ${VERSION} cannot decrypt with an imported secret key" >&2
  exit 1
fi

# configure leaves out a component whose dependency it cannot find (dirmngr
# without GnuTLS, keyboxd without SQLite) and still succeeds. A missing one
# would fall through to Ubuntu's 2.4 copy, so check each.
hash -r
for b in bin/gpg bin/gpg-agent bin/gpgsm bin/gpgconf bin/dirmngr libexec/keyboxd libexec/scdaemon; do
  if ! "$PREFIX/$b" --version 2>/dev/null | head -1 | grep -qF "${VERSION}"; then
    echo "❌ /usr/local/$b is missing or does not report ${VERSION}" >&2
    exit 1
  fi
done

# ---- startup: keys brought from the host (gnupg+keys, envfolio+seed) ----
# The CLI copies the private key files of the keys asked for -- private-keys-v1.d/<keygrip>.key, as
# the host's gpg keeps them, still encrypted with the key's passphrase -- into
# .booth/.tmp/gnupg-keys/private-keys/, and for gnupg+keys the host's public keyring into
# pubkeys.asc. This hook puts them into the booth's gpg home, never over a key file already there;
# the booth's own gpg-agent asks for a passphrase, in the booth, when a key is used.
STARTUP_FILE="${CB_GNUPG_TEST_ROOT:-}/usr/share/startup.d/55-cb-gnupg-keys--startup.sh"
mkdir -p "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

KEYS="${CB_GNUPG_KEYS_DIR:-/home/coder/code/.booth/.tmp/gnupg-keys}"   # override: tests only
[[ -d "$KEYS" ]] || exit 0

say() { echo "GnuPG keys: $*"; }
gnupg_home="${GNUPGHOME:-$HOME/.gnupg}"
mkdir -p "$gnupg_home" && chmod 700 "$gnupg_home"

if [[ -s "$KEYS/pubkeys.asc" ]]; then
    if gpg --batch --quiet --import "$KEYS/pubkeys.asc" >/dev/null 2>&1; then
        say "imported the host's public keyring."
    else
        say "could not import the host's public keyring."
    fi
fi

if [[ -d "$KEYS/private-keys" ]]; then
    mkdir -p "$gnupg_home/private-keys-v1.d" && chmod 700 "$gnupg_home/private-keys-v1.d"
    keys=0
    for key in "$KEYS/private-keys"/*.key; do
        [[ -f "$key" ]] || continue
        dst="$gnupg_home/private-keys-v1.d/$(basename "$key")"
        [[ -e "$dst" ]] && continue
        cp "$key" "$dst" && chmod 600 "$dst" && keys=$((keys + 1))
    done
    (( keys == 0 )) || say "brought $keys private key file(s) from the host (passphrase-protected)."
fi
true
EOF
chmod 755 "$STARTUP_FILE"

echo "✅ GnuPG ${VERSION} installed."
echo -n "   gpg → "; gpg --version | head -1

cat <<'EON'
ℹ️ Ready to use:
- gpg, gpg-agent, gpgconf, dirmngr from /usr/local/bin shadow Ubuntu's 2.4.
- Post-quantum key:   gpg --quick-gen-key you@example.com pqc
- If an older agent is still running:   gpgconf --kill all
- Keys from the host:   select tools/gnupg+keys:"<key id or email>"

Notes:
- Ubuntu's gnupg packages stay installed for apt; /usr/bin/gpg is still 2.4.
- Docs: https://gnupg.org/documentation/
EON
