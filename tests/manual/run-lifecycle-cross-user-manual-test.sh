#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Manual test: cross-user lifecycle image restore behavior
#
# This validates the known limitation:
# image committed by User A and run by User B may hit UID/GID ownership issues.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
PLAYGROUND_DIR="$ROOT_DIR/examples/playground"

TAG="cb-manual-cross-user:$(date +%Y%m%d-%H%M%S)"
TARGET_USER=""
AUTO_CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --user)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Error: --user requires a username value."
        exit 2
      fi
      TARGET_USER="$2"
      shift 2
      ;;
    --yes|-y)
      AUTO_CONFIRM=true
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [--user <username>] [--yes]"
      echo "  --user <username>  Run test against this local user without username prompt"
      echo "  --yes, -y          Skip confirmation prompt"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Use --help for usage."
      exit 2
      ;;
  esac
done

echo "═══════════════════════════════════════════════════════════"
echo "Lifecycle Cross-User Manual Test"
echo "═══════════════════════════════════════════════════════════"
echo

echo "This manual test asks for another local user and attempts:"
echo "  1) User A (you) creates and commits a booth image"
echo "  2) User B runs that image"
echo "  3) We check if /home/coder is writable for User B"
echo

if [[ -z "$TARGET_USER" ]]; then
  read -rp "Enter another local username to test with: " TARGET_USER
fi

if [[ -z "${TARGET_USER}" ]]; then
  echo "No username provided. Exiting."
  exit 1
fi

if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "User '$TARGET_USER' does not exist on this machine."
  exit 1
fi

echo
if [[ "$AUTO_CONFIRM" != "true" ]]; then
  read -rp "Proceed with manual cross-user test using '$TARGET_USER'? [y/N]: " CONFIRM
  CONFIRM="$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')"
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "yes" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

echo
echo "Step A: build and copy latest codingbooth binary"
GOCACHE=/tmp/go-cache ./build/cli-build.sh >/dev/null
cp -f ./codingbooth ./examples/playground/codingbooth
chmod +x ./examples/playground/codingbooth

# Ensure egress allowlist exists for playground config
EGRESS_ALLOWLIST="$PLAYGROUND_DIR/.booth/egress/allowlist.txt"
if [[ ! -f "$EGRESS_ALLOWLIST" ]]; then
  mkdir -p "$(dirname "$EGRESS_ALLOWLIST")"
  cat > "$EGRESS_ALLOWLIST" <<'EOF'
pypi.org
files.pythonhosted.org
EOF
  echo "Note: created missing egress allowlist at $EGRESS_ALLOWLIST"
fi

echo "Step B: create keep-alive booth and commit image as current user"
(
  cd "$PLAYGROUND_DIR"
  ./codingbooth --name cross-user-source --keep-alive -- 'mkdir -p /home/coder/.manual-cross-user && echo created-by-user-a > /home/coder/.manual-cross-user/owner.txt'
  docker commit cross-user-source "$TAG" >/dev/null
  docker rm -f cross-user-source >/dev/null 2>&1 || true
)

echo
echo "Step C: run committed image as user '$TARGET_USER'"
echo "Command to run (you may be prompted for sudo password):"
echo "  sudo -u $TARGET_USER -H bash -lc 'cd $PLAYGROUND_DIR && ./codingbooth --image $TAG --keep-alive -- \"touch /home/coder/.manual-cross-user/from-user-b\"'"
echo

set +e
OUTPUT="$(sudo -u "$TARGET_USER" -H bash -lc "cd '$PLAYGROUND_DIR' && ./codingbooth --image '$TAG' --keep-alive -- 'touch /home/coder/.manual-cross-user/from-user-b'" 2>&1)"
RESULT=$?
set -e

echo
if [[ $RESULT -eq 0 ]]; then
  echo "✅ Manual check result: User B command succeeded."
  echo "   Cross-user restore may be fine for this setup."
elif grep -q "Permission denied" <<<"$OUTPUT" && grep -q "cd: $PLAYGROUND_DIR" <<<"$OUTPUT"; then
  echo "✅ Expected environment limitation: target user cannot access the test folder."
  echo "   This run did not reach the cross-UID/GID check."
  echo "   Re-run from a shared path (for example /tmp) to perform the real ownership test."
else
  echo "⚠️  Manual check result: User B command failed (exit $RESULT)."
  echo "   This can indicate the known cross-UID/GID ownership limitation."
  echo "   Command output:"
  echo "$OUTPUT" | sed 's/^/     /'
fi

echo
echo "Cleanup commands:"
echo "  docker rm -f cross-user-source >/dev/null 2>&1 || true"
echo "  docker rmi $TAG >/dev/null 2>&1 || true"

echo
docker rm -f cross-user-source >/dev/null 2>&1 || true
docker rmi "$TAG" >/dev/null 2>&1 || true

echo "Done."
