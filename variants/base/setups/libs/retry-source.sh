# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ---- Retrying a network-bound command ----
#
# Every `*--install.sh` reaches out to a package registry mid-build, and registries
# have bad minutes. A Microsoft Marketplace 503 once failed five consecutive image
# builds of tests/complex/test-boothfile-code-extension while the Open VSX half of
# the same run succeeded every time; `go install` had already needed its own retry
# because proxy.golang.org resets connections. Most package managers have no retry
# of their own, so one blip upstream fails a build that has nothing wrong with it.
#
# `curl` callers do NOT need this — use its own `--retry 5 --retry-delay 3
# --retry-all-errors`, which is what the download-based setups already do. This is
# for the package managers, which have no such flag.
#
# Source with:
#   SETUP_LIBS_DIR=${SETUP_LIBS_DIR:-/opt/codingbooth/setups/libs}
#   source "${SETUP_LIBS_DIR}/retry-source.sh"

# Attempts include the first try, so 3 means "the original call plus two retries";
# CB_RETRY_ATTEMPTS=1 disables retrying entirely. The wait grows linearly:
# CB_RETRY_DELAY, then twice that, and so on. The tests set CB_RETRY_DELAY=0 so
# they exercise the loop without sleeping.
CB_RETRY_ATTEMPTS="${CB_RETRY_ATTEMPTS:-3}"
CB_RETRY_DELAY="${CB_RETRY_DELAY:-5}"

# cb_is_transient_error <log-file>
#   True for failures a later attempt can plausibly clear: an HTTP 5xx or 429 from
#   a registry, and the usual transport-level errors, in the wording each ecosystem
#   happens to use.
#
#   What is deliberately absent matters as much as what is here: "not found", "no
#   matching distribution", "unable to locate package", "no such crate" and their
#   kin read the same on every attempt. Retrying those would only make every typo'd
#   package name cost the full backoff before the build says so — and several of
#   these scripts promise a fast hard error on a bad id.
cb_is_transient_error() {
  grep -qiE \
    -e '(returned|status|http error|response)[^0-9]{0,12}(5[0-9][0-9]|429)' \
    -e '(internal server error|bad gateway|service unavailable|gateway time-?out|too many requests)' \
    -e '\b(ECONNRESET|ECONNREFUSED|ECONNABORTED|ETIMEDOUT|EAI_AGAIN|ENOTFOUND|EHOSTUNREACH|ENETUNREACH|EPIPE)\b' \
    -e 'connection (reset|refused|timed out|aborted|closed|broken)' \
    -e 'socket (hang up|timeout|error)' \
    -e 'could not resolve (host|proxy)|getaddrinfo|temporary failure (in|resolving) name' \
    -e 'read timed out|request timed out|timed out|timeout (was reached|while)' \
    -e 'network (is unreachable|error|failure|timeout|problem)' \
    -e 'tls handshake|ssl (connection|error|read|handshake)|unexpected eof' \
    -e 'spurious network error|failed to get 200 response|remote end closed|incompleteread' \
    -e 'failed to fetch|could not connect|unable to connect|hash sum mismatch|undetermined error' \
    -e 'unable to load the service index|response ended prematurely|the operation was canceled' \
    -e 'condahttperror|too many connection resets|service temporarily unavailable' \
    -- "$1"
}

# cb_retry <command...>
#   Runs the command, retrying it while the failure looks transient. Returns the
#   last attempt's exit status, so a caller's own error handling is unchanged —
#   this only decides how many times the command gets to fail first.
#
#   Output streams live through `tee` rather than being captured and replayed, so a
#   long `cargo install` still shows progress in the build log; the copy on disk is
#   only there to classify the failure. stderr is folded into stdout to be
#   classified with it, which for a Docker build log is where it was going anyway.
cb_retry() {
  local attempt=1 rc log backoff pipefail_was_off
  log="$(mktemp)"

  while :; do
    # pipefail so the pipeline reports the command's status rather than tee's.
    # Restored afterwards because callers differ on whether they set it.
    pipefail_was_off=0
    shopt -qo pipefail || pipefail_was_off=1
    set -o pipefail
    rc=0
    { "$@" 2>&1 | tee "$log"; } || rc=$?
    if [ "$pipefail_was_off" -eq 1 ]; then set +o pipefail; fi

    if [ "$rc" -eq 0 ] \
       || [ "$attempt" -ge "$CB_RETRY_ATTEMPTS" ] \
       || ! cb_is_transient_error "$log"; then
      rm -f "$log"
      return "$rc"
    fi

    backoff=$(( attempt * CB_RETRY_DELAY ))
    echo "⚠️  Transient network/registry error (attempt ${attempt}/${CB_RETRY_ATTEMPTS}); retrying in ${backoff}s ..." >&2
    sleep "$backoff"
    attempt=$(( attempt + 1 ))
  done
}
