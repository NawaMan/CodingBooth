#!/bin/bash
set -euo pipefail

source ../common--source.sh

# Define cleanup
cleanup() {
  rm -f in-workspace.txt in-host.txt
}
trap cleanup EXIT  # run cleanup on script exit (success or error)

cleanup
DATE=$(date)
echo $DATE > in-host.txt
../../workspace --variant base -- echo $DATE '>' in-workspace.txt

if diff -u in-workspace.txt in-host.txt; then
  print_test_result "true" "$0" "1" "Command execution matches"
else
  print_test_result "false" "$0" "1" "Command execution matches"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi