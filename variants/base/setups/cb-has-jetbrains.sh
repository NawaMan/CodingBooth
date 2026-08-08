#!/bin/bash
# Returns 0 if a JetBrains IDE is available, 1 otherwise.

# Every JetBrains IDE unpacks with a product-info.json at its install root, and
# jetbrains--setup.sh drops each one under /opt/<ide>-<version>/ with a stable
# /opt/<ide> symlink beside it. Looking for the marker file rather than a list of
# IDE names keeps this working for IDEs the catalog has not learned about yet.
# JETBRAINS_OPT_ROOT is overridable so the unit test can point this at a fake tree;
# nothing in a real image sets it.
for info in "${JETBRAINS_OPT_ROOT:-/opt}"/*/product-info.json; do
    [ -f "$info" ] && exit 0
done

exit 1
