#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# booth-web-preview-notebook--setup.sh
# Web Preview for the notebook variant: the same controls code-server's
# extension shows, opened from a "Web Preview" tile in the JupyterLab Launcher.
#
# jupyter-server-proxy supplies only the tile — its launcher entries can open a
# JupyterLab tab on any same-origin path. It does not carry the application
# traffic: it forwards the Jupyter session cookie to whatever it proxies, so
# /proxy/<port>/ is served by the wrapper's nginx instead, behind a check of the
# Jupyter login (see booth-web-preview/nginx-notebook.conf.template).
#
# Prereqs: python--setup.sh and notebook--setup.sh already ran.
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)" >&2; exit 1; }
HOME=/root

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f /etc/profile.d/70-cb-notebook--profile.sh ] && source /etc/profile.d/70-cb-notebook--profile.sh 2>/dev/null || true
if [[ -z "${CB_NOTEBOOK_VENV_DIR:-}" || ! -x "${CB_NOTEBOOK_VENV_DIR}/bin/jupyter-lab" ]]; then
  source "$SCRIPT_DIR/libs/skip-setup.sh"
  skip_setup "$(basename "$0")" "JupyterLab (notebook--setup.sh) not installed"
fi

# 4.x is the line for JupyterLab 4, which notebook--setup.sh installs today.
JUPYTER_SERVER_PROXY_VERSION="${JUPYTER_SERVER_PROXY_VERSION:-4.6.0}"

DEST="${CB_WEB_PREVIEW_DIR:-/usr/local/share/booth-web-preview}"
mkdir -p "$DEST"
cp -R "$SCRIPT_DIR/booth-web-preview/." "$DEST/"

env PIP_CACHE_DIR="${PIP_CACHE_DIR:-/opt/pip-cache}" PIP_DISABLE_PIP_VERSION_CHECK=1 \
  "${CB_NOTEBOOK_VENV_DIR}/bin/python" -m pip install "jupyter-server-proxy==${JUPYTER_SERVER_PROXY_VERSION}"

# The entry's own /booth-web-preview/ route is never the point: path_info sends
# the tile to the controls nginx serves at the site root, and new_browser_tab
# keeps them inside JupyterLab. Command-less, so nothing is started for it; the
# port is the wrapper's nginx, which is what that route would reach.
#
# A .py file, not jupyter_server_config.d/*.json: Jupyter reads that directory
# only to enable extensions. `.update` adds to ServerProxy.servers rather than
# replacing any the user configures in ~/.jupyter.
CONFIG_DIR="${CB_NOTEBOOK_VENV_DIR}/etc/jupyter"
mkdir -p "$CONFIG_DIR"
cat >"$CONFIG_DIR/jupyter_server_config.py" <<PY
# Written by booth-web-preview-notebook--setup.sh.
c.ServerProxy.servers.update({
    "booth-web-preview": {
        "port": 10000,
        "new_browser_tab": False,
        "launcher_entry": {
            "title": "Web Preview",
            "path_info": "booth-preview/index.html",
            "icon_path": "${DEST}/globe.svg",
            "category": "Other",
        },
    },
    # The same controls, opened on viewmd; they start it when it is not
    # running. The hash is the controls' own {"address": ...} start state.
    "booth-markdown-viewer": {
        "port": 10000,
        "new_browser_tab": False,
        "launcher_entry": {
            "title": "Markdown Viewer",
            "path_info": "booth-preview/index.html#%7B%22address%22%3A%22http%3A%2F%2Fbooth%3A8765%2F%22%7D",
            "icon_path": "${DEST}/markdown.svg",
            "category": "Other",
        },
    },
})

# window.jupyterapp, so the controls (same-origin with JupyterLab) can open
# more preview tabs and name theirs after the page they show.
c.LabApp.expose_app_in_browser = True
PY
chmod -R a+rX "$DEST"
chmod a+r "$CONFIG_DIR/jupyter_server_config.py"

echo "✅ Web Preview installed for JupyterLab (jupyter-server-proxy ${JUPYTER_SERVER_PROXY_VERSION})."
echo "ℹ️ In the notebook variant, open Web Preview from the Launcher and enter a port, e.g. 3000,"
echo "   or Markdown Viewer to browse the project's Markdown files."
