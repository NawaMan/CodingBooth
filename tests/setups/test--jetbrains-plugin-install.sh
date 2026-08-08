#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: jetbrains-plugin--install.sh
#
# Runs the real jetbrains-plugin--install.sh against a fake /opt tree holding a
# fake JetBrains IDE, with `curl` stubbed so no marketplace request leaves the
# machine. Asserts both what it emits and what it does when an install goes wrong.
#
# Locked in here:
#   - comma-separated ids are split
#   - an unpinned id goes through the IDE's own `installPlugins`
#   - a numeric id is resolved to its xmlId before being handed on — the IDE
#     answers "unknown plugins" for a number, so this resolution is load-bearing
#   - a trailing @version is downloaded from the marketplace instead, and unpacked
#   - an id no IDE accepts is a hard failure
#   - no ids at all is a no-op, because the template's param defaults to empty
#   - no JetBrains IDE at all is a SKIP, not a failure: the IDEs are desktop-only,
#     so a base-variant build reaches this through no fault of the ids (this is the
#     one place it deliberately differs from code-extension--install.sh)
#   - an idea.plugins.path already in idea.properties is honoured
#   - an IDE reached through both /opt/<ide> and /opt/<ide>-<version> is visited once
#
# The script requires root; we satisfy that with fakeroot, and point the fake /opt
# and the plugin dir at a temp tree so nothing real is touched.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS_DIR="$REPO_ROOT/variants/base/setups"
PLUGIN_SCRIPT="$SETUPS_DIR/jetbrains-plugin--install.sh"

for tool in jq unzip; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "SKIP: needs $tool, which jetbrains-plugin--install.sh relies on"
        exit 0
    fi
done

# The script guards on EUID==0; run under fakeroot when not already root.
ROOT_RUN=()
if [ "$EUID" -ne 0 ]; then
    if command -v fakeroot >/dev/null 2>&1; then
        ROOT_RUN=(fakeroot)
    else
        echo "SKIP: needs root or fakeroot to satisfy jetbrains-plugin--install.sh's root check"
        exit 0
    fi
fi

STUB=$(mktemp -d)
trap "rm -rf $STUB" EXIT
mkdir -p "$STUB/bin" "$STUB/opt" "$STUB/empty-opt" "$STUB/plugins" "$STUB/home"

# ---- A fake JetBrains IDE ----------------------------------------------------
# Shaped like the real thing: a versioned install dir carrying product-info.json,
# bin/idea.properties and an <ide>-starter shim, with a stable /opt/<ide> symlink
# beside it. Both paths match the discovery glob, which is what test 10 checks.
IDE_DIR="$STUB/opt/idea-IC-9.9.9"
mkdir -p "$IDE_DIR/bin"
cat > "$IDE_DIR/product-info.json" << 'EOF'
{ "productCode": "IC", "buildNumber": "999.1.1", "dataDirectoryName": "IdeaICTest" }
EOF
cat > "$IDE_DIR/bin/idea.properties" << 'EOF'
idea.fatal.error.notification=disabled
EOF
ln -s "$IDE_DIR" "$STUB/opt/idea"

# Stub starter, standing in for the IDE's headless `installPlugins`. It writes into
# whatever idea.plugins.path names, which is how the test sees where a plugin went.
#   cb.unknown.*  → "unknown plugins", exit 1 (no such id on the marketplace)
cat > "$IDE_DIR/idea-starter" << 'EOF'
#!/bin/bash
[[ "${1:-}" == "installPlugins" ]] || { echo "stub: unexpected command ${1:-}" >&2; exit 2; }
shift
DIR="$(grep -E '^idea\.plugins\.path=' "$(dirname "$0")/bin/idea.properties" | tail -1 | cut -d= -f2-)"
for id in "$@"; do
  case "$id" in
    cb.unknown.*) echo "unknown plugins: [$id]"; exit 1 ;;
  esac
  mkdir -p "$DIR/${id// /_}"
  echo "installed plugin: PluginNode{id=$id}"
done
EOF
chmod +x "$IDE_DIR/idea-starter"

# ---- A minimal, valid plugin archive -----------------------------------------
# One top-level dir holding lib/ and META-INF/plugin.xml, which is the shape
# install_pinned checks for before it copies anything into place.
cat > "$STUB/plugin.zip.b64" << 'ZIPB64'
UEsDBBQAAAAIAEeIB13Hgv69EgAAABAAAAAdAAAAc3R1YnBsdWdpbi9saWIvc3R1YnBsdWdpbi5q
YXLLyy/RLUpNzMmp1E3UzUosAgBQSwMEFAAAAAgAR4gHXTL4JAc3AAAASgAAAB4AAABzdHVicGx1
Z2luL01FVEEtSU5GL3BsdWdpbi54bWyzyUxJTdQtyClNz8yzs8lMsUtO0isuKU3SgwjZ6Gem2NmU
pRYVZ+bn2RnqGekZ2+jDuCBJhGYAUEsBAhQDFAAAAAgAR4gHXceC/r0SAAAAEAAAAB0AAAAAAAAA
AAAAAIABAAAAAHN0dWJwbHVnaW4vbGliL3N0dWJwbHVnaW4uamFyUEsBAhQDFAAAAAgAR4gHXTL4
JAc3AAAASgAAAB4AAAAAAAAAAAAAAIABTQAAAHN0dWJwbHVnaW4vTUVUQS1JTkYvcGx1Z2luLnht
bFBLBQYAAAAAAgACAJcAAADAAAAAAAA=
ZIPB64

# ---- Stub curl ---------------------------------------------------------------
# Two endpoints matter: the id lookup, and the pinned download. Everything else
# 404s, so an unexpected request shows up as a failure rather than reaching out.
#   /api/plugins/9999      → xmlId cb.stub.plugin
#   /api/plugins/<other>   → 404 (curl -f exits 22)
#   action=download&...    → the plugin zip above, unless version=0.0.0 (→ 404),
#                            which stands in for "no build of this pin fits this IDE"
cat > "$STUB/bin/curl" << EOF
#!/bin/bash
OUT=""
URL=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -o) OUT="\$2"; shift 2 ;;
    -*) shift ;;
    *)  URL="\$1"; shift ;;
  esac
