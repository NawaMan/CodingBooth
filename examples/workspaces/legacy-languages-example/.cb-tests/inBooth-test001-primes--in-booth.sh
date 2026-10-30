#!/bin/bash
# Each language must compile (where it is compiled) and print the same primes.
echo "=== Testing primes in every language ==="
cd "$(dirname "$0")/.."
OUT="$(just run 2>&1)"
echo "$OUT"
EXPECTED="2 3 5 7 11 13 17 19 23 29"
status=0
for lang in "Fortran" "COBOL" "ALGOL 68" "Prolog" "Smalltalk" "Pascal"; do
  if echo "$OUT" | grep -qE "^ *${lang}: +${EXPECTED// / +} *$"; then
    echo "ok   - $lang"
  else
    echo "FAIL - $lang"; status=1
  fi
done
exit $status
