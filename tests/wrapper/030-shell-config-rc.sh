#!/usr/bin/env bash
# 030 — shell-config writes the booth() one-liner into ~/.bashrc, skips on
#       re-run, and shell-config --uninstall removes it cleanly.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/booth ./booth
# Seed a realistic bashrc so we can see we don't clobber surrounding content.
cat > ~/.bashrc <<'RC'
# my normal bashrc stuff
export PATH=/foo:$PATH
alias ll='ls -lah'
RC

echo "=== INSTALL ==="
./booth shell-config | sed -n '1,5p'
echo "--- bashrc tail after install ---"
tail -n 3 ~/.bashrc

echo "=== RE-RUN (should skip) ==="
./booth shell-config | sed -n '1,3p'

echo "=== MARKER COUNT ==="
grep -c '# booth function v[0-9]\+' ~/.bashrc

echo "=== UNINSTALL ==="
./booth shell-config --uninstall | sed -n '1,3p'
echo "--- bashrc after uninstall ---"
cat ~/.bashrc
echo "--- end ---"
echo "MARKER COUNT AFTER: $(grep -c '# booth function v[0-9]\+' ~/.bashrc || true)"
BASH
)

# Install added exactly one marker line; original content preserved.
install_section="${LAST_OUTPUT#*=== INSTALL ===}"; install_section="${install_section%%=== RE-RUN*}"
assert_contains "$install_section" "Added booth function"
assert_contains "$install_section" "# booth function v6"
assert_contains "$install_section" "alias ll='ls -lah'"  # surrounding line preserved

# Re-run reports skipped, doesn't add duplicates.
rerun_section="${LAST_OUTPUT#*=== RE-RUN}"; rerun_section="${rerun_section%%=== MARKER COUNT*}"
assert_contains "$rerun_section" "Already configured"

# Exactly one marker after install + re-run.
marker_section="${LAST_OUTPUT#*=== MARKER COUNT ===}"; marker_section="${marker_section%%=== UNINSTALL*}"
marker_count="$(echo "$marker_section" | tr -d ' \n')"
assert_eq "$marker_count" "1"

# Uninstall removed the booth lines; original content still there.
uninstall_section="${LAST_OUTPUT##*=== UNINSTALL ===}"
assert_contains "$uninstall_section" "Removed booth function"
assert_contains "$uninstall_section" "alias ll='ls -lah'"
assert_not_contains "$uninstall_section" "# booth function v"
assert_contains "$uninstall_section" "MARKER COUNT AFTER: 0"
pass
