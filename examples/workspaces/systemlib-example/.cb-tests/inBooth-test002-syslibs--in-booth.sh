#!/bin/bash
# The point of this example: the system libraries are really installed — headers
# AND shared objects — so code can #include them and link against them. Proven here
# with a tiny compile-and-link probe (path-independent, unlike checking fixed header
# locations — libcurl's headers live under a multiarch path on Ubuntu).
set -euo pipefail
echo "=== Testing system libraries (libcurl-dev, libsqlite3-dev, sqlite3 CLI) ==="

echo "-- compile + link + run a probe against both libraries --"
printf '%s\n' \
    '#include <curl/curl.h>' \
    '#include <sqlite3.h>' \
    '#include <cstdio>' \
    'int main() { std::printf("libcurl %s, sqlite %s\n",' \
    '            curl_version(), sqlite3_libversion()); return 0; }' \
    | clang++ -x c++ - -o /tmp/syslib-probe -lcurl -lsqlite3
/tmp/syslib-probe

echo "-- tools --"
curl-config --version
sqlite3 --version
