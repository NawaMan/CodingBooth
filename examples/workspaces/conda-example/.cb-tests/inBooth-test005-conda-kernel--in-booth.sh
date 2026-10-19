#!/bin/bash
# The conda env is a Jupyter kernel of its own, pointing at the env's real path.
echo "=== Testing conda Jupyter kernel ==="
set -euo pipefail
jupyter kernelspec list
KERNEL_JSON="$(jupyter kernelspec list --json | python -c 'import json,sys; print(json.load(sys.stdin)["kernelspecs"]["conda"]["resource_dir"])')/kernel.json"
cat "$KERNEL_JSON"
grep -q '"/opt/conda-envs/' "$KERNEL_JSON"
