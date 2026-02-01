#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 [--packages "Pkg1,Pkg2,..."] [--no-cran] [--repo <CRAN_URL>]

Examples:
  $0                                   # Install latest R + shared site-library
  $0 --packages "tidyverse,data.table" # preinstall common packages
  $0 --no-cran                         # don't add CRAN APT repo; use distro packages
  $0 --repo https://cloud.r-project.org # override CRAN mirror URL

Notes:
- Installs r-base and r-base-dev
- Shared site library at /opt/R/site-library (world-writable)
- Exposes R and Rscript via /usr/local/bin (non-login shells OK)
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)."; exit 1; }

# ---- args ----
PKGS_LIST=""
USE_CRAN=1
CRAN_URL_DEFAULT="https://cloud.r-project.org"
CRAN_URL="$CRAN_URL_DEFAULT"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --packages) shift; PKGS_LIST="${1:-}"; shift ;;
    --no-cran)  USE_CRAN=0; shift ;;
    --repo)     shift; CRAN_URL="${1:-$CRAN_URL_DEFAULT}"; shift ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

set -o pipefail
export DEBIAN_FRONTEND=noninteractive

# ---- base deps ----
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gnupg lsb-release software-properties-common locales
rm -rf /var/lib/apt/lists/*

# Ensure UTF-8 locale (R likes this)
sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen || true
locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# ---- Optional: add CRAN APT repo on Ubuntu ----
. /etc/os-release
ID_LIKE_LC="$(printf '%s' "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
IS_UBUNTU=0
if [[ "${ID:-}" == "ubuntu" || "$ID_LIKE_LC" == *"ubuntu"* ]]; then
  IS_UBUNTU=1
fi

if [[ $USE_CRAN -eq 1 && $IS_UBUNTU -eq 1 ]]; then
  CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
  [[ -n "$CODENAME" ]] || { echo "❌ Could not determine Ubuntu codename."; exit 1; }

  # CRAN provides suites like noble-cran40, jammy-cran40, etc.
  CRAN_SUITE="${CODENAME}-cran40"
  install -d /usr/share/keyrings
  curl -fsSL "${CRAN_URL}/bin/linux/ubuntu/marutter_pubkey.asc" -o /usr/share/keyrings/cran-archive-keyring.asc
  # Convert to gpg keyring if needed
  gpg --dearmor </usr/share/keyrings/cran-archive-keyring.asc >/usr/share/keyrings/cran-archive-keyring.gpg 2>/dev/null || true

  echo "deb [signed-by=/usr/share/keyrings/cran-archive-keyring.gpg] ${CRAN_URL}/bin/linux/ubuntu ${CRAN_SUITE}/" \
    >/etc/apt/sources.list.d/cran-r.list

  apt-get update
fi

# ---- install R base ----
apt-get install -y --no-install-recommends r-base r-base-dev r-recommended
rm -rf /var/lib/apt/lists/*

# ---- detect version & normalize /opt layout ----
R_BIN="$(command -v R)"
RS_BIN="$(command -v Rscript)"
[[ -x "$R_BIN" && -x "$RS_BIN" ]] || { echo "❌ R or Rscript not found after installation."; exit 1; }

R_MAJOR_MINOR="$("$R_BIN" --version | sed -n '1s/.*[[:space:]]\([0-9]\+\.[0-9]\+\).*/\1/p')"
[[ -n "$R_MAJOR_MINOR" ]] || R_MAJOR_MINOR="unknown"

INSTALL_PARENT=/opt/R
TARGET_DIR="${INSTALL_PARENT}/R-${R_MAJOR_MINOR}"
LINK_DIR=/opt/R-stable
BIN_DIR=/usr/local/bin
SITE_LIB=/opt/R/site-library

rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR/bin" "$SITE_LIB"
chmod -R 0777 "$SITE_LIB" || true

# Symlink the system binaries into /opt layout
ln -sfn "$R_BIN"  "$TARGET_DIR/bin/R"
ln -sfn "$RS_BIN" "$TARGET_DIR/bin/Rscript"

