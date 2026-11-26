#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: go/cargo/cabal--install.sh take the packages the catalog installs
# from NawaMan/CodingBoothPrebuilt, and pecl--install.sh takes an unpinned
# extension from apt -- each compiling only when there is no binary.
#
#   go     gopls@latest resolves through the module proxy and lands in ~/go/bin;
#          dlv@v1.27.2 is taken as pinned; with no asset, or for an unknown
#          module, `go install` runs as before.
#   cargo  ripgrep resolves through crates.io and lands rg in ~/.cargo/bin;
#          --locked alone keeps the prebuilt; any other flag compiles.
#   cabal  hlint resolves through Hackage, lands in the haskell-tools layout and
#          is linked; a package left over still goes to `cabal install`.
#   pecl   redis comes from apt as php<ver>-redis; a pinned redis-6.0.2, or an
#          extension apt does not package, goes to pecl.
#
# Hermetic: every registry and the release folder are file:// paths this test
# writes, so the version lookup, download, sha256 check and unpack are the real
# ones. sudo, install, ln, id, uname, go, cargo, cabal, pecl, php and apt-get
# are stubs that log; nothing is installed or written outside the stub dir.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"

# The prebuilt asset is named after /etc/os-release (ubuntu26.04), which only Linux has.
if [[ ! -r /etc/os-release ]]; then
    echo "SKIP: $0 needs /etc/os-release for the CodingBoothPrebuilt asset names ($(uname -s))"
    exit 0
fi
DISTRO="$(. /etc/os-release && echo "${ID}${VERSION_ID}")"

STUB="$(cd "$(mktemp -d)" && pwd -P)"
trap '/bin/rm -rf "$STUB"' EXIT
mkdir -p "$STUB/bin" "$STUB/releases" "$STUB/empty" "$STUB/home" "$STUB/opt" "$STUB/php/bin"
LOG="$STUB/calls.log"

# A release asset holding bin/<executable>s (or <executable> at the top, as hlint ships).
make_asset() { # tool version layout(bin|top) executable...
    local tool="$1" version="$2" layout="$3"; shift 3
    local name="${tool}-${version}-${DISTRO}-x86_64" dir exe
    dir="$STUB/pkg/$name"; [[ "$layout" == bin ]] && dir="$dir/bin"
    mkdir -p "$dir" "$STUB/releases/${tool}-${version}"
    for exe in "$@"; do printf '#!/bin/sh\necho prebuilt-%s\n' "$exe" > "$dir/$exe"; chmod +x "$dir/$exe"; done
    tar -czf "$STUB/releases/${tool}-${version}/$name.tar.gz" -C "$STUB/pkg" "$name"
    (cd "$STUB/releases/${tool}-${version}" && sha256sum "$name.tar.gz" > "$name.tar.gz.sha256")
}
make_asset gopls 0.24.0 bin gopls
make_asset dlv 1.27.2 bin dlv
make_asset ripgrep 16.0.0 bin rg
make_asset hlint 3.10 top hlint

# The registries, as the files their APIs would serve.
mkdir -p "$STUB/proxy/golang.org/x/tools/gopls/@latest" "$STUB/crates" "$STUB/hackage/hlint"
echo '{"Version":"v0.24.0","Time":"2026-11-01T00:00:00Z"}' > "$STUB/proxy/golang.org/x/tools/gopls/@latest/index"
echo '{"crate":{"id":"ripgrep","max_stable_version":"16.0.0"}}' > "$STUB/crates/ripgrep"
echo '{"deprecated-version":[],"normal-version":["3.10","3.8"]}' > "$STUB/hackage/hlint/preferred"

# file:// cannot serve a directory, so the proxy's .../@latest is a folder with an index;
# a curl stub maps it. Every other URL goes to the real curl.
REAL_CURL="$(command -v curl)"
cat > "$STUB/bin/curl" <<STUBEOF
#!/bin/bash
args=()
for a in "\$@"; do
  case "\$a" in file://*/@latest) a="\$a/index" ;; esac
  args+=("\$a")
