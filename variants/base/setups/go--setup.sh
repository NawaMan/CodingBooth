#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

# --------------------------
# Root setup
# --------------------------
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)"; exit 1; }

# --- Defaults ---
GO_VERSION="${1:-1.25.3}"         # Replace with desired Go version

LEVEL=57                          # See README.md - Profile Ordering

STARTUP_FILE="/usr/share/startup.d/${LEVEL}-cb-go--startup.sh"
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-go--profile.sh"
STARTER_FILE="/usr/local/bin/go"

# ==== Things to do once at the call time by root. ====

# ---- Install Go ----
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) GO_ARCH="amd64" ;;
    aarch64) GO_ARCH="arm64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
esac

GO_TARBALL="go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
GO_URL="https://go.dev/dl/${GO_TARBALL}"

echo "📦 Downloading Go ${GO_VERSION} from ${GO_URL}..."
curl -fsSL -o "/tmp/${GO_TARBALL}" "${GO_URL}"

echo "📂 Extracting to /usr/local ..."
# Clean only the temporary /usr/local/go extraction dir (not versions)
rm -rf /usr/local/go
tar -C /usr/local -xzf "/tmp/${GO_TARBALL}"

# Move extracted tree to a versioned directory and point 'current' to it
mv /usr/local/go "/usr/local/go-${GO_VERSION}"
ln -sfn "/usr/local/go-${GO_VERSION}" /usr/local/go-current

rm "/tmp/${GO_TARBALL}"

# ---- Create startup file: to be executed as normal user on first login ----
export GO_VERSION
envsubst '$GO_VERSION' > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SENTINEL="$HOME/.go-startup-done"
[[ -f "$SENTINEL" ]] || {
  mkdir -p "$HOME/go/bin" "$HOME/go/src" "$HOME/go/pkg"
  touch "$SENTINEL"
}
EOF
chmod 755 "${STARTUP_FILE}"

# ---- Create profile file: to be sourced at the beginning of a user shell session ----
envsubst '$GO_VERSION' > "${PROFILE_FILE}" <<'EOF'
# Profile: Go: $GO_VERSION

# ==== Things to do at shell login by user. ====
# Prefer the "current" symlink so the last installed wins.
case ":$PATH:" in
  *":/usr/local/go-current/bin:"*) ;;
  *) export PATH="/usr/local/go-current/bin:$PATH";;
esac

# Add GOPATH/bin to PATH if not already there
case ":$PATH:" in
  *":$HOME/go/bin:"*) ;;
  *) export PATH="$HOME/go/bin:$PATH";;
esac

export GOPATH="$HOME/go"
EOF
chmod 644 "${PROFILE_FILE}"

# ---- Create starter file: a wrapper to the program installed so that we can do things before and after ----
envsubst '$GO_VERSION' > "${STARTER_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Wrapper for Go binary using the "current" symlink.
exec /usr/local/go-current/bin/go "$@"
EOF
chmod 755 "${STARTER_FILE}"

echo "✅ .... Go is installed ...."
echo "• Version: ${GO_VERSION}"
echo "• Startup file (container login) : ${STARTUP_FILE}"
echo "• Profile file (every user shell): ${PROFILE_FILE}"
echo "• Starter file (the executable)  : ${STARTER_FILE}"
echo "• Current symlink                : /usr/local/go-current -> /usr/local/go-${GO_VERSION}"
echo ""
echo "You may source the profile above to start using Go in this session."
