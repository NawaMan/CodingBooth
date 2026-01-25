#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Run all complex tests
#
# Complex tests are tests that require custom Dockerfiles, setup scripts,
# and more elaborate configurations.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================================"
echo "Running Complex Tests"
echo "============================================================"

FAILED=0

# Test .booth/home (no-clobber behavior)
echo ""
echo "--- Running: test-booth-home ---"
if (cd test-booth-home && ./test--booth-home.sh); then
  echo "PASSED: test-booth-home"
else
  echo "FAILED: test-booth-home"
  FAILED=$((FAILED + 1))
fi

# Test cb-home-seed (no-clobber behavior)
echo ""
echo "--- Running: test-cb-home-seed ---"
if (cd test-cb-home-seed && ./test--cb-home-seed.sh); then
  echo "PASSED: test-cb-home-seed"
else
  echo "FAILED: test-cb-home-seed"
  FAILED=$((FAILED + 1))
fi

# Test cb-home (override behavior)
echo ""
echo "--- Running: test-cb-home ---"
if (cd test-cb-home && ./test--cb-home.sh); then
  echo "PASSED: test-cb-home"
else
  echo "FAILED: test-cb-home"
  FAILED=$((FAILED + 1))
fi

# Test .booth/startup.sh
echo ""
echo "--- Running: test-booth-startup ---"
if (cd test-booth-startup && ./test--booth-startup.sh); then
  echo "PASSED: test-booth-startup"
else
  echo "FAILED: test-booth-startup"
  FAILED=$((FAILED + 1))
fi

# Test workspace environment (.env file, mounts)
echo ""
echo "--- Running: test-workspace-env ---"
if (cd test-workspace-env && ./test--workspace-env.sh); then
  echo "PASSED: test-workspace-env"
else
  echo "FAILED: test-workspace-env"
  FAILED=$((FAILED + 1))
fi

# Test cmds in config.toml (default command)
echo ""
echo "--- Running: test-config-cmds ---"
if (cd test-config-cmds && ./test--config-cmds.sh); then
  echo "PASSED: test-config-cmds"
else
  echo "FAILED: test-config-cmds"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "============================================================"
if [ $FAILED -eq 0 ]; then
  echo "All complex tests passed!"
  exit 0
else
  echo "FAILED: $FAILED test(s) failed"
  exit 1
fi
