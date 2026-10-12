#!/bin/bash
# Run by test--boothfile-exec-env.sh through `booth exec ... -- bash inBooth-exec-env.sh`: plain
# bash, NOT a login shell, so /etc/profile.d never runs. Everything below must work from the image
# environment alone. Prints one labeled line per check; the host side asserts on them.

# Commands only the profile used to put on PATH.
echo "julia: $(julia --version 2>&1 | head -1)"
echo "conda: $(conda --version 2>&1 | head -1)"
echo "gopls: $(gopls version >/dev/null 2>&1 && echo ok || echo missing)"

# Variables only the profile used to set.
echo "gopath: ${GOPATH:-unset}"
echo "java-home: $("${JAVA_HOME:-/nonexistent}/bin/java" -version 2>&1 | head -1)"
echo "julia-depot: ${JULIA_DEPOT_PATH:-unset}"
echo "conda-envs: ${CONDA_ENVS_DIRS:-unset}"
