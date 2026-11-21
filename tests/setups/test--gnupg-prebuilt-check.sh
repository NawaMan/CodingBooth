#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: gnupg--setup.sh checks the gpg it installed for the upstream fixes
# a release lacks, and what it does when the check fails
#
# GnuPG 2.5.24 as released cannot decrypt with a secret key imported without a
# passphrase (https://dev.gnupg.org/T8469). The setup patches the source build,
# and after installing runs an export / import / decrypt round trip:
#
#   1. A prebuilt asset that passes is kept: nothing is built from source.
#   2. A prebuilt asset that fails (one published before the fix) is replaced by
#      a source build, with both upstream fixes applied.
#   3. No prebuilt asset: the source build applies both fixes.
#   4. A source build whose gpg still fails stops the setup.
#   5. An upstream fix whose sha256 does not match stops the setup before
#      anything is compiled.
#   6. Every fix the setup pins is kept in libs/gnupg-patches/ and matches its
#      sha256 (the real one), so a build downloads none of them.
#   7. With the fixes beside the setup, the source build applies them and asks
#      GitHub for nothing.
#
# Cases 2-5 run with no libs/gnupg-patches/ beside the copy, so they cover the
# download that is left for a fix not kept there.
#
# Hermetic: the setup runs from a copy beside a stub apt--install.sh and a stub
# prebuilt-source.sh, with CB_GNUPG_TEST_ROOT putting /usr/local and the startup
# hook under a scratch folder. curl, tar, make, patch, gpg, sha256sum, dpkg,
# apt-get and the rest are stubs that log their arguments. The "gpg" it installs
# is a stub too: it decrypts only when a marker says it carries the fixes, which
# the stub `make install` writes only after `patch` ran for both commits.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/variants/base/setups/gnupg--setup.sh"

if ! grep -q 'CB_GNUPG_TEST_ROOT' "$SCRIPT"; then
    print_test_result "false" "$0" "0" "gnupg--setup.sh no longer reads CB_GNUPG_TEST_ROOT; this test cannot run it safely"
    exit 1
fi

# The real sha256sum, found before $STUB/bin stubs it: /usr/bin on Ubuntu, /sbin on macOS.
REAL_SHA256SUM="$(command -v sha256sum)"

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/tmp" "$STUB/setups/libs"
LOG="$STUB/calls.log"
cp "$SCRIPT" "$STUB/setups/gnupg--setup.sh"

# The stub gpg, used from PATH (to verify the tarball) and as every installed
# program. It decrypts only when <prefix>/share/patched exists.
cat > "$STUB/gpg-stub" <<'EOF'
#!/bin/bash
case " $* " in
  *" --version "*) echo "gpg (GnuPG) 2.5.24"; exit 0 ;;
  *" --verify "*)  echo "[GNUPG:] VALIDSIG stub 2026-01-01 0 4 0 1 10 00 6DAA6E64A76D2840571B4902528897B826403ADA"; exit 0 ;;
  *" -d "*)        cat > /dev/null
                   [[ -f "$(dirname "$0")/../share/patched" ]] && echo ok
                   exit 0 ;;
  *" -e "*)        cat; exit 0 ;;
esac
exit 0
EOF
chmod +x "$STUB/gpg-stub"
cp "$STUB/gpg-stub" "$STUB/bin/gpg"

# Lays an installed tree of stub programs into the folder named.
cat > "$STUB/lay-tree" <<'EOF'
#!/bin/bash
dest="$1"
/bin/mkdir -p "$dest/bin" "$dest/libexec" "$dest/share"
for b in bin/gpg bin/gpg-agent bin/gpgsm bin/gpgconf bin/dirmngr libexec/keyboxd libexec/scdaemon; do
  /bin/cp "$STUB_ROOT/gpg-stub" "$dest/$b"
done
EOF
chmod +x "$STUB/lay-tree"

# prebuilt-source.sh: PREBUILT_MODE none | patched | unpatched.
cat > "$STUB/setups/libs/prebuilt-source.sh" <<'EOF'
cb_prebuilt_install() {
  echo "cb_prebuilt_install $*" >> "$STUB_LOG"
  [[ "$PREBUILT_MODE" == none ]] && return 1
  "$STUB_ROOT/lay-tree" "$4"
  [[ "$PREBUILT_MODE" == patched ]] && touch "$4/share/patched"
  echo libc6 > "$4/RUNTIME-DEPS.txt"
  echo stub > "$4/BUILD-INFO.txt"
  echo stub > "$4/COPYING"
  return 0
}
EOF
cat > "$STUB/setups/apt--install.sh" <<'EOF'
#!/bin/bash
echo "apt--install $*" >> "$STUB_LOG"
EOF
chmod +x "$STUB/setups/apt--install.sh"