done
exec "$REAL_CURL" "\${args[@]}"
STUBEOF
for cmd in sudo install ln go cargo cabal pecl apt-get; do
    printf '#!/bin/bash\necho "%s $*" >> "$STUB_LOG"\n' "$cmd" > "$STUB/bin/$cmd"
done
# apt has php8.4-redis and nothing else; `php -m` lists redis once its package is in.
cat > "$STUB/bin/apt-get" <<'STUBEOF'
#!/bin/bash
echo "apt-get $*" >> "$STUB_LOG"
if [[ " $* " == *" -s "* ]]; then [[ " $* " == *" php8.4-redis "* ]]; exit; fi
[[ " $* " == *" install "* && " $* " == *" php8.4-redis "* ]] && touch "$STUB_ROOT/redis-installed"
exit 0
STUBEOF
cat > "$STUB/php/bin/php" <<'STUBEOF'
#!/bin/bash
case "$1" in
  -r) echo -n 8.4 ;;
  -m) echo Core; [[ -f "$STUB_ROOT/redis-installed" ]] && echo redis ;;
  -i) echo "extension_dir => $STUB_ROOT/ext => $STUB_ROOT/ext"
      echo "Scan this dir for additional .ini files => $STUB_ROOT/scan" ;;
esac
exit 0
STUBEOF
# pecl builds <name>.so like the real one, so its fallback passes its own .so check.
cat > "$STUB/bin/pecl" <<'STUBEOF'
#!/bin/bash
echo "pecl $*" >> "$STUB_LOG"
name="${2##*/}"; name="${name%%-[0-9]*}"
touch "$STUB_ROOT/ext/${name}.so"
STUBEOF
mkdir -p "$STUB/ext" "$STUB/scan"
printf '#!/bin/bash\necho coder\n' > "$STUB/bin/id"
printf '#!/bin/bash\necho x86_64\n' > "$STUB/bin/uname"
chmod +x "$STUB/bin/"* "$STUB/php/bin/php"

run() { # releases-dir script args...; sets OUT and RC
    local releases="$1" script="$2"; shift 2
    : > "$LOG"; /bin/rm -f "$STUB/redis-installed" "$STUB/ext/"* "$STUB/scan/"*
    RC=0
    OUT=$(env EUID=0 PATH="$STUB/bin:/usr/bin:/bin:/sbin" STUB_LOG="$LOG" STUB_ROOT="$STUB" \
        CB_PREBUILT_URL="file://$releases" CB_GO_PROXY_URL="file://$STUB/proxy" \
        CB_CRATES_API_URL="file://$STUB/crates" CB_HACKAGE_URL="file://$STUB/hackage" \
        CB_USER_NAME=coder CB_USER_HOME="$STUB/home" CB_HASKELL_TOOLS_ROOT="$STUB/opt" \
        GO_BIN="$STUB/bin/go" CARGO_BIN="$STUB/bin/cargo" HASKELL_HOME="$STUB/none" \
        PHP_HOME="$STUB/php" CB_RETRY_DELAY=0 \
        bash "$SETUPS/$script" "$@" 2>&1) || RC=$?
}

FAILED=0
check() { # number description ok
    print_test_result "$3" "$0" "$1" "$2"
    if [[ "$3" != "true" ]]; then
        echo "  rc=$RC"
        echo "$OUT" | sed 's/^/  out: /' | tail -10
        sed 's/^/  log: /' "$LOG" | tail -10
        FAILED=$((FAILED + 1))
    fi
}
logged() { grep -qE "$1" "$LOG"; }

# ---- go ----
run "$STUB/releases" go--install.sh golang.org/x/tools/gopls@latest github.com/go-delve/delve/cmd/dlv@v1.27.2
ok=false
[[ $RC -eq 0 ]] && logged "^install -m 755 -o coder -g coder .*/gopls/bin/gopls $STUB/home/go/bin/gopls$" \
  && logged "^install -m 755 -o coder -g coder .*/dlv/bin/dlv $STUB/home/go/bin/dlv$" \
  && ! logged "go install" && ok=true
