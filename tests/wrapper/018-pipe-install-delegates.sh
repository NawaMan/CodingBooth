#!/usr/bin/env bash
# 018 — piping the wrapper (`curl … /booth | bash`) must hand off to the
#       installer instead of running as a normal invocation.
#
#       The wrapper detects this by inspecting $0, which is the shell's name
#       rather than a script path when piped, and delegates to
#       codingbooth.io/install.sh. That branch is the first thing in the file
#       and guards against a piped wrapper falling through to path resolution
#       on a $0 that is not a path at all.
#
#       curl is shimmed on PATH so this stays hermetic and offline: the shim
#       records the URL the wrapper asked for and emits a marker script in place
#       of the real installer, which the wrapper's own `| bash` then runs. That
#       proves the delegation happened AND that its output is executed, without
#       a second network install (080 already covers the real installer).
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth

mkdir -p shim
# The shim's stdout is consumed by the wrapper's own `| bash`, so the call is
# logged to a file rather than echoed — anything on stdout here is script the
# wrapper executes, not text anyone reads.
cat > shim/curl <<'SHIM'
#!/usr/bin/env bash
echo "SHIM-CURL: $*" >> /tmp/curl-calls.log
# Stand in for install.sh; the wrapper pipes this into bash.
echo 'echo "INSTALLER-RAN"'
SHIM
chmod +x shim/curl
export PATH="$PWD/shim:$PATH"

echo "=== PIPED ==="
bash < ./booth

echo "=== CURL-CALLS ==="
cat /tmp/curl-calls.log

echo "=== NOT-PIPED-CONTROL ==="
./booth help
BASH
)

piped="${LAST_OUTPUT#*=== PIPED ===}"; piped="${piped%%=== CURL-CALLS*}"
curl_calls="${LAST_OUTPUT#*=== CURL-CALLS ===}"; curl_calls="${curl_calls%%=== NOT-PIPED-CONTROL*}"
control="${LAST_OUTPUT##*=== NOT-PIPED-CONTROL ===}"

# The branch announced itself.
assert_contains "$piped" "Installing CodingBooth wrapper..."
# And piped what it fetched into a shell that actually ran it.
assert_contains "$piped" "INSTALLER-RAN"
# It fetched the published installer, not something else.
assert_contains "$curl_calls" "https://codingbooth.io/install.sh"
# It delegated instead of proceeding — no wrapper help, no install attempt.
assert_not_contains "$piped" "Wrapper commands:"

# Control: invoked as a file, the same wrapper takes the normal path.
assert_contains "$control" "Wrapper commands:"
assert_not_contains "$control" "Installing CodingBooth wrapper..."
pass