logging_stub() { # name [body]
  { echo '#!/bin/bash'; echo "echo \"$1 \$*\" >> \"\$STUB_LOG\""; echo "${2:-exit 0}"; } > "$STUB/bin/$1"
}
for name in dpkg dpkg-query ldconfig ldd apt-mark apt-get; do logging_stub "$name"; done
logging_stub patch 'cat > /dev/null'
cat > "$STUB/bin/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >> "$STUB_LOG"
out=""
while (($#)); do [[ "$1" == -o ]] && { out="$2"; shift; }; shift; done
[[ -n "$out" ]] && echo "stub-content" > "$out"
exit 0
EOF
# sha256sum: the hash the setup pins for the file, read out of the setup itself.
# PATCH_SHA=bad gives a patch a hash that is not the pinned one.
cat > "$STUB/bin/sha256sum" <<'EOF'
#!/bin/bash
name="$(basename "$1")"
case "$name" in
  *.tar.bz2) sum="$(sed -n 's/^GNUPG_DEFAULT_SHA256="\(.*\)"$/\1/p' "$STUB_SCRIPT")" ;;
  *.patch)   sum="$(sed -n "s/^ *\"${name%.patch} \([0-9a-f]*\)\"\$/\1/p" "$STUB_SCRIPT")"
             [[ "$PATCH_SHA" == bad ]] && sum=0000000000000000000000000000000000000000000000000000000000000000 ;;
