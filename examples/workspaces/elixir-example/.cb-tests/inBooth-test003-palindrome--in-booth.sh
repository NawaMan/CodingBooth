#!/bin/bash
echo "=== Testing Palindrome app ==="
cd "$(dirname "$0")/.."
./run-palindrome.sh racecar | grep -q "IS a palindrome"
