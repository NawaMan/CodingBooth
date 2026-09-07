#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# mojo-nb-kernel--setup.sh
#
# Official Modular notebooks: a Python ipykernel plus `import mojo.notebook`,
# which registers the %%mojo cell magic. Registers that kernel under the name
# "mojo" so it appears in the Jupyter picker. Auto-imports the magic via an
# IPython startup file so the first cell does not have to.
#
# Prereqs:
#   - python--setup.sh, mojo--setup.sh, notebook--setup.sh
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

if [ "$EUID" -ne 0 ]; then
  echo "❌ This script must be run as root (use sudo)." >&2
  exit 1
fi
HOME=/root

[ -f /etc/profile.d/53-cb-python--profile.sh ] && source /etc/profile.d/53-cb-python--profile.sh 2>/dev/null || true
[ -f /etc/profile.d/70-cb-notebook--profile.sh ] && source /etc/profile.d/70-cb-notebook--profile.sh 2>/dev/null || true

JUPYTER_KERNEL_PREFIX="${JUPYTER_KERNEL_PREFIX:-/usr/local}"
KERNEL_NAME="${KERNEL_NAME:-mojo}"
KERNEL_DISPLAY_NAME="${KERNEL_DISPLAY_NAME:-Mojo}"
CB_PYTHON_HOME="${CB_PYTHON_HOME:-/opt/python}"
PY="${CB_PYTHON_HOME}/bin/python"
STARTUP_FILE="/usr/share/startup.d/75-cb-mojo-nb-kernel--startup.sh"
SKEL_STARTUP="/etc/skel/.ipython/profile_default/startup/00-mojo-notebook.py"

if [[ ! -x "$PY" ]]; then
  echo "❌ Python is not set up. Run python--setup.sh first." >&2
  exit 1
fi

if ! command -v mojo >/dev/null 2>&1 && [[ ! -x "${CB_PYTHON_HOME}/bin/mojo" ]]; then
  echo "❌ Mojo is not installed. Run mojo--setup.sh first." >&2
  exit 1
fi

if ! "$PY" -c 'import importlib.util as u; raise SystemExit(0 if u.find_spec("mojo.notebook") else 1)'; then
  echo "❌ The installed mojo package has no mojo.notebook (%%mojo magic)." >&2
  exit 1
fi

if ! "$PY" -c 'import importlib.util as u; raise SystemExit(0 if all(u.find_spec(m) for m in ("ipykernel", "jupyter_client")) else 1)'; then
  echo "❌ Jupyter/ipykernel is missing. Run notebook--setup.sh first." >&2
  exit 2
fi

echo "🧩 Registering Mojo notebook kernel at ${JUPYTER_KERNEL_PREFIX} ..."
"$PY" -m ipykernel install \
  --prefix="${JUPYTER_KERNEL_PREFIX}" \
  --name="${KERNEL_NAME}" \
  --display-name="${KERNEL_DISPLAY_NAME}"

KDIR="${JUPYTER_KERNEL_PREFIX}/share/jupyter/kernels/${KERNEL_NAME}"
chmod -R a+rX "${KDIR}" 2>/dev/null || true

install -d "$(dirname "$SKEL_STARTUP")"
cat > "$SKEL_STARTUP" <<'PY'
# Auto-enable Modular's %%mojo cell magic.
import mojo.notebook
PY
chmod 644 "$SKEL_STARTUP"

# Container home is recreated per run; seed the IPython startup for the user.
cat > "${STARTUP_FILE}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.ipython/profile_default/startup"
cat > "$HOME/.ipython/profile_default/startup/00-mojo-notebook.py" <<'PY'
import mojo.notebook
PY
chmod 644 "$HOME/.ipython/profile_default/startup/00-mojo-notebook.py"
EOF
chmod 755 "${STARTUP_FILE}"

echo
echo "🔎 Kernels:"
"$PY" -m jupyter kernelspec list 2>/dev/null || true

echo
echo "✅ Mojo notebook kernel installed."
echo "   Kernel name:      ${KERNEL_NAME}"
echo "   Display name:     ${KERNEL_DISPLAY_NAME}"
echo "   Kernelspec dir:   ${KDIR}"
echo "   Magic:            import mojo.notebook  (%%mojo cells, each with main())"
echo
echo "ℹ️ Ready to use:"
cat <<'EOF'
  # In Jupyter, pick kernel "Mojo", then:
  %%mojo

  def main():
      print("Hello from Mojo")
EOF