done
case "\$URL" in
  */api/plugins/9999)      echo '{"id":9999,"xmlId":"cb.stub.plugin","name":"CB Stub"}' ;;
  */api/plugins/*)         exit 22 ;;
  *action=download*version=0.0.0*) exit 22 ;;
  *action=download*)       base64 -d < "$STUB/plugin.zip.b64" > "\$OUT" ;;
  *)                       exit 22 ;;
esac
EOF
chmod +x "$STUB/bin/curl"

reset_plugins() {
    rm -rf "$STUB/plugins"
    mkdir -p "$STUB/plugins"
    # Drop any idea.plugins.path a previous run appended, so each case starts clean.
    grep -v '^idea\.plugins\.path=' "$IDE_DIR/bin/idea.properties" > "$IDE_DIR/bin/idea.properties.new"
    mv "$IDE_DIR/bin/idea.properties.new" "$IDE_DIR/bin/idea.properties"
}

# PATH is stubbed so the script finds the fake curl, never the real one.
# JETBRAINS_OPT_ROOT / JETBRAINS_PLUGINS_ROOT point discovery and installs at the
# temp tree; nothing in a real image sets either.
run_plugin_install() {
    reset_plugins
    PATH="$STUB/bin:$PATH" \
    HOME="$STUB/home" \
    SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
    JETBRAINS_OPT_ROOT="$STUB/opt" \
    JETBRAINS_PLUGINS_ROOT="$STUB/plugins" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$PLUGIN_SCRIPT" "$@" < /dev/null 2>&1
}

# Same, but pointed at an /opt with no JetBrains IDE in it.
run_plugin_install_no_ide() {
    PATH="$STUB/bin:$PATH" \
    HOME="$STUB/home" \
    SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
    JETBRAINS_OPT_ROOT="$STUB/empty-opt" \
    JETBRAINS_PLUGINS_ROOT="$STUB/plugins" \
        ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$PLUGIN_SCRIPT" "$@" < /dev/null 2>&1
}

ALL_PASSED=true
TEST_NUM=0

assert_ok() {
    local desc="$1" expected="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    local out rc
    out=$(run_plugin_install "$@") && rc=0 || rc=$?
    if [[ $rc -eq 0 ]] && echo "$out" | grep -qF -- "$expected"; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        echo "  args:     $*"
        echo "  expected: exit 0 and output containing: $expected"
        echo "  actual:   exit $rc"
        echo "$out" | sed 's/^/            /'
        ALL_PASSED=false
    fi
}

assert_fails() {
    local desc="$1" expected="$2"; shift 2
    TEST_NUM=$((TEST_NUM + 1))
    local out rc
    out=$(run_plugin_install "$@") && rc=0 || rc=$?
    if [[ $rc -ne 0 ]] && echo "$out" | grep -qF -- "$expected"; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        echo "  args:     $*"
        echo "  expected: non-zero exit and output containing: $expected"
        echo "  actual:   exit $rc"
        echo "$out" | sed 's/^/            /'
        ALL_PASSED=false
    fi
}

# 1. An unpinned id goes through the IDE's own installer.
assert_ok "unpinned id goes through installPlugins" \
    "installed plugin: PluginNode{id=cb.stub.plugin}" cb.stub.plugin

# 2. …and is reported against the IDE it landed in.
assert_ok "unpinned id reported per IDE" "✔ cb.stub.plugin → idea" cb.stub.plugin

# 3-4. A comma list is split into separate ids (the form the config template emits).
assert_ok "comma list: first id installed" \
    "✔ cb.stub.plugin → idea" "cb.stub.plugin,cb.other.plugin"
assert_ok "comma list: second id installed" \
    "✔ cb.other.plugin → idea" "cb.stub.plugin,cb.other.plugin"

# 5-6. A numeric id is resolved to its xmlId first. `installPlugins 9999` answers
#      "unknown plugins", so handing the number straight through would fail — this
#      is what makes the numeric form usable at all, and the numeric form is the
#      only way to name a plugin whose xmlId has a space ("Lombook Plugin").
assert_ok "numeric id is resolved to its xmlId" "↪ 9999 → cb.stub.plugin" 9999
assert_ok "resolved numeric id is what gets installed" \
    "installed plugin: PluginNode{id=cb.stub.plugin}" 9999

# 7. A pinned id is downloaded and unpacked instead — `installPlugins` has no
#    version argument, so a pin cannot go through it.
assert_ok "pinned id is downloaded and unpacked" \
    "✔ cb.stub.plugin@1.2.3 → idea" cb.stub.plugin@1.2.3

# 8. The unpacked plugin really lands in the plugin dir, not just in the log.
TEST_NUM=$((TEST_NUM + 1))
run_plugin_install cb.stub.plugin@1.2.3 > /dev/null 2>&1 || true
if [[ -f "$STUB/plugins/IdeaICTest/stubplugin/META-INF/plugin.xml" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "pinned plugin lands under the plugins dir"
else
    print_test_result "false" "$0" "$TEST_NUM" "pinned plugin should land under the plugins dir"
    find "$STUB/plugins" | sed 's/^/          /'
    ALL_PASSED=false
fi

# 9. A pin with no build for this IDE fails rather than installing something else.
assert_fails "pin with no compatible build fails" \
    "not available for idea" cb.stub.plugin@0.0.0

# 10-11. An id no IDE accepts is a hard failure, with an actionable hint.
assert_fails "unknown id exits non-zero" "installed into no IDE" cb.unknown.plugin
assert_fails "unknown id points at the marketplace" \
    "plugins.jetbrains.com" cb.unknown.plugin

# 12. An unknown numeric id fails at resolution, before any IDE is touched.
assert_fails "unknown numeric id fails at resolution" \
    "no plugin with numeric id 12345" 12345

# 13. One bad id in a list fails the whole run — a partially-applied image is
#     worse than a build that stops.
assert_fails "one bad id in a list fails the run" \
    "installed into no IDE" "cb.stub.plugin,cb.unknown.plugin"

# 13b-13c. An id containing a space, passed as ONE argument, must not be word-split.
#     This is the path lombok-idea--setup.sh uses: Lombok's xmlId really is the two-word
#     "Lombook Plugin", and splitting it yields two invalid ids and a failed build. Only
#     a direct caller can deliver it whole — through a Boothfile the param expands
#     unquoted and the shell splits it first, which is why the numeric id exists.
assert_ok "an id with a space survives as one id" \
    "✔ Lombook Plugin → idea" "Lombook Plugin"

TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_plugin_install "Lombook Plugin")
INSTALL_LINES=$(echo "$OUT" | grep -c "installed plugin:" || true)
if [[ "$INSTALL_LINES" == "1" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "a spaced id is one install, not two"
else
    print_test_result "false" "$0" "$TEST_NUM" "a spaced id should be one install, not two"
    echo "  install lines: $INSTALL_LINES"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

# 14. No arguments → no-op, zero exit. JETBRAINS_PLUGIN_PKGS defaults to "" in
#     templates/ides/jetbrains-plugin-pkg, so `install jetbrains-plugin ${...}`
#     reaches here with no ids whenever that template is selected without naming
#     any, and a hard failure would break the image build.
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_plugin_install) && RC=0 || RC=$?
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -qF "nothing to install"; then
    print_test_result "true" "$0" "$TEST_NUM" "no arguments is a no-op"
else
    print_test_result "false" "$0" "$TEST_NUM" "no arguments is a no-op"
    echo "  actual: exit $RC"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

# 15. No JetBrains IDE → skip, not failure. jetbrains--setup.sh calls skip_setup on a
#     non-desktop variant, so `setup idea` + `install jetbrains-plugin X` on the base
#     variant legitimately leaves no IDE to install into. skip_setup exits 0 when
#     neither stdin nor stdout is a TTY, which is the Dockerfile build case and the
#     case here (stdin is /dev/null, stdout a pipe).
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_plugin_install_no_ide cb.stub.plugin) && RC=0 || RC=$?
if [[ $RC -eq 0 ]] && echo "$OUT" | grep -qF "no JetBrains IDE installed"; then
    print_test_result "true" "$0" "$TEST_NUM" "no JetBrains IDE is a skip, not a failure"
else
    print_test_result "false" "$0" "$TEST_NUM" "no JetBrains IDE should be a skip, not a failure"
    echo "  actual: exit $RC"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

# 16. An idea.plugins.path already in idea.properties wins over the default: an
#     image may have been built before this lib existed, or been pointed elsewhere
#     on purpose.
TEST_NUM=$((TEST_NUM + 1))
reset_plugins
mkdir -p "$STUB/plugins/preset"
echo "idea.plugins.path=$STUB/plugins/preset" >> "$IDE_DIR/bin/idea.properties"
OUT=$(PATH="$STUB/bin:$PATH" HOME="$STUB/home" SETUP_LIBS_DIR="$SETUPS_DIR/libs" \
      JETBRAINS_OPT_ROOT="$STUB/opt" JETBRAINS_PLUGINS_ROOT="$STUB/plugins" \
      ${ROOT_RUN[@]+"${ROOT_RUN[@]}"} bash "$PLUGIN_SCRIPT" cb.stub.plugin < /dev/null 2>&1) \
      && RC=0 || RC=$?
if [[ $RC -eq 0 && -d "$STUB/plugins/preset/cb.stub.plugin" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "an existing idea.plugins.path is honoured"
else
    print_test_result "false" "$0" "$TEST_NUM" "an existing idea.plugins.path should be honoured"
    echo "  actual: exit $RC"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

# 17. /opt/idea and /opt/idea-IC-9.9.9 are the same install; it must be visited once,
#     or every plugin would be installed twice and every failure counted twice.
TEST_NUM=$((TEST_NUM + 1))
OUT=$(run_plugin_install cb.stub.plugin)
FOUND_COUNT=$(echo "$OUT" | grep -c "✔ cb.stub.plugin → idea" || true)
if [[ "$FOUND_COUNT" == "1" ]]; then
    print_test_result "true" "$0" "$TEST_NUM" "an IDE reached by two paths is visited once"
else
    print_test_result "false" "$0" "$TEST_NUM" "an IDE reached by two paths should be visited once"
    echo "  install lines: $FOUND_COUNT"
    echo "$OUT" | sed 's/^/          /'
    ALL_PASSED=false
fi

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
