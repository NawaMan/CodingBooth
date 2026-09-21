#!/usr/bin/env bash
# 081 — install.sh --check-only reports Docker / Linux rootless / userns-remap
#       without aborting. Guards the first-run warning so a rootless host is
#       told before they ever type `booth`.
source "$(dirname "$0")/_lib.sh"

LAST_OUTPUT=$(run_in_container <<'BASH'
set -e
cp /booth/install.sh ./install.sh
chmod +x ./install.sh

mkdir -p shim
cat > shim/docker <<'SH'
#!/usr/bin/env bash
echo "STUB-DOCKER: $*" >> /tmp/docker-calls.log
case "$1" in
  info)
    cat /tmp/docker-info-json
    ;;
  version)
    echo '29.0.0'
    ;;
  *)
    echo "unexpected docker $*" >&2
    exit 1
    ;;
esac
SH
chmod +x shim/docker
export PATH="$PWD/shim:$PATH"

echo "=== ROOTFUL ==="
echo '["name=apparmor","name=seccomp,profile=builtin","name=cgroupns"]' > /tmp/docker-info-json
bash ./install.sh --check-only

echo "=== ROOTLESS ==="
echo '["name=seccomp,profile=builtin","name=rootless"]' > /tmp/docker-info-json
bash ./install.sh --check-only

echo "=== USERNS ==="
echo '["name=apparmor","name=userns"]' > /tmp/docker-info-json
bash ./install.sh --check-only

echo "=== PERMISSION ==="
cat > shim/docker <<'SH'
#!/usr/bin/env bash
echo "permission denied while trying to connect to the Docker daemon socket" >&2
exit 1
SH
chmod +x shim/docker
bash ./install.sh --check-only
BASH
)

rootful="${LAST_OUTPUT#*=== ROOTFUL ===}"; rootful="${rootful%%=== ROOTLESS*}"
rootless="${LAST_OUTPUT#*=== ROOTLESS ===}"; rootless="${rootless%%=== USERNS*}"
userns="${LAST_OUTPUT#*=== USERNS ===}"; userns="${userns%%=== PERMISSION*}"
permission="${LAST_OUTPUT##*=== PERMISSION ===}"

assert_contains "$rootful" "docker: ok"
assert_not_contains "$rootful" "Warning: this machine looks like Linux rootless"
assert_not_contains "$rootful" "userns-remap"

assert_contains "$rootless" "Warning: this machine looks like Linux rootless Docker"
assert_contains "$rootless" "booth --rootless"

assert_contains "$userns" "userns-remap"
assert_contains "$userns" "booth --rootless"

assert_contains "$permission" "permission denied"
assert_contains "$permission" "usermod"
pass
