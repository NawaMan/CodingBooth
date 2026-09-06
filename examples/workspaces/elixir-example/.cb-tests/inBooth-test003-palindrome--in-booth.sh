#!/bin/bash
echo "=== Testing Palindrome app ==="
cd "$(dirname "$0")/.."
just run racecar | grep -q "IS a palindrome"
