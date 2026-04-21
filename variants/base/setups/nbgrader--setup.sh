#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

usage() {
  cat <<USAGE
Usage:
  $0

Notes:
- Installs nbgrader (Jupyter assignment creation + auto-grading) via pip
- Requires the notebook template (JupyterLab) and python
- Enables nbgrader server + lab extensions system-wide
- See: https://nbgrader.readthedocs.io/
USAGE
}

# ---- root check ----
[[ $EUID -eq 0 ]] || { echo "❌ Run as root (sudo)"; exit 1; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

# ---- sanity: jupyter must be installed ----
if ! command -v jupyter >/dev/null 2>&1; then
  echo "❌ jupyter not found — the notebook template must be installed first."
  exit 1
fi

# ---- install nbgrader ----
echo "• Installing nbgrader (pip) ..."
pip install --no-cache-dir --break-system-packages nbgrader 2>/dev/null \
  || pip install --no-cache-dir nbgrader

# ---- enable nbgrader extensions system-wide ----
# The server extension is auto-enabled by pip install on modern nbgrader,
# but we enable explicitly to be robust across versions.
echo "• Enabling nbgrader server extension ..."
jupyter server extension enable --system --py nbgrader || \
  jupyter serverextension enable --system --py nbgrader || true

# JupyterLab extensions (Formgrader, Create Assignment, Assignment List)
# are shipped as prebuilt extensions in modern nbgrader — no extra build step.

# ---- summary ----
echo ""
echo "✅ nbgrader installed."
echo -n "   nbgrader → "; nbgrader --version 2>/dev/null || true
echo ""
echo "ℹ️  Getting started:"
echo "   1. In a course directory, run:   nbgrader quickstart <course_id>"
echo "   2. Start JupyterLab — the Formgrader tab appears automatically."
echo "   3. Docs: https://nbgrader.readthedocs.io/en/stable/user_guide/creating_and_grading_assignments.html"