esac
echo "${sum:-none}  $1"
EOF
# tar: "unpacks" a source tree whose configure only logs.
cat > "$STUB/bin/tar" <<'EOF'
#!/bin/bash
echo "tar $*" >> "$STUB_LOG"
dir=""
while (($#)); do [[ "$1" == -C ]] && { dir="$2"; shift; }; shift; done
/bin/mkdir -p "$dir/gnupg-2.5.24"
printf '#!/bin/bash\necho "configure $*" >> "$STUB_LOG"\n' > "$dir/gnupg-2.5.24/configure"
chmod +x "$dir/gnupg-2.5.24/configure"
EOF
# make install: the built programs carry the fixes only when patch ran for both
# commits (and SOURCE_MODE is not "broken").
cat > "$STUB/bin/make" <<'EOF'
#!/bin/bash
echo "make $*" >> "$STUB_LOG"
[[ "${1:-}" == install ]] || exit 0
prefix="$CB_GNUPG_TEST_ROOT/usr/local"
"$STUB_ROOT/lay-tree" "$prefix"
/bin/rm -f "$prefix/share/patched"
if [[ "$SOURCE_MODE" != broken && "$(grep -c '^patch ' "$STUB_LOG")" -eq 2 ]]; then
  touch "$prefix/share/patched"
fi
EOF
cat > "$STUB/bin/mktemp" <<'EOF'
#!/bin/bash
exec /usr/bin/mktemp -d "$STUB_ROOT/tmp/gnupg.XXXXXX"
EOF
cat > "$STUB/bin/rm" <<'EOF'
#!/bin/bash
for a in "$@"; do
  case "$a" in
    -*) ;;
    "$STUB_ROOT"/*) /bin/rm -rf "$a" ;;
  esac
done
EOF
chmod +x "$STUB/bin/"*

ROOT=""
run_setup() { # PREBUILT_MODE [SOURCE_MODE] [PATCH_SHA]; prints the output, sets RC and ROOT
    : > "$LOG"
    ROOT="$STUB/root-$1-${2:-ok}-${3:-ok}"
    mkdir -p "$ROOT/usr/local"
    RC=0
    OUT=$(env EUID=0 PATH="$STUB/bin:/usr/bin:/bin" STUB_LOG="$LOG" STUB_ROOT="$STUB" STUB_SCRIPT="$SCRIPT" \
        SETUP_LIBS_DIR="$STUB/setups/libs" CB_GNUPG_TEST_ROOT="$ROOT" \
        PREBUILT_MODE="$1" SOURCE_MODE="${2:-ok}" PATCH_SHA="${3:-ok}" \
        "$STUB/setups/gnupg--setup.sh" --version 2.5.24 2>&1) || RC=$?
}

FAILED=0
check() { # number, description, ok (true|false)
    print_test_result "$3" "$0" "$1" "$2"
    if [[ "$3" != "true" ]]; then
        echo "  rc=$RC"
        echo "$OUT" | sed 's/^/  out: /' | tail -10
        sed 's/^/  log: /' "$LOG" | tail -10
        FAILED=$((FAILED + 1))
    fi
}
both_fixes_applied() {
    [[ "$(grep -c '^patch ' "$LOG")" -eq 2 ]] &&
      grep -q "curl .*gpg/gnupg/commit/42386bcf8861f04c1bdec5cbb139a03da83d8ef9.patch" "$LOG" &&
      grep -q "curl .*gpg/gnupg/commit/5523cec6913bcbd1a374d183899a6f298d2c0e32.patch" "$LOG"
}
installed() {
    [[ "$RC" -eq 0 ]] && echo "$OUT" | grep -q "GnuPG 2.5.24 installed" &&
      [[ -f "$ROOT/usr/share/startup.d/55-cb-gnupg-keys--startup.sh" ]]
}

run_setup patched
ok=false
installed && ! echo "$OUT" | grep -q "building from source" &&
  ! grep -q "^make \|^curl \|^patch " "$LOG" && ok=true
check 1 "a prebuilt gpg that decrypts with an imported key is kept, with no source build" "$ok"

run_setup unpatched
ok=false
installed && echo "$OUT" | grep -q "cannot decrypt with an imported secret key (an asset from before the fix)" &&
  echo "$OUT" | grep -q "building from source" && both_fixes_applied &&
  grep -q "^make install" "$LOG" && [[ -f "$ROOT/usr/local/share/patched" ]] && ok=true
check 2 "a prebuilt gpg that cannot is replaced by a source build with both upstream fixes" "$ok"

run_setup none
ok=false
installed && echo "$OUT" | grep -q "not prebuilt for this image" && both_fixes_applied &&
  grep -q "^configure --prefix=/usr/local " "$LOG" && ok=true
check 3 "with no prebuilt asset the source build applies both upstream fixes" "$ok"

run_setup none broken
ok=false
[[ "$RC" -ne 0 ]] && echo "$OUT" | grep -q "❌ GnuPG 2.5.24 cannot decrypt with an imported secret key" &&
  ! echo "$OUT" | grep -q "GnuPG 2.5.24 installed" && ok=true
check 4 "a source build whose gpg still cannot decrypt stops the setup" "$ok"

run_setup none ok bad
ok=false
[[ "$RC" -ne 0 ]] && echo "$OUT" | grep -q "SHA256 mismatch for 42386bcf8861f04c1bdec5cbb139a03da83d8ef9.patch" &&
  ! grep -q "^make \|^patch " "$LOG" && ok=true
check 5 "an upstream fix whose sha256 does not match stops the setup before anything is compiled" "$ok"

# The pinned fixes, read out of the setup: "<commit> <sha256>" lines.
PINNED="$(sed -n 's/^ *"\([0-9a-f]\{40\}\) \([0-9a-f]\{64\}\)"$/\1 \2/p' "$SCRIPT")"
PATCH_DIR="$REPO_ROOT/variants/base/setups/libs/gnupg-patches"
ok=true; detail=""
[[ -n "$PINNED" ]] || { ok=false; detail="no pinned fix found in the setup"; }
while read -r commit want; do
    [[ -n "$commit" ]] || continue
    have="$("$REAL_SHA256SUM" "$PATCH_DIR/$commit.patch" 2>/dev/null | awk '{ print $1 }')"
    [[ "$have" == "$want" ]] || { ok=false; detail+=" $commit: ${have:-missing}"; }
done <<< "$PINNED"
RC=0; OUT="$detail"; : > "$LOG"
check 6 "every pinned upstream fix is kept in libs/gnupg-patches/ and matches its sha256" "$ok"

mkdir -p "$STUB/setups/libs/gnupg-patches"
cp "$PATCH_DIR"/*.patch "$STUB/setups/libs/gnupg-patches/"
run_setup none
ok=false
installed && [[ "$(grep -c '^patch ' "$LOG")" -eq 2 ]] && ! grep -q "curl .*gpg/gnupg/commit" "$LOG" &&
  [[ -f "$ROOT/usr/local/share/patched" ]] && ok=true
check 7 "with the fixes beside the setup the source build applies them and asks GitHub for nothing" "$ok"
rm -rf "$STUB/setups/libs/gnupg-patches"

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
