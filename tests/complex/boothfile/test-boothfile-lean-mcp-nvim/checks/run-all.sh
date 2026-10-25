#!/bin/bash
# Runs every checks/test*.sh in the booth and marks each PASSED or FAILED.
cd "$(dirname "$0")"
status=0
for t in test[0-9][0-9][0-9]-*.sh; do
    if bash "$t"; then echo ">>> PASSED: $t"; else echo ">>> FAILED: $t"; status=1; fi
done
exit $status
