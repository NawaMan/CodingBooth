#!/bin/bash
# Build (where needed) and run the primes program in one language, or all of them.
# Usage: ./run-primes.sh [fortran|cobol|algol68|prolog|smalltalk|pascal|all]
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

run() {
  case "$1" in
    fortran)   gfortran src/primes.f90 -J build -o build/primes-fortran && build/primes-fortran ;;
    cobol)     gcobol src/primes.cob -o build/primes-cobol && build/primes-cobol ;;
    algol68)   ga68 src/primes.a68 -o build/primes-algol68 && build/primes-algol68 ;;
    prolog)    swipl -g main -t halt src/primes.pl ;;
    smalltalk) pharo st --quit "$PWD/src/primes.st" ;;
    pascal)    fpc -v0 -FEbuild -FUbuild src/primes.pas >/dev/null && build/primes ;;
    *) echo "Unknown language: $1" >&2; exit 2 ;;
  esac
}

if [[ "${1:-all}" == "all" ]]; then
  for lang in fortran cobol algol68 prolog smalltalk pascal; do
    run "$lang"
  done
else
  run "$1"
fi
