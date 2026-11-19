#!/bin/bash
echo "=== Testing Anagram app ==="
cd "$(dirname "$0")/.."
just run listen silent | grep -q "ARE anagrams"
