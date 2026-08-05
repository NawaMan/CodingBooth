#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# selenium--setup.sh — Install browser drivers (+ Chrome for Testing) for Selenium
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  \$0 [BROWSERS]
  \$0 [--browsers BROWSERS] [--chrome-version VERSION]

Arguments:
  BROWSERS   Comma-separated: chromium, firefox, or "all" (default: chromium)

Options:
  --browsers BROWSERS         Same as positional
  --chrome-version VERSION    Chrome for Testing channel/version
                              (default: Stable via last-known-good JSON)
  -h, --help                  Show this help

Notes:
- Installs matching browser + driver binaries under /opt/selenium
- Does NOT install language bindings (use pip-pkg:selenium, npm-pkg:selenium-webdriver, …)
- Ubuntu's apt chromium/firefox packages are snap stubs — we use Chrome for Testing
  and official geckodriver instead
- Chrome for Testing publishes linux64 only; on aarch64 we install Debian
  Bookworm's chromium + chromium-driver instead (same engine, arm64 build)
USAGE
}

[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }
HOME=/root

BROWSERS="chromium"
CHROME_VERSION="Stable"

if [[ $# -ge 1 && ! "$1" =~ ^-- ]]; then
  BROWSERS="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)         usage; exit 0 ;;
    --browsers)        shift; BROWSERS="${1:-$BROWSERS}"; shift ;;
    --chrome-version)  shift; CHROME_VERSION="${1:-Stable}"; shift ;;
    *) echo "❌ Unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$BROWSERS" == "all" ]]; then
  BROWSERS="chromium,firefox"
fi
BROWSER_LIST="${BROWSERS//,/ }"

export DEBIAN_FRONTEND=noninteractive
echo "• Installing browser runtime libraries and download tools ..."
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  unzip \
  jq \
  fonts-liberation \
  fonts-noto-color-emoji \
  libasound2t64 \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libdrm2 \
  libgbm1 \
  libgtk-3-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libx11-6 \
  libxcomposite1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxkbcommon0 \
  libxrandr2 \
  libxshmfence1 \
  xdg-utils
rm -rf /var/lib/apt/lists/*

INSTALL_ROOT="/opt/selenium"
BIN_DIR="${INSTALL_ROOT}/bin"
mkdir -p "${BIN_DIR}" "${INSTALL_ROOT}"

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)  CFT_PLATFORM="linux64"; GECKO_ASSET="linux64" ;;
  aarch64|arm64) CFT_PLATFORM="";       GECKO_ASSET="linux-aarch64" ;;
  *) echo "❌ Unsupported arch: $ARCH"; exit 1 ;;
esac

install_chrome_for_testing() {
  local version_label="$1"
  echo "⬇️  Installing Chrome for Testing (${version_label}) ..."

  if [[ -n "${CFT_PLATFORM}" ]]; then
    local json url_chrome url_driver ver
    json="$(curl -fsSL https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json)"
    if [[ "${version_label}" == "Stable" || "${version_label}" == "latest" || "${version_label}" == "stable" ]]; then
      ver="$(echo "$json" | jq -r '.channels.Stable.version')"
      url_chrome="$(echo "$json" | jq -r --arg p "$CFT_PLATFORM" '.channels.Stable.downloads.chrome[] | select(.platform==$p) | .url')"
      url_driver="$(echo "$json" | jq -r --arg p "$CFT_PLATFORM" '.channels.Stable.downloads.chromedriver[] | select(.platform==$p) | .url')"
    else
      # Explicit version: construct Chrome for Testing public CDN URLs.
      ver="${version_label#v}"
      url_chrome="https://storage.googleapis.com/chrome-for-testing-public/${ver}/${CFT_PLATFORM}/chrome-linux64.zip"
      url_driver="https://storage.googleapis.com/chrome-for-testing-public/${ver}/${CFT_PLATFORM}/chromedriver-linux64.zip"
    fi

    local tmp
    tmp="$(mktemp -d)"
    curl -fsSL "$url_chrome" -o "$tmp/chrome.zip"
    curl -fsSL "$url_driver" -o "$tmp/chromedriver.zip"
    unzip -q "$tmp/chrome.zip" -d "${INSTALL_ROOT}"
    unzip -q "$tmp/chromedriver.zip" -d "${INSTALL_ROOT}"
    rm -rf "$tmp"

    # Normalize layout: chrome-linux64/ and chromedriver-linux64/
    local chrome_bin driver_bin
    chrome_bin="$(find "${INSTALL_ROOT}" -type f -path '*/chrome-linux64/chrome' | head -1)"
    driver_bin="$(find "${INSTALL_ROOT}" -type f -path '*/chromedriver-linux64/chromedriver' | head -1)"
    [[ -n "$chrome_bin" ]] || { echo "❌ chrome binary not found after extract"; exit 1; }
    [[ -n "$driver_bin" ]] || { echo "❌ chromedriver binary not found after extract"; exit 1; }
    chmod a+x "$chrome_bin" "$driver_bin"
    ln -sfn "$chrome_bin" "${BIN_DIR}/chrome"
    ln -sfn "$chrome_bin" "${BIN_DIR}/google-chrome"
    ln -sfn "$driver_bin" "${BIN_DIR}/chromedriver"
    echo "   Chrome for Testing ${ver} → ${chrome_bin}"
    echo "   chromedriver → ${driver_bin}"
    return 0
  fi

  # aarch64: Chrome for Testing publishes no linux-arm64 build — not through the
  # CDN and not through @puppeteer/browsers, which fetches from the same place.
  # Debian Bookworm does build chromium and chromium-driver for arm64, and a
  # matched pair of those is exactly what Selenium needs.
  echo ""
  echo "⚠️  arm64: Chrome for Testing has no linux-arm64 build (${version_label} ignored)."
  echo "    Using Debian Bookworm's Chromium + chromium-driver instead — same"
  echo "    engine, and Selenium drives them through the usual chromedriver."
  echo ""
  cb-install-chromium.sh --with-driver

  local chrome_bin driver_bin
  chrome_bin="$(command -v chromium || command -v chromium-browser || true)"
  driver_bin="$(command -v chromedriver || true)"
  [[ -n "$chrome_bin" ]] || { echo "❌ chromium not found after install"; exit 1; }
  [[ -n "$driver_bin" ]] || { echo "❌ chromedriver not found after install"; exit 1; }

  # Selenium code and the `chrome` command both expect --no-sandbox in a
  # container; wrap rather than symlink so callers need no extra flags.
  cat >"${BIN_DIR}/chrome" <<EOF
