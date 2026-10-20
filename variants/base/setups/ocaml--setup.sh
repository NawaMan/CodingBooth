#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# cb-version: 0.1.0
#
# EXPERIMENTAL: no tests or example ship with this setup yet.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
    cat <<'EOF'
Usage: ocaml--setup.sh [--version X.Y.Z] [--tools-revision N]

Installs a prebuilt OCaml compiler, Dune, UTop and OCamlFormat, with opam.
Defaults: --version 5.4.1 --tools-revision 1
Example: setup ocaml --version 5.4.1

Archives are built by NawaMan/CodingBoothPrebuilt for each Ubuntu release and CPU.
An unavailable archive is an error; this setup never compiles from source.
To request a source build, run that repository's workflow with tools=ocaml and
versions=<version>-tools<revision>. Additional opam packages may compile locally.
EOF
}

OCAML_VERSION=5.4.1
TOOLS_REVISION=1
while (( $# )); do
    case "$1" in
        --version|--tools-revision)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 2; }
            if [[ "$1" == --version ]]; then OCAML_VERSION="$2"; else TOOLS_REVISION="$2"; fi
            shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "❌ Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done
[[ "$OCAML_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$TOOLS_REVISION" =~ ^[1-9][0-9]*$ ]] || {
    echo '❌ Expected --version X.Y.Z and a positive --tools-revision.' >&2; exit 2;
}
[[ $EUID -eq 0 ]] || { echo '❌ Run as root (sudo).' >&2; exit 1; }
case "$(uname -m)" in
    x86_64|amd64|aarch64|arm64) ;;
    *) echo "❌ Unsupported CPU: $(uname -m)" >&2; exit 1 ;;
esac

SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
source "$SETUP_LIBS_DIR/prebuilt-source.sh"
BUNDLE_VERSION="$OCAML_VERSION-tools$TOOLS_REVISION"
PREFIX="/opt/ocaml/ocaml-$BUNDLE_VERSION"
if ! cb_prebuilt_install ocaml "$BUNDLE_VERSION" native "$PREFIX"; then
    echo "❌ No prebuilt OCaml $BUNDLE_VERSION for this Ubuntu release and CPU." >&2
    echo "Request tools=ocaml, versions=$BUNDLE_VERSION in NawaMan/CodingBoothPrebuilt Actions." >&2
    echo 'Source compilation is not started automatically.' >&2
    exit 1
fi
[[ "$(cat "$PREFIX/BUNDLE-VERSION")" == "$BUNDLE_VERSION" && -x "$PREFIX/bin/opam" \
    && -x "$PREFIX/opam/booth/bin/ocamlc" ]] || {
    echo "❌ Invalid OCaml bundle at $PREFIX" >&2; exit 1;
}

# Native compilation needs a C linker; UTop also needs the runtime libev library.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends build-essential m4 pkg-config git rsync unzip \
    ca-certificates curl libgmp10 libev4 libzstd1 libglpk40
rm -rf /var/lib/apt/lists/*
chmod -R a+rX "$PREFIX"
ln -sfn "$PREFIX" /opt/ocaml-current
mkdir -p /usr/local/bin /usr/share/startup.d /etc/profile.d

cat > /usr/local/bin/cb-ocaml-tool <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/ocaml-current/env.sh
tool=$(basename "$0")
if [[ "$tool" == opam ]]; then
    exec /opt/ocaml-current/bin/opam "$@"
fi
exec "$OCAML_HOME/bin/$tool" "$@"
EOF
chmod 755 /usr/local/bin/cb-ocaml-tool
for executable in "$PREFIX/opam/booth/bin/"*; do
    [[ -f "$executable" && -x "$executable" ]] || continue
    ln -sfn /usr/local/bin/cb-ocaml-tool "/usr/local/bin/$(basename "$executable")"
done
ln -sfn /usr/local/bin/cb-ocaml-tool /usr/local/bin/opam

cat > /etc/profile.d/62-cb-ocaml--profile.sh <<'EOF'
# Use the selected prebuilt compiler and its matching package environment.
source /opt/ocaml-current/env.sh
EOF
chmod 644 /etc/profile.d/62-cb-ocaml--profile.sh

cat > /usr/share/startup.d/62-cb-ocaml--startup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/ocaml-current/env.sh
# The booth user must be able to add project packages to this container's opam root.
if [[ "$(stat -c %u "$OPAMROOT")" != "$(id -u)" ]]; then
    sudo chown -R "$(id -u):$(id -g)" "$OPAMROOT"
fi
EOF
chmod 755 /usr/share/startup.d/62-cb-ocaml--startup.sh

echo "✅ OCaml $OCAML_VERSION installed from prebuilt bundle $BUNDLE_VERSION."
ocamlc -version
cat <<'EOF'
ℹ️ Ready to use:
  ocamlc -o hello hello.ml   # compile bytecode
  dune build                # build a project
  utop                      # interactive console
  ocamlformat --help        # formatter
  opam install <package>    # additional packages may compile from source
EOF
