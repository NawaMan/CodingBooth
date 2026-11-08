#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 2.9.0

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--version <X.Y.Z>|latest]
  $0 [<X.Y.Z>|latest]

Examples:
  $0                         # install the pinned default (2.0.0)
  $0 --version 2.0.0         # pin a specific version
  $0 2.0.0                   # same, in the form a Boothfile emits
  $0 --version latest        # install the latest GitHub release

Notes:
- Installs folio (EnvFolio) to /usr/local/bin/folio
- Also installs pass, which EnvFolio is built on, when it is missing
- Part of the base image: every variant already has it
- Checksums are verified against the release's SHA256SUMS
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

# ---- defaults / args ----
# No version given means the pinned default, not 'latest': the base image then
# gets the same EnvFolio on every build, and an upstream release that is not out
# yet (a draft is invisible to the API) cannot silently pick an older one.
ENVFOLIO_DEFAULT_VER="2.0.0"   # also the fallback when 'latest' cannot be resolved
REQ_VER="$ENVFOLIO_DEFAULT_VER"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) shift; REQ_VER="${1:-latest}"; shift ;;
    -h|--help) usage; exit 0 ;;
    # `setup envfolio 0.6.0` in a Boothfile compiles to a positional argument,
    # so accept that spelling too.
    -*) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
    *) REQ_VER="$1"; shift ;;
  esac
done
REQ_VER="${REQ_VER#v}"

