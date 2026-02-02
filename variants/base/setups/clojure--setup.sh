#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Clojure setup script
# Installs Clojure CLI (tools.deps) and optionally Leiningen

set -Eeuo pipefail
trap 'echo "Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <x.y.z.z>|latest] [--with-lein|--no-lein]

Examples:
  $0                        # default Clojure CLI + Leiningen
  $0 --version latest       # latest Clojure CLI
  $0 --no-lein              # skip Leiningen

Notes:
- Installs Clojure CLI to /opt/clojure/clojure-<ver> -> /opt/clojure-stable
- Leiningen installed to /usr/local/bin/lein (optional)
- Requires Java (JAVA_HOME should be set by jdk--setup.sh)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "Run as root (use sudo)"; exit 1; }

# ---- defaults / args ----
CLJ_DEFAULT_VER="1.12.0.1479"
REQ_VER=""
WITH_LEIN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)   shift; REQ_VER="${1:-}"; shift ;;
    --with-lein) WITH_LEIN=1; shift ;;
    --no-lein)   WITH_LEIN=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

# Resolve version
if [[ -z "$REQ_VER" ]]; then
  CLJ_VER="$CLJ_DEFAULT_VER"
elif [[ "$REQ_VER" == "latest" ]]; then
  # Clojure releases are on GitHub
  CLJ_VER="$(curl -fsSL https://api.github.com/repos/clojure/brew-install/releases/latest | grep -oP '"tag_name"\s*:\s*"\K[^"]+' | sed 's/^v//')"
  [[ -n "$CLJ_VER" ]] || { echo "Failed to resolve latest Clojure version"; exit 1; }
else
  CLJ_VER="$REQ_VER"
fi

# ---- sanity: Java present ----
if ! command -v java >/dev/null 2>&1; then
  echo "Warning: Java not found. Install it first (jdk--setup.sh)."
fi

# ---- base deps ----
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates bash rlwrap
rm -rf /var/lib/apt/lists/*

# ---- locations ----
INSTALL_PARENT=/opt/clojure
TARGET_DIR="${INSTALL_PARENT}/clojure-${CLJ_VER}"
LINK_DIR=/opt/clojure-stable
BIN_DIR=/usr/local/bin

# Clean old shims
for b in clj clojure; do
  rm -f "${BIN_DIR}/$b" || true
done

# ---- Download and install Clojure CLI ----
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CLJ_URL="https://download.clojure.org/install/linux-install-${CLJ_VER}.sh"

echo "Downloading Clojure CLI ${CLJ_VER} ..."
curl -fsSL "$CLJ_URL" -o "$TMP/install.sh"
chmod +x "$TMP/install.sh"

echo "Installing Clojure CLI ${CLJ_VER} ..."
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

# The official installer expects to install to /usr/local, we'll redirect
bash "$TMP/install.sh" --prefix "$TARGET_DIR"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- Leiningen (optional) ----
if [[ $WITH_LEIN -eq 1 ]]; then
  echo "Installing Leiningen ..."
  curl -fsSL https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein -o "${BIN_DIR}/lein"
  chmod +x "${BIN_DIR}/lein"
  # Pre-download leiningen jar
  HOME=/tmp "${BIN_DIR}/lein" version || true
fi

# ---- login-shell env ----
cat >/etc/profile.d/61-cb-clojure--profile.sh <<'EOF'
# Clojure under /opt
export CLOJURE_HOME=/opt/clojure-stable
export PATH="$CLOJURE_HOME/bin:$PATH"
EOF
chmod 0644 /etc/profile.d/61-cb-clojure--profile.sh

# ---- non-login wrappers ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/cljwrap" <<'EOF'
#!/bin/sh
: "${CLOJURE_HOME:=/opt/clojure-stable}"
export PATH="$CLOJURE_HOME/bin:$PATH"
tool="$(basename "$0")"
exec "$CLOJURE_HOME/bin/$tool" "$@"
EOF
chmod +x "${BIN_DIR}/cljwrap"

for t in clj clojure; do
  ln -sfn "${BIN_DIR}/cljwrap" "${BIN_DIR}/$t"
done

# ---- summary ----
echo "Clojure CLI ${CLJ_VER} installed at ${TARGET_DIR} (linked at ${LINK_DIR})."
echo -n "   clojure: "; "${BIN_DIR}/clojure" --version 2>&1 || true
if [[ $WITH_LEIN -eq 1 ]]; then
  echo -n "   lein: "; "${BIN_DIR}/lein" version 2>&1 | head -n1 || true
fi

cat <<'EON'
Ready to use:
- clojure --version
- clj (REPL with rlwrap)
- lein new app myapp (if Leiningen installed)
- Requires JAVA_HOME set (use jdk--setup.sh first)
EON
