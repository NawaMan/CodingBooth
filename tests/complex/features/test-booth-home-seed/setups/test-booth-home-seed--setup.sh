#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# test-booth-home-seed--setup.sh
#
# Test setup script that:
# 1. Creates a file in /home/coder during build (BEFORE .booth/home-seed is copied)
# 2. Creates a startup script that logs the file content for verification
# -----------------------------------------------------------------------------

set -Eeuo pipefail
trap 'echo "Error on line $LINENO" >&2; exit 1' ERR

# Ensure running as root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

echo "Setting up test for .booth/home-seed..."

# Create the test file in /home/coder DURING BUILD
# This file should NOT be overwritten by .booth/home-seed (no-clobber behavior)
mkdir -p /home/coder
echo "ORIGINAL_FROM_BUILD" > /home/coder/.testfile
chown -R coder:coder /home/coder/.testfile 2>/dev/null || true

# NOTE: We do NOT create .testfile-normal here
# This allows testing that .booth/home-seed CAN copy files when they don't exist

# Create a startup script that logs the file content
cat > /usr/share/startup.d/70-cb-test-booth-home-seed--startup.sh << 'STARTUP'
#!/usr/bin/env bash
# Startup script to log the test file content for verification
echo "=== .booth/home-seed test startup ===" >> /tmp/startups.log
echo "Content of /home/coder/.testfile:" >> /tmp/startups.log
cat /home/coder/.testfile >> /tmp/startups.log 2>&1 || echo "FILE NOT FOUND" >> /tmp/startups.log
echo "=================================" >> /tmp/startups.log
STARTUP

chmod 755 /usr/share/startup.d/70-cb-test-booth-home-seed--startup.sh

echo "Test setup for .booth/home-seed complete."
