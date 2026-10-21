# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0

# ---- GHC into a ghcup tree, prebuilt when possible ----
#
# `ghcup install ghc` downloads a binary distribution in seconds, then spends 6-7 minutes
# in its install step. CodingBoothPrebuilt publishes GHC already installed (ghcup's own
# .ghcup/ghc/<version> layout, built at /opt/ghc/ghc-<version>), which unpacks in about
# 10 seconds. Unpacked into .ghcup/ghc/<version>, ghcup lists it as installed and can
# `ghcup set` it like one it installed itself.
#
# Source with:
#   SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
#   source "${SETUP_LIBS_DIR}/ghc-source.sh"

source "$(dirname "${BASH_SOURCE[0]}")/prebuilt-source.sh"

# cb_ghc_install <ghcup> <version|recommended|latest>
#   Installs that GHC into the ghcup tree <ghcup> lives in (GHCUP_INSTALL_BASE_PREFIX must
#   point at it), from CodingBoothPrebuilt when a build is published for it, else with
#   `ghcup install ghc`. Does not change ghcup's default GHC. Sets CB_GHC_VERSION to the
#   numeric version.
cb_ghc_install() {
  local ghcup="$1" want="$2" version dest built f tool
  version="$want"
  if ! [[ "$want" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    # A tag (recommended, latest): ghcup's raw list is "ghc <version> <tag,tag,...> ...".
    version="$("$ghcup" list -t ghc -c available -r 2>/dev/null \
      | awk -v t="$want" '{ n = split($3, tags, ","); for (i = 1; i <= n; i++) if (tags[i] == t) { print $2; exit } }')"
  fi

  dest="$(dirname "$(dirname "$ghcup")")/ghc/${version}"
  if [ -n "$version" ] && [ ! -x "${dest}/bin/ghc" ] \
     && cb_prebuilt_install ghc "$version" native "$dest"; then
    # The wrapper scripts in bin/ name the prefix the build used.
    built="/opt/ghc/ghc-${version}"
    grep -lr "$built" "${dest}/bin" | xargs -r sed -i "s|${built}|${dest}|g"
    rm -f "${dest}/BUILD-INFO.txt"
    # The versioned links `ghcup install` adds: ghc-9.12.4 and ghc-9.12, haddock-9.12.4 for
    # haddock-ghc-9.12.4, and so on. `ghcup set` adds only the unversioned ones.
    for f in "${dest}"/bin/*-"${version}"; do
      tool="$(basename "$f" "-${version}")"
      tool="${tool%-ghc}"
      ln -sfn "../ghc/${version}/bin/$(basename "$f")" "$(dirname "$ghcup")/${tool}-${version}"
      ln -sfn "../ghc/${version}/bin/$(basename "$f")" "$(dirname "$ghcup")/${tool}-${version%.*}"
    done
  else
    echo "📦 Installing GHC ${want} with ghcup..."
    "$ghcup" install ghc "$want"
    [ -n "$version" ] || version="$("$ghcup" list -t ghc -c installed -r 2>/dev/null \
      | awk -v t="$want" '{ n = split($3, tags, ","); for (i = 1; i <= n; i++) if (tags[i] == t) { print $2; exit } }')"
  fi
  CB_GHC_VERSION="$version"
}
