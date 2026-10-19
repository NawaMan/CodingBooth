#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# Unit test: the port each desktop launcher (start-xfce/kde/lxqt/wayland) binds
#
# Every desktop has its own default noVNC port — xfce 14444, kde 15555,
# lxqt 16666, wayland 17777 — so starting one by hand on another variant
# (a base booth, a notebook booth) never lands on the booth port, 10000, where
# that variant's own service already listens. The port is resolved as: the
# first argument, else NOVNC_PORT when set explicitly, else the default.
#
# The launchers are heredocs inside their setup scripts, so each is extracted
# and run on the host. Nothing desktop-shaped exists here: websockify and the
# VNC server are stubs that record their arguments, and a BASH_ENV-defined
# command_not_found_handle turns every other missing program (xfce4, labwc's
# helpers, dbus-launch, …) into a no-op. What is asserted is what websockify
# was asked to bind and which URL the launcher printed.
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
source ../common--source.sh

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SETUPS="$REPO_ROOT/variants/base/setups"

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT

# Each stub records how it was called. The launchers stop websockify as soon as
# they see the desktop gone — the X11 ones when the VNC server's pid file names no
# live process, the Wayland one when the compositor exits — so the VNC stub leaves
# a pid file for a process that lives a second (as a real server would), and the
# compositor and wayvnc stubs stay up until websockify is on record.
# (start-wayland also writes its own logs to /tmp/cb-*.log.)
mkdir -p "$WORK/bin"
for stub in websockify tigervncserver wayvnc labwc; do
    cat > "$WORK/bin/$stub" <<'STUB'
#!/bin/bash
trap '' TERM INT HUP
echo "$(basename "$0") $*" >> "$STUB_LOG"
case "$(basename "$0")" in
    # start-wayland starts websockify a few seconds after these two, then stops at
    # the first of the three to exit. Both stay up until websockify has logged
    # (at most 10s), so the run always ends on websockify's own exit.
    labwc|wayvnc)
        [[ "$(basename "$0")" == labwc ]] && : > "$XDG_RUNTIME_DIR/${WAYLAND_DISPLAY:-wayland-0}"
        for _ in $(seq 1 100); do grep -q '^websockify ' "$STUB_LOG" && break; sleep 0.1; done ;;
    tigervncserver)
        if [[ "${1:-}" == :* ]]; then
            sleep 1 &
            mkdir -p "$HOME/.vnc" && echo $! > "$HOME/.vnc/$(hostname)$1.pid"
        fi ;;
esac
exit 0
STUB
    chmod +x "$WORK/bin/$stub"
done
echo 'command_not_found_handle() { return 0; }' > "$WORK/missing-is-noop.sh"

ALL_PASSED=true
TEST_NUM=0

check() {
    local desc="$1" ok="$2" detail="${3:-}"
    TEST_NUM=$((TEST_NUM + 1))
    if [[ "$ok" == "true" ]]; then
        print_test_result "true" "$0" "$TEST_NUM" "$desc"
    else
        print_test_result "false" "$0" "$TEST_NUM" "$desc"
        [[ -n "$detail" ]] && echo "$detail" | sed 's/^/      /' | head -8
        ALL_PASSED=false
    fi
}