check 1 "go: gopls@latest (via the proxy) and dlv@v1.27.2 come prebuilt into ~/go/bin" "$ok"

run "$STUB/empty" go--install.sh golang.org/x/tools/gopls@latest
ok=false
[[ $RC -eq 0 ]] && grep -q "gopls 0.24.0: not prebuilt for this image" <<< "$OUT" \
  && logged "^sudo -u coder bash -lc go install 'golang.org/x/tools/gopls@latest'$" && ok=true
check 2 "go: with no asset, gopls@latest is go-installed as before" "$ok"

run "$STUB/releases" go--install.sh github.com/example/tool@latest
ok=false
[[ $RC -eq 0 ]] && logged "^sudo -u coder bash -lc go install 'github.com/example/tool@latest'$" \
  && ! logged "^install " && ok=true
check 3 "go: a module not in the prebuilt list is go-installed" "$ok"

# ---- cargo ----
run "$STUB/releases" cargo--install.sh --locked ripgrep
ok=false
[[ $RC -eq 0 ]] && logged "^install -m 755 -o coder -g coder .*/ripgrep/bin/rg $STUB/home/.cargo/bin/rg$" \
  && ! logged "cargo install" && ok=true
check 4 "cargo: --locked ripgrep (crates.io's newest) comes prebuilt as ~/.cargo/bin/rg" "$ok"

run "$STUB/releases" cargo--install.sh --features=pcre2 ripgrep
ok=false
[[ $RC -eq 0 ]] && logged "cargo install 'ripgrep' --features=pcre2" && ! logged "^install " && ok=true
check 5 "cargo: a flag other than --locked compiles" "$ok"

run "$STUB/releases" cargo--install.sh ripgrep@14.1.0
ok=false
[[ $RC -eq 0 ]] && grep -q "ripgrep 14.1.0: not prebuilt for this image" <<< "$OUT" \
  && logged "cargo install 'ripgrep' --version '14.1.0'" && ok=true
check 6 "cargo: a pinned version with no asset compiles that version" "$ok"

# ---- cabal ----
run "$STUB/releases" cabal--install.sh hlint pandoc
ok=false
[[ $RC -eq 0 ]] && [[ -x "$STUB/opt/hlint-3.10/hlint" ]] \
  && logged "^ln -sfn $STUB/opt/hlint-3.10/hlint /usr/local/bin/hlint$" \
  && logged "^cabal install --installdir=/usr/local/bin --install-method=copy --overwrite-policy=always pandoc$" \
  && ! logged "cabal install .*hlint" && ok=true
check 7 "cabal: hlint (Hackage's newest) comes prebuilt and linked; pandoc still goes to cabal" "$ok"

run "$STUB/releases" cabal--install.sh hlint
ok=false
[[ $RC -eq 0 ]] && ! logged "^cabal " && ok=true
check 8 "cabal: nothing left to build runs no cabal at all" "$ok"

# ---- pecl ----
run "$STUB/releases" pecl--install.sh redis
ok=false
[[ $RC -eq 0 ]] && logged "^apt-get install -y --no-install-recommends php8.4-redis$" \
  && ! logged "^pecl " && [[ ! -e "$STUB/scan/redis.ini" ]] && ok=true
check 9 "pecl: an unpinned redis comes from apt as php8.4-redis, enabled by the package" "$ok"

run "$STUB/releases" pecl--install.sh redis-6.0.2 xdebug
ok=false
[[ $RC -eq 0 ]] && logged "^pecl install redis-6.0.2$" && logged "^pecl install xdebug$" \
  && ! logged "apt-get install -y" && ok=true
check 10 "pecl: a pinned version, or an extension apt lacks, is built with pecl" "$ok"

if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