#!/usr/bin/env bash
exec "${chrome_bin}" --no-sandbox --disable-dev-shm-usage "\$@"
EOF
  chmod 0755 "${BIN_DIR}/chrome"
  ln -sfn "${BIN_DIR}/chrome" "${BIN_DIR}/google-chrome"
  ln -sfn "$driver_bin" "${BIN_DIR}/chromedriver"
}

install_geckodriver() {
  echo "⬇️  Installing geckodriver ..."
  local tag url tmp
  tag="$(curl -fsSL https://api.github.com/repos/mozilla/geckodriver/releases/latest | jq -r '.tag_name')"
  url="https://github.com/mozilla/geckodriver/releases/download/${tag}/geckodriver-${tag}-${GECKO_ASSET}.tar.gz"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/geckodriver.tgz"
  tar -xzf "$tmp/geckodriver.tgz" -C "$tmp"
  install -m 755 "$tmp/geckodriver" "${BIN_DIR}/geckodriver"
  rm -rf "$tmp"
  echo "   geckodriver ${tag} → ${BIN_DIR}/geckodriver"
  echo "   Note: Firefox browser itself is not installed (Ubuntu ships snap stubs)."
  echo "         Pair geckodriver with a Firefox you provide, or use chromium only."
}

for b in $BROWSER_LIST; do
  case "$b" in
    chromium|chrome) install_chrome_for_testing "$CHROME_VERSION" ;;
    firefox)         install_geckodriver ;;
    *) echo "❌ Unknown browser: $b (use chromium, firefox, or all)"; exit 2 ;;
  esac
done

chmod -R a+rX "${INSTALL_ROOT}"
# Ensure binaries are executable for non-root users
find "${INSTALL_ROOT}" -type f \( -name chrome -o -name chromedriver -o -name geckodriver \) -exec chmod a+x {} +

LEVEL=60
PROFILE_FILE="/etc/profile.d/${LEVEL}-cb-selenium--profile.sh"
cat > "${PROFILE_FILE}" <<PROF
# Profile: Selenium browser drivers
export PATH="${BIN_DIR}:\$PATH"
export SE_CHROME_PATH="${BIN_DIR}/chrome"
export CHROME_BIN="${BIN_DIR}/chrome"
export CHROMEDRIVER_PATH="${BIN_DIR}/chromedriver"
export GECKODRIVER_PATH="${BIN_DIR}/geckodriver"
# Selenium 4+ Selenium Manager still works; these help bindings that honor env vars.
export SE_MANAGER_PATH="\${SE_MANAGER_PATH:-}"
PROF
chmod 644 "${PROFILE_FILE}"

echo ""
echo "✅ Selenium drivers installed."
echo "   Root     : ${INSTALL_ROOT}"
echo "   PATH dir : ${BIN_DIR}"
echo "   Browsers : ${BROWSER_LIST}"
command -v chromedriver >/dev/null 2>&1 || export PATH="${BIN_DIR}:$PATH"
if [[ -x "${BIN_DIR}/chromedriver" ]]; then
  echo -n "   chromedriver → "; "${BIN_DIR}/chromedriver" --version 2>/dev/null | head -1 || true
fi
if [[ -x "${BIN_DIR}/chrome" ]]; then
  echo -n "   chrome       → "; "${BIN_DIR}/chrome" --version 2>/dev/null | head -1 || true
fi
if [[ -x "${BIN_DIR}/geckodriver" ]]; then
  echo -n "   geckodriver  → "; "${BIN_DIR}/geckodriver" --version 2>/dev/null | head -1 || true
fi
echo ""
echo "  Language bindings (install separately):"
echo "   python+pip-pkg:selenium"
echo "   nodejs+npm-pkg:selenium-webdriver"
echo "   java / go / etc. as needed"
