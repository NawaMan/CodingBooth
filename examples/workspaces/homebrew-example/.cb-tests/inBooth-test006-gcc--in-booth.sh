#!/bin/bash
# Test: gcc

echo "=== Testing gcc ==="
gcc --version | head -1

# Compile and run hello world
TMPSRC="/tmp/test-gcc-$$.c"
TMPBIN="/tmp/test-gcc-$$"

cat > "$TMPSRC" << 'EOF'
#include <stdio.h>
int main() { printf("gcc works!\n"); return 0; }
EOF

gcc "$TMPSRC" -o "$TMPBIN"
"$TMPBIN"
rm -f "$TMPSRC" "$TMPBIN"
