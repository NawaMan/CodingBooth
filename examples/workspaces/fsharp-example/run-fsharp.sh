#!/bin/bash
# Run F# example
# cd "$(dirname "$0")"
echo
echo "== customers.csv =="
cat customers.csv
echo

dotnet run --project .
