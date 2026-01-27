#!/bin/bash
# Test startup script for .booth/startup.sh feature
# This script runs at container start (Step 15) as the coder user

# Test 1: Create a file to prove the script ran
echo "STARTUP_SCRIPT_RAN" > /home/coder/.startup-test

# Test 2: Verify we're running as coder user
echo "$(whoami)" > /home/coder/.startup-user

# Test 3: Verify environment variables are available
echo "${HOME}" > /home/coder/.startup-home

# Test 4: Verify we can access the code directory
echo "$(pwd)" > /home/coder/.startup-pwd
