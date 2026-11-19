#!/bin/bash
# Test: bat (syntax highlighting cat)

echo "=== Testing bat ==="
echo '{"hello": "world"}' | bat -l json --paging=never
