#!/bin/bash
echo "=== Testing Anagram app ==="
cd "$(dirname "$0")"
./run-anagram.sh listen silent | grep -q "ARE anagrams"
