#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

set -euo pipefail

source ../common--source.sh

DOCKERFILE=test--dockerfile
VERSION_TAG=$(cat ../../version.txt)

export VERSION_TAG="$VERSION_TAG"
envsubst '$VERSION_TAG' > "${DOCKERFILE}" <<'EOF'
# syntax=docker/dockerfile:1.7
ARG VARIANT_TAG=base
ARG VERSION_TAG=${VERSION_TAG}
FROM nawaman/codingbooth:${VARIANT_TAG}-${VERSION_TAG}

# The default value is the latest LTS
ARG PY_VERSION=3.12
ARG VARIANT_TAG=base

SHELL ["/bin/bash","-o","pipefail","-lc"]
USER root

ENV SETUPS_DIR=/opt/codingbooth/setups
ENV VARIANT_TAG="${VARIANT_TAG}"
ENV CB_VARIANT_TAG="${VARIANT_TAG}"
ENV PY_VERSION="${PY_VERSION}"

ARG TEST_VALUE=Default-Test-Value
ENV TEST_VAR=$TEST_VALUE
EOF

# Basic test

rm -f $0.log
ACTUAL=$(run_coding_booth --dockerfile $DOCKERFILE -- 'echo TEST_VAR=$TEST_VAR' 2>/dev/null)
EXPECT="TEST_VAR=Default-Test-Value"


if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "1" "Match - the default test value"
else
  print_test_result "false" "$0" "1" "Match - the default test value"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi


# BuildArg

rm -f $0.log
ACTUAL=$(run_coding_booth --dockerfile $DOCKERFILE --build-arg TEST_VALUE=Overriden-Test-Value -- 'echo TEST_VAR=$TEST_VAR' 2> $0.log)

EXPECT="TEST_VAR=Overriden-Test-Value"

if diff -u <(echo "$EXPECT") <(echo "$ACTUAL"); then
  print_test_result "true" "$0" "2" "Match - the overriden test value"
else
  print_test_result "false" "$0" "2" "Match - the overriden test value"
  echo "-------------------------------------------------------------------------------"
  echo "Expected: "
  echo "$EXPECT"
  echo "-------------------------------------------------------------------------------"
  echo "Actual: "
  echo "$ACTUAL"
  echo "-------------------------------------------------------------------------------"
  exit 1
fi

# Validate that $0.log exists and is not empty
if [[ -s "$0.log" ]]; then
  print_test_result "true" "$0" "3" "Log file '$0.log' exists and is not empty -- contain the build log"
else
  print_test_result "false" "$0" "3" "Log file '$0.log' is missing or empty"
  exit 1
fi


# Check Silence Build

rm -f $0.log
ACTUAL=$(run_coding_booth --dockerfile $DOCKERFILE --silence-build -- 'echo TEST_VAR=$TEST_VAR' | grep -v "coding-booth" 2> $0.log)

# Validate that $0.log exists and is empty
if [[ -e "$0.log" && ! -s "$0.log" ]]; then
    print_test_result "true" "$0" "4" "Log file '$0.log' exists and is empty -- no build log as the build is silence"
else
    print_test_result "false" "$0" "4" "Log file '$0.log' is missing or not empty -- contain the build log"
    exit 1
fi