# Stable link
ln -sfn "$TARGET_DIR" "$LINK_DIR"

# ---- Profile (login shells): PATH + shared site library + default repo ----
cat >/etc/profile.d/99-r--profile.sh <<EOF
# R under /opt
export R_HOME=$LINK_DIR
export PATH="\$R_HOME/bin:\$PATH"
# Shared site library for all users/CI
export R_LIBS_SITE=${SITE_LIB}
# Default CRAN repo (can be overridden in user ~/.Rprofile)
export R_DEFAULT_CRAN_MIRROR=${CRAN_URL}
EOF
chmod 0644 /etc/profile.d/99-r--profile.sh

# Also configure system-wide R settings:
install -d /etc/R
cat >/etc/R/Renviron.site <<EOF
R_LIBS_SITE=${SITE_LIB}
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF

# Rprofile.site to set a sensible default CRAN mirror (if missing)
cat >/etc/R/Rprofile.site <<EOF
local({
  repos <- getOption("repos")
  if (is.null(repos) || length(repos) == 0L || repos["CRAN"] %in% c(NULL, "@CRAN@")) {
    options(repos = c(CRAN = "${CRAN_URL}"))
  }
})
EOF

# ---- Non-login wrappers ----
install -d "$BIN_DIR"
cat >"${BIN_DIR}/rwrap" <<'EOF'
#!/bin/sh
: "${R_HOME:=/opt/R-stable}"
: "${R_LIBS_SITE:=/opt/R/site-library}"
: "${R_DEFAULT_CRAN_MIRROR:=https://cloud.r-project.org}"
export R_HOME R_LIBS_SITE PATH="$R_HOME/bin:$PATH" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
tool="$(basename "$0")"
exec "$R_HOME/bin/$tool" "$@"
EOF
chmod +x "${BIN_DIR}/rwrap"
ln -sfn "${BIN_DIR}/rwrap" "${BIN_DIR}/R"
ln -sfn "${BIN_DIR}/rwrap" "${BIN_DIR}/Rscript"

# ---- Optional: preinstall packages into the shared site library ----
if [[ -n "$PKGS_LIST" ]]; then
  # Turn "a,b,c" or "a b c" into c("a","b","c")
  PKGS_VEC="$(printf '%s' "$PKGS_LIST" | tr ',' ' ' | xargs -n1 | awk '{printf "\"%s\",",$0}' | sed 's/,$//')"
  echo "📦 Installing CRAN packages into ${SITE_LIB}: [$PKGS_VEC]"
  R_LIBS_SITE="$SITE_LIB" R_DEFAULT_CRAN_MIRROR="$CRAN_URL" \
    "${BIN_DIR}/Rscript" -e "options(repos=c(CRAN='${CRAN_URL}')); pkgs <- c($PKGS_VEC); install.packages(pkgs, Ncpus=parallel::detectCores());"
fi

# ---- Summary ----
echo "✅ R installed."
echo "   R version        → $("$BIN_DIR/R" --version | head -n1)"
echo "   Rscript version  → $("$BIN_DIR/Rscript" --version 2>&1 | head -n1)"
echo "   R_LIBS_SITE      → ${SITE_LIB}"
echo "   R_HOME           → ${LINK_DIR}"

cat <<'EON'
ℹ️ Ready to use:
- Try: R --version && Rscript --version
- Works in login & non-login shells (wrapper primes PATH + R_LIBS_SITE).
- Shared packages live in /opt/R/site-library (persist in CI to speed up builds).
- Change default CRAN mirror by editing /etc/R/Rprofile.site or setting options(repos=...).

Tips:
- Install packages system-wide: R -e 'install.packages(c("tidyverse","data.table"))'
- For dev headers: use r-base-dev (already installed).
- If you need Rcpp / compilation: ensure a C/C++ toolchain (clang/gcc) is present.
EON
