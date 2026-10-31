#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.1

# lsp--hls--setup.sh — Make the Haskell Language Server reachable for editors.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|recommended|latest]

Examples:
  $0                       # use the HLS the haskell template installed (recommended if none)
  $0 --version 2.11.0      # install and select that HLS release

Notes:
- Needs the haskell template: HLS goes into its ghcup tree under /opt/haskell-stable
- Links haskell-language-server-wrapper (what editors start) and haskell-language-server
  onto PATH through hswrap, so they work in non-login shells too
- HLS ships one binary per GHC it supports; the setup warns when the installed GHC is not one
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

REQ_VER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done
REQ_VER="${REQ_VER#v}"

HASKELL_HOME=/opt/haskell-stable
GHCUP_BIN="${HASKELL_HOME}/.ghcup/bin"
if [[ ! -x "${GHCUP_BIN}/ghcup" || ! -x /usr/local/bin/hswrap ]]; then
  echo "❌ HLS needs the Haskell toolchain, and ${GHCUP_BIN}/ghcup is not there." >&2
  echo "   Select the haskell template in booth config, then rebuild the booth." >&2
  exit 1
fi
# ghcup installs into the tree the haskell setup made, not ~/.ghcup.
export GHCUP_INSTALL_BASE_PREFIX="$(readlink -f "$HASKELL_HOME")"
export PATH="${GHCUP_BIN}:${HASKELL_HOME}/.cabal/bin:${PATH}"

if [[ -n "$REQ_VER" || ! -x "${GHCUP_BIN}/haskell-language-server-wrapper" ]]; then
  echo "📦 Installing HLS ${REQ_VER:-recommended} with ghcup ..."
  ghcup install hls "${REQ_VER:-recommended}"
  ghcup set hls "${REQ_VER:-recommended}"
fi

# Editors start the wrapper, which picks the per-GHC server for the project.
for t in haskell-language-server-wrapper haskell-language-server; do
  ln -sfn /usr/local/bin/hswrap "/usr/local/bin/$t"
done

HLS_VER="$(haskell-language-server-wrapper --numeric-version 2>/dev/null || true)"
GHC_VER="$(ghc --numeric-version 2>/dev/null || true)"
echo "✅ HLS ${HLS_VER:-?} linked."
echo -n "   haskell-language-server-wrapper → "; command -v haskell-language-server-wrapper || true

if [[ -n "$GHC_VER" && ! -x "${GHCUP_BIN}/haskell-language-server-${GHC_VER}" ]]; then
  SUPPORTED="$(cd "$GHCUP_BIN" && ls haskell-language-server-[0-9]* 2>/dev/null \
               | sed 's/^haskell-language-server-//' | tr '\n' ' ')"
  echo "⚠️  HLS ${HLS_VER:-?} has no server for GHC ${GHC_VER}, so editors will report an error." >&2
  echo "   It supports: ${SUPPORTED:-none}. Pick one of those with haskell:<ghc>, or pin an HLS" >&2
  echo "   that supports ${GHC_VER} with lsp:hls@<version>." >&2
elif [[ -n "$GHC_VER" ]]; then
  # A server for this GHC can still be built against another build of it: ghcup's unofficial
  # aarch64 HLS bindists are, and exit on every file with "GHC ABIs don't match". Type-check one
  # file now, so that shows here rather than as a silent editor.
  PROBE="$(mktemp -d)"
  echo 'main = pure ()' > "${PROBE}/Main.hs"
  PROBE_OUT="$(cd "$PROBE" && HOME="$PROBE" timeout 300 haskell-language-server-wrapper typecheck Main.hs 2>&1 || true)"
  if [[ "$PROBE_OUT" == *"GHC ABIs don't match"* ]]; then
    echo "⚠️  HLS ${HLS_VER:-?} was built against a different GHC ${GHC_VER} than the one installed" >&2
    echo "   (\"GHC ABIs don't match\"), so editors will get no Haskell server. ghcup's unofficial" >&2
    echo "   $(uname -m) builds of HLS do this. Try another GHC with haskell:<ghc>, or another HLS" >&2
    echo "   with lsp:hls@<version>." >&2
  fi
  rm -rf "$PROBE"
fi

cat <<'EON'
ℹ️ Ready to use:
- Editors start it as: haskell-language-server-wrapper --lsp
- Fresh, Helix, TTT, and Neovim pick it up for Haskell files
- Check a project:     cd my-project && haskell-language-server-wrapper

Notes:
- The first open of a project builds its cabal plan, which takes a while.
- See: https://haskell-language-server.readthedocs.io
EON