# Runs an extracted launcher with a clean environment plus the given VAR=value
# pairs, then any launcher arguments after "--". Sets RUN_OUT, RUN_EXIT and BOUND
# (the host:port websockify was told to listen on).
run_launcher() {
    local launcher="$1"; shift
    local envs=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do envs+=("$1"); shift; done
    [[ "${1:-}" == "--" ]] && shift
    local home
    home=$(mktemp -d "$WORK/home-XXXX")
    mkdir -p "$home/xdg"
    : > "$WORK/stub.log"
    # timeout_run wraps `env`, not the other way round: it is resolved out here,
    # where there is still a PATH, and `env -i` keeps the launcher's own
    # environment as bare as before. `${envs[@]+…}` because bash 3.2 (macOS)
    # calls an empty array unset, and this file runs under `set -u`.
    RUN_OUT=$(cd "$home" && timeout_run 20 \
        env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$home" XDG_RUNTIME_DIR="$home/xdg" \
        BASH_ENV="$WORK/missing-is-noop.sh" STUB_LOG="$WORK/stub.log" ${envs[@]+"${envs[@]}"} \
        bash "$launcher" "$@" 2>&1 </dev/null) && RUN_EXIT=0 || RUN_EXIT=$?
    BOUND=$(awk '$1=="websockify"{for(i=2;i<=NF;i++) if($i ~ /^(0\.0\.0\.0|127\.0\.0\.1):/) print $i}' "$WORK/stub.log")
}

# start-wayland expands "${COMPOSITOR_ARGS[@]}", which is empty for labwc, and
# bash before 4.4 — macOS ships 3.2 — calls an empty array unset under `set -u`:
# the launcher dies on its own expansion before it starts anything. It is right
# for the bash 5 in the image it actually runs in, so this asks the shell that
# would run it rather than changing the launcher. Behaviour, not a version test,
# because the shell the launcher gets is whichever one that PATH finds.
launcher_shell_allows_empty_arrays() {
    env -i PATH="$WORK/bin:/usr/bin:/bin" bash -uc 'a=(); printf "%s" "${a[@]}"' >/dev/null 2>&1
}

for desktop in xfce:14444 kde:15555 lxqt:16666 wayland:17777; do
    name=${desktop%%:*}
    default=${desktop##*:}
    # tr, not ${name^^}: that expansion is bash 4, and macOS ships bash 3.2.
    upper=$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')

    if [[ "$name" == wayland ]] && ! launcher_shell_allows_empty_arrays; then
        echo "SKIP: start-wayland needs a shell that allows an empty \"\${arr[@]}\" under set -u" \
             "(bash 4.4+); this host runs the launchers with bash" \
             "$(env -i PATH="$WORK/bin:/usr/bin:/bin" bash -c 'echo "${BASH_VERSION%%(*}"')"
        continue
    fi
    launcher="$WORK/start-$name"
    # The starter heredoc: `cat > <starter> <<'EOF'` ... `EOF`.
    awk -v name="$name" '
        $0 ~ /^cat > / && ($0 ~ /STARTER_FILE/ || $0 ~ ("/usr/local/bin/start-" name " ")) && $0 ~ /<<.EOF.$/ { f=1; next }
        f && /^EOF$/ { exit }
        f' "$SETUPS/$name--setup.sh" > "$launcher"
    if ! grep -q "start-$name" "$launcher"; then
        check "start-$name: launcher extracted from $name--setup.sh" "false"
        continue
    fi

    run_launcher "$launcher"
    check "start-$name: defaults to $default" \
        "$([[ "$BOUND" == "0.0.0.0:$default" ]] && echo true || echo false)" "bound: '$BOUND'
$RUN_OUT"
    check "start-$name: prints its own port and how to expose it" \
        "$([[ "$RUN_OUT" == *"localhost:$default/"* && "$RUN_OUT" == *"booth--expose $default"* ]] && echo true || echo false)" "$RUN_OUT"

    run_launcher "$launcher" -- 20001
    check "start-$name 20001: binds the given port" \
        "$([[ "$BOUND" == "0.0.0.0:20001" ]] && echo true || echo false)" "bound: '$BOUND'"

    run_launcher "$launcher" NOVNC_PORT=20002
    check "start-$name: honours an explicit NOVNC_PORT" \
        "$([[ "$BOUND" == "0.0.0.0:20002" ]] && echo true || echo false)" "bound: '$BOUND'"

    run_launcher "$launcher" NOVNC_PORT=20002 -- 20003
    check "start-$name 20003: the argument wins over NOVNC_PORT" \
        "$([[ "$BOUND" == "0.0.0.0:20003" ]] && echo true || echo false)" "bound: '$BOUND'"

    # Behind the desktop variants' wrapper: the wrapper exports INNER_PORT and is
    # itself reached on the booth port, so that is the URL to print.
    wrapper_host=0.0.0.0
    if [[ "$name" == lxqt || "$name" == wayland ]]; then wrapper_host=127.0.0.1; fi
    run_launcher "$launcher" INNER_PORT="$default" BOOTH_HOST_PORT=10000 -- "$default"
    check "start-$name behind the wrapper: prints the booth port, no expose hint" \
        "$([[ "$BOUND" == "$wrapper_host:$default" && "$RUN_OUT" == *"localhost:10000/"* && "$RUN_OUT" != *"booth--expose"* ]] && echo true || echo false)" "$RUN_OUT"

    run_launcher "$launcher" -- notaport
    check "start-$name notaport: refused with a usage line" \
        "$([[ "$RUN_EXIT" != 0 && "$RUN_OUT" == *"Usage: start-$name [port]"* && -z "$BOUND" ]] && echo true || echo false)" "$RUN_OUT"

    # The desktop variant's wrapper passes the same port as an argument.
    check "start-$name-wrapped runs start-$name on $default" \
        "$(grep -qE "^${upper}_INNER_PORT=$default$" "$SETUPS/booth-message-desktop-wrapped--setup.sh" \
            && grep -qF "export INNER_CMD=\"start-$name \$${upper}_INNER_PORT\"" "$SETUPS/booth-message-desktop-wrapped--setup.sh" \
            && echo true || echo false)"
done

if [[ "$ALL_PASSED" != "true" ]]; then
    exit 1
fi
