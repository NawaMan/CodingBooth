#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Test: Verify home directory structure and permissions

set -euo pipefail

source ../common--source.sh

# =============================================================================
# TEST 1: /home/coder exists and is owned by coder user
# =============================================================================
HOME_USER=$(run_coding_booth --variant base --silence-build -- 'stat -c "%U" /home/coder' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "1" "Failed to stat /home/coder"
  echo "Output: $HOME_USER"
  exit 1
}

if [[ "$HOME_USER" == "coder" ]]; then
  print_test_result "true" "$0" "1" "/home/coder owned by user coder"
else
  print_test_result "false" "$0" "1" "/home/coder has wrong user ownership: $HOME_USER"
  exit 1
fi

# =============================================================================
# TEST 2: /home/coder/code exists and is accessible
# =============================================================================
CODE_EXISTS=$(run_coding_booth --variant base --silence-build -- 'test -d /home/coder/code && echo "OK"' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "2" "Failed to check /home/coder/code"
  exit 1
}

if echo "$CODE_EXISTS" | grep -q "OK"; then
  print_test_result "true" "$0" "2" "/home/coder/code exists"
else
  print_test_result "false" "$0" "2" "/home/coder/code does not exist"
  exit 1
fi

# =============================================================================
# TEST 3: .bashrc exists, owned by coder, and has 644 permissions
# =============================================================================
BASHRC_CHECK=$(run_coding_booth --variant base --silence-build -- 'test -f /home/coder/.bashrc && stat -c "%U %a" /home/coder/.bashrc' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "3" ".bashrc does not exist or cannot be read"
  exit 1
}

if [[ "$BASHRC_CHECK" == "coder 644" ]]; then
  print_test_result "true" "$0" "3" ".bashrc exists, owned by coder, permissions 644"
else
  print_test_result "false" "$0" "3" ".bashrc has wrong ownership/permissions: $BASHRC_CHECK (expected: coder 644)"
  exit 1
fi

# =============================================================================
# TEST 4: .profile exists, owned by coder, and has 644 permissions
# =============================================================================
PROFILE_CHECK=$(run_coding_booth --variant base --silence-build -- 'test -f /home/coder/.profile && stat -c "%U %a" /home/coder/.profile' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "4" ".profile does not exist or cannot be read"
  exit 1
}

if [[ "$PROFILE_CHECK" == "coder 644" ]]; then
  print_test_result "true" "$0" "4" ".profile exists, owned by coder, permissions 644"
else
  print_test_result "false" "$0" "4" ".profile has wrong ownership/permissions: $PROFILE_CHECK (expected: coder 644)"
  exit 1
fi

# =============================================================================
# TEST 5: .zshrc exists, owned by coder, and has 644 permissions
# =============================================================================
ZSHRC_CHECK=$(run_coding_booth --variant base --silence-build -- 'test -f /home/coder/.zshrc && stat -c "%U %a" /home/coder/.zshrc' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "5" ".zshrc does not exist or cannot be read"
  exit 1
}

if [[ "$ZSHRC_CHECK" == "coder 644" ]]; then
  print_test_result "true" "$0" "5" ".zshrc exists, owned by coder, permissions 644"
else
  print_test_result "false" "$0" "5" ".zshrc has wrong ownership/permissions: $ZSHRC_CHECK (expected: coder 644)"
  exit 1
fi

# =============================================================================
# TEST 6: .gitconfig exists, owned by coder, and has 644 permissions
# =============================================================================
GITCONFIG_CHECK=$(run_coding_booth --variant base --silence-build -- 'test -f /home/coder/.gitconfig && stat -c "%U %a" /home/coder/.gitconfig' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "6" ".gitconfig does not exist or cannot be read"
  exit 1
}

if [[ "$GITCONFIG_CHECK" == "coder 644" ]]; then
  print_test_result "true" "$0" "6" ".gitconfig exists, owned by coder, permissions 644"
else
  print_test_result "false" "$0" "6" ".gitconfig has wrong ownership/permissions: $GITCONFIG_CHECK (expected: coder 644)"
  exit 1
fi

# =============================================================================
# TEST 7: coder can write to home directory
# =============================================================================
WRITE_TEST=$(run_coding_booth --variant base --silence-build -- 'touch /home/coder/test-write && rm /home/coder/test-write && echo "OK"' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "7" "coder cannot write to home directory"
  exit 1
}

if echo "$WRITE_TEST" | grep -q "OK"; then
  print_test_result "true" "$0" "7" "coder can write to home directory"
else
  print_test_result "false" "$0" "7" "coder cannot write to home directory"
  exit 1
fi

# =============================================================================
# TEST 8: Home directory has correct permissions (755)
# =============================================================================
HOME_PERMS=$(run_coding_booth --variant base --silence-build -- 'stat -c "%a" /home/coder' | grep -v "coding-booth" 2>&1) || {
  print_test_result "false" "$0" "8" "Failed to get /home/coder permissions"
  exit 1
}

if [[ "$HOME_PERMS" == "755" ]]; then
  print_test_result "true" "$0" "8" "/home/coder has correct permissions (755)"
else
  print_test_result "false" "$0" "8" "/home/coder has wrong permissions: $HOME_PERMS (expected 755)"
  exit 1
fi

echo ""
echo "All home permission tests passed!"