# ---- base deps ----
# EnvFolio is one bash script on top of pass. gpg, git, tar, gzip and tree are
# already in the base image; pass is not. --no-install-recommends keeps out
# xclip/qrencode: the clipboard is only needed for `-c`, and EnvFolio says what
# to install when it is.
MISSING=()
command -v curl >/dev/null 2>&1 || MISSING+=(curl ca-certificates)
command -v pass >/dev/null 2>&1 || MISSING+=(pass)
if [[ ${#MISSING[@]} -gt 0 ]]; then
  apt--install.sh "${MISSING[@]}"
fi

# ---- resolve version ----
if [[ "$REQ_VER" == "latest" ]]; then
  VERSION=$(curl --retry 3 --retry-delay 2 -fsSL https://api.github.com/repos/NawaMan/EnvFolio/releases/latest \
            | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"v[^"]+"' | head -1 \
            | sed -E 's/.*"v([^"]+)".*/\1/' || true)
  if [[ -z "$VERSION" ]]; then
    # See elixir--setup.sh: the GitHub API is rate-limited, so degrade to the
    # pinned default instead of failing the build.
    echo "⚠️  Could not resolve the latest EnvFolio release; using ${ENVFOLIO_DEFAULT_VER}."
    VERSION="$ENVFOLIO_DEFAULT_VER"
  fi
else
  VERSION="$REQ_VER"
fi

# ---- install folio ----
# A single bash script, the same for every architecture. Since 0.4.0 the command
# (and the release asset) is `folio`; the app is still EnvFolio.
echo "⬇️  Installing EnvFolio (folio) v${VERSION} ..."
BASE_URL="https://github.com/NawaMan/EnvFolio/releases/download/v${VERSION}"
ASSET="folio"
TMP_DIR=$(mktemp -d)
curl -fsSL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 5 \
  "${BASE_URL}/${ASSET}" -o "${TMP_DIR}/folio"

# Verify against the release's SHA256SUMS. A release without the checksum file
# leaves nothing to check, so warn rather than fail; a checksum that is present
# and wrong is fatal.
if curl --retry 5 --retry-delay 3 --retry-all-errors -fsSL "${BASE_URL}/SHA256SUMS" -o "${TMP_DIR}/SHA256SUMS" 2>/dev/null; then
  EXPECTED=$(awk -v asset="$ASSET" '$2 == asset || $2 == "*"asset {print $1}' "${TMP_DIR}/SHA256SUMS" | head -1)
  if [[ -n "$EXPECTED" ]]; then
    ACTUAL=$(sha256sum "${TMP_DIR}/folio" | awk '{print $1}')
    if [[ "$EXPECTED" != "$ACTUAL" ]]; then
      echo "❌ Checksum mismatch for ${ASSET}: expected ${EXPECTED}, got ${ACTUAL}"
      rm -rf "${TMP_DIR}"
      exit 1
    fi
    echo "🔒 Checksum verified."
  else
    echo "⚠️  ${ASSET} is not listed in SHA256SUMS; skipping checksum verification."
  fi
else
  echo "⚠️  No SHA256SUMS published for v${VERSION}; skipping checksum verification."
fi

install -m 755 "${TMP_DIR}/folio" /usr/local/bin/folio
rm -rf "${TMP_DIR}"
# An image built on top of one with EnvFolio 0.3.0 or older still carries the
# old command, which no longer matches the store this one uses.
rm -f /usr/local/bin/envfolio

# ---- startup: a store seeded from the host (envfolio+seed) ----
# The CLI copies the items named by CB_FOLIO_SEED (`folio exec` arguments) from the host's store,
# still encrypted, into .booth/.tmp/folio-seed/ before the container starts, with the store's
# .gpg-id and public key. This hook makes that the booth's store. CB_FOLIO_SEED_MODE:
#   seed (default) -- only when the booth has no store yet; one there (e.g. +store-cache) is kept.
#   fill           -- also add the items an existing store lacks, when it has the same key (a store
#                     with another key could not read them: secrets are encrypted to the seed's key,
#                     texts signed by it). What is already there is never replaced.
# Paths are kept (@app2/@prod/...), so the same `folio exec` means the same here as on the host.
STARTUP_FILE="/usr/share/startup.d/60-cb-envfolio--startup.sh"
mkdir -p "$(dirname "$STARTUP_FILE")"
cat > "$STARTUP_FILE" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail

SEED="${CB_FOLIO_SEED_DIR:-/home/coder/code/.booth/.tmp/folio-seed}"   # override: tests only
[[ -n "${CB_FOLIO_SEED:-}" && -s "$SEED/.gpg-id" ]] || exit 0
MODE="${CB_FOLIO_SEED_MODE:-seed}"
STORE="$(folio path 2>/dev/null)" || STORE=""
[[ -n "$STORE" ]] || STORE="${FOLIO_STORE_DIR:-$HOME/.folio}"

say() { echo "EnvFolio seed: $*"; }

# The texts are signed by the store's key; folio shows one only when that signature checks out.
[[ -s "$SEED/pubkey.asc" ]] && gpg --batch --quiet --import "$SEED/pubkey.asc" >/dev/null 2>&1

# The store key's private key files come with every seed, but not through here: they go the way
# every key reaches a booth, .booth/.tmp/gnupg-keys/, imported by the gnupg startup hook (55),
# which runs before this one.

# commit_store MESSAGE -- record what was added, as folio does for its own changes.
commit_store() {
    git -C "$STORE" add -A >/dev/null 2>&1 \
        && git -C "$STORE" -c user.name="CodingBooth" -c user.email="booth@localhost" \
               commit -q -m "$1" >/dev/null 2>&1
    true
}

# Each item of the seed: <name>.gpg, or <name>.txt with its .txt.sig.
seed_items() {
    (cd "$SEED" && find . -type f \( -name '*.gpg' -o -name '*.txt' \) | sed 's|^\./||' | sort)
}

if [[ ! -s "$STORE/.gpg-id" || ! -e "$STORE/.git" ]]; then
    if [[ -d "$STORE" && -n "$(ls -A "$STORE" 2>/dev/null)" ]]; then
        say "$STORE is not an EnvFolio store and not empty; not seeding it."
        exit 0
    fi
    mkdir -p "$STORE" && chmod 700 "$STORE"
    (cd "$SEED" && find . -mindepth 1 -maxdepth 1 ! -name pubkey.asc ! -name private-keys -exec cp -a {} "$STORE/" \;)
    git -C "$STORE" init -q >/dev/null 2>&1
    commit_store "Seeded from the host: folio exec $CB_FOLIO_SEED"
    say "made $STORE from the host's items ($(seed_items | wc -l))."
    exit 0
fi

if [[ "$MODE" != "fill" ]]; then
    say "$STORE already exists; kept as it is (CB_FOLIO_SEED_MODE=fill adds missing items)."
    exit 0
fi
if ! cmp -s "$SEED/.gpg-id" "$STORE/.gpg-id"; then
    say "$STORE uses another key than the host's store; nothing added (its items could not be read here)."
    exit 0
fi
added=0
while IFS= read -r item; do
    [[ -e "$STORE/$item" ]] && continue
    mkdir -p "$(dirname "$STORE/$item")"
    cp -a "$SEED/$item" "$STORE/$item" || continue
    [[ "$item" == *.txt && -f "$SEED/$item.sig" ]] && cp -a "$SEED/$item.sig" "$STORE/$item.sig"
    added=$((added + 1))
done < <(seed_items)
(( added == 0 )) || commit_store "Filled from the host: folio exec $CB_FOLIO_SEED"
say "added $added missing item(s) to $STORE."
true
EOF
chmod 755 "$STARTUP_FILE"

# ---- friendly summary ----
echo "✅ folio installed."
echo -n "   folio → "; folio version 2>/dev/null || true

cat <<'EON'
ℹ️ Ready to use:
- Create the store:          folio init
- Add a text / a secret:     folio insert text gh/user   |   folio insert secret gh/token
- Run with them as env vars: folio exec --secrets gh -- gh auth status
- Move items to another booth: folio export   |   folio import

Notes:
- The store is ~/.folio (or $FOLIO_STORE_DIR) and its GPG key lives in
  ~/.gnupg; both are lost when the container is recreated. Select
  tools/envfolio+store-cache to keep them in .booth/cache/, or use
  `folio backup` / `restore`.
- See: https://github.com/NawaMan/EnvFolio
EON
