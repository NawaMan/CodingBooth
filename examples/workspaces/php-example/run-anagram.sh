#!/bin/bash
# Run Anagram checker
cd "$(dirname "$0")"
php src/anagram.php "$@"
