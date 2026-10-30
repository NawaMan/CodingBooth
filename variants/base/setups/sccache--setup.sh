#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.2.0

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]

Examples:
  $0                         # install sccache ${SCCACHE_DEFAULT_VER:-(pinned default)}
  $0 --version latest        # newest release
  $0 --version 0.18.0        # pin specific version

Notes:
- Installs sccache to /usr/local/bin/sccache (the static musl build)
- Supports amd64 and arm64
- Only installs the binary: cargo uses it once RUSTC_WRAPPER=sccache is set,
  which the rust+sccache extension does on the container environment
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
SCCACHE_DEFAULT_VER="0.19.0"   # used as-is, and as the fallback when 'latest' cannot be resolved
REQ_VER="$SCCACHE_DEFAULT_VER"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-$SCCACHE_DEFAULT_VER}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- arch mapping ----
dpkgArch="$(dpkg --print-architecture)"
case "$dpkgArch" in
  amd64) ARCH="x86_64" ;;
  arm64) ARCH="aarch64" ;;
  *) echo "❌ Unsupported arch: $dpkgArch (need amd64 or arm64)"; exit 1 ;;
esac

# The base image already carries curl, tar, and ca-certificates; only pay for
# apt when this script is run somewhere leaner.
if ! command -v curl >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends curl ca-certificates tar
  rm -rf /var/lib/apt/lists/*
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/mozilla/sccache/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See elixir--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest sccache release; using ${SCCACHE_DEFAULT_VER}."
    VERSION="$SCCACHE_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install sccache ----
echo "⬇️  Installing sccache v${VERSION} (${ARCH}) ..."
NAME="sccache-v${VERSION}-${ARCH}-unknown-linux-musl"
TMP_DIR=$(mktemp -d)
curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL \
  "https://github.com/mozilla/sccache/releases/download/v${VERSION}/${NAME}.tar.gz" -o "${TMP_DIR}/sccache.tar.gz"
tar -xzf "${TMP_DIR}/sccache.tar.gz" -C "${TMP_DIR}"
install -d /usr/local/lib/sccache
install -m 755 "${TMP_DIR}/${NAME}/sccache" /usr/local/lib/sccache/sccache
rm -rf "${TMP_DIR}"

# ---- starter: warn when the shared cache is not mounted ----
# rust+sccache sets SCCACHE_DIR and bind-mounts the host's ~/.cache/sccache there
# (`:create`, so booth makes the folder). If the mount still did not happen -- the
# folder could not be created, or SCCACHE_DIR was pointed elsewhere -- sccache
# caches inside the container: it works, shares nothing, and is gone with the booth.
# Startup hooks only log to /tmp/startups.log, so the warning goes where it is
# seen: the first compile, once per container. No SCCACHE_DIR, no expectation.
# Only a real crate compile counts: cargo discards the stderr of its probes
# (`rustc -vV`, `--crate-name ___`), which would otherwise use up the one warning.
cat > /usr/local/bin/sccache <<'EOF'
#!/bin/bash
# cargo compiles crates in parallel: mkdir is atomic, so exactly one of them warns.
if [[ -n "${SCCACHE_DIR:-}" && " $* " == *" --crate-name "* && " $* " != *" --crate-name ___ "* ]] \
   && mkdir /tmp/.cb-sccache-checked 2>/dev/null; then
  if ! mountpoint -q "$SCCACHE_DIR" 2>/dev/null; then
    cat >&2 <<WARN
⚠️  sccache: $SCCACHE_DIR is not mounted from the host, so compiled crates are
   cached in this booth only and are not shared with other projects.
   Check that the host folder exists and is yours (~/.cache/sccache), then restart the booth.
WARN
  fi
fi
exec /usr/local/lib/sccache/sccache "$@"
EOF
chmod 755 /usr/local/bin/sccache

# ---- friendly summary ----
echo "✅ sccache installed."
echo -n "   sccache → "; sccache --version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- cargo build                 # compiled crates are cached when RUSTC_WRAPPER=sccache
- sccache --show-stats        # cache hits and misses since the server started
- sccache --zero-stats        # reset the counters

Notes:
- The cache lives in SCCACHE_DIR (default ~/.cache/sccache), capped by SCCACHE_CACHE_SIZE (default 10G).
- Incrementally compiled crates (your own workspace members in a debug build) are not cached;
  dependencies are, which is where most of the build time goes.
- See: https://github.com/mozilla/sccache
EON
