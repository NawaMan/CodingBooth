#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# One transient status line for a suite runner.
#
# Every suite here has stretches where it prints nothing: config holds a parallel
# test's output back until it finishes, config-tui waits on a VHS recording, and
# run-example-tests.sh sends an entire example to a log file and then blocks on
# `wait` — sometimes for a quarter of an hour. A terminal that has shown nothing
# for a quarter of an hour is indistinguishable from a hung one, and that
# ambiguity is what turns a slow run into a Ctrl+C.
#
# So: draw one line, in place, and erase it before anything else is printed. The
# scrollback ends up exactly as it was — the line never survives — but while the
# run is quiet there is always a name, a clock, and a spinner to look at. This is
# the shell counterpart of the line a silenced `docker build` draws (see
# cli/src/pkg/docker/build_progress.go); the rules are deliberately the same.
#
# It is drawn on the controlling terminal, not on stdout, so a captured log or a
# CI transcript is byte-for-byte what it was before. With no terminal — CI, a
# nohup, a pipe into a file — nothing is drawn at all and a runner should fall
# back to printing its heartbeat, which is the only signal a log gets.
#
# Usage, from a runner's own polling loop:
#
#     source "${SCRIPT_DIR}/../progress--source.sh"
#     progress_init || true                       # decides whether to draw
#     while ...; do
#         progress_draw "3 running · $(progress_elapsed "$start")"
#         sleep 0.2
#     done
#     progress_clear                              # before printing ANYTHING
#
# The one rule: `progress_clear` before any normal output, or that output lands
# on top of a half-drawn line and stays in the scrollback. Runners that already
# have an EXIT trap should call progress_clear from it, so a Ctrl+C does not
# leave the line behind.
#
# Turn it off with CB_NO_TEST_PROGRESS=1. (The booth CLI has its own knob for its
# own line, CB_NO_BUILD_PROGRESS — a runner that owns the terminal line sets that
# one for its children, so the two never draw at once.)
# -----------------------------------------------------------------------------

# Nothing is drawn for the first second, so a suite of fast tests does not
# flicker a line between one result and the next.
PROGRESS_START_DELAY="${PROGRESS_START_DELAY:-1}"

PROGRESS_ACTIVE=false

# Where the line is written. /dev/tty is the point — the line has to survive the
# runner's own stdout being redirected into a log — and a test points this at a
# file to read back what would have been drawn.
PROGRESS_TTY="${PROGRESS_TTY:-/dev/tty}"

_PROGRESS_FRAME=0
_PROGRESS_DRAWN=false
_PROGRESS_QUIET_SINCE=0
_PROGRESS_WIDTH=80

# The same frames the CLI's build line uses.
_PROGRESS_SPINNER=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")

# progress_init decides whether this run gets a line, and returns non-zero when
# it does not — so a caller can keep its own printed heartbeat for that case.
#
# A terminal has to be there twice over: /dev/tty has to be writable (that is
# where the line goes, so it survives the runner's own output being redirected),
# and one of the standard streams has to still be a terminal (so a detached run
# that merely inherited a controlling terminal does not scribble on it).
progress_init() {
    PROGRESS_ACTIVE=false

    [ -n "${CB_NO_TEST_PROGRESS:-}" ] && return 1
    [ -t 0 ] || [ -t 1 ] || [ -t 2 ] || return 1
    { : >>"$PROGRESS_TTY"; } 2>/dev/null || return 1

    PROGRESS_ACTIVE=true
    _PROGRESS_QUIET_SINCE=$SECONDS
    _progress_measure
    return 0
}

# progress_draw redraws the line in place. Cheap enough to call from a polling
# loop: it is all builtins apart from an occasional `stty`.
progress_draw() {
    [ "$PROGRESS_ACTIVE" = true ] || return 0
    [ -n "$1" ] || return 0
    (( SECONDS - _PROGRESS_QUIET_SINCE < PROGRESS_START_DELAY )) && return 0

    _PROGRESS_FRAME=$(( _PROGRESS_FRAME + 1 ))
    (( _PROGRESS_FRAME % 20 == 0 )) && _progress_measure

    local text="${_PROGRESS_SPINNER[$(( _PROGRESS_FRAME % 10 ))]} $1"

    # One column short of the width: a line that wraps leaves a stray row behind,
    # because \r\033[K only ever clears the row the cursor is on.
    local limit=$(( _PROGRESS_WIDTH - 1 ))
    if (( ${#text} > limit )); then
        text="${text:0:$(( limit - 1 ))}…"
    fi

    printf '\r\033[K%s' "$text" >>"$PROGRESS_TTY" 2>/dev/null
    _PROGRESS_DRAWN=true
    return 0
}

# progress_clear erases the line. Call it before printing anything, and from the
# EXIT trap. Idempotent, and safe to call when no line was ever drawn.
progress_clear() {
    if [ "$_PROGRESS_DRAWN" = true ]; then
        printf '\r\033[K' >>"$PROGRESS_TTY" 2>/dev/null
        _PROGRESS_DRAWN=false
    fi
    _PROGRESS_QUIET_SINCE=$SECONDS
    return 0
}

# progress_elapsed <start-epoch> [now-epoch] — "12s", "7m29s", "1h07m", the same
# shape the CLI's build line uses so the two read alike.
progress_elapsed() {
    local start="$1" now="${2:-}" secs
    [ -n "$now" ] || now=$(date +%s)
    secs=$(( now - start ))
    (( secs < 0 )) && secs=0

    if (( secs < 60 )); then
        printf '%ds' "$secs"
    elif (( secs < 3600 )); then
        printf '%dm%02ds' $(( secs / 60 )) $(( secs % 60 ))
    else
        printf '%dh%02dm' $(( secs / 3600 )) $(( (secs % 3600) / 60 ))
    fi
}

# progress_elapsed_var <varname> <start-epoch> <now-epoch> — the same string
# assigned to a variable, for a loop that redraws several times a second. The
# `$(progress_elapsed …)` form forks a subshell per call, and a four-slot line
# redrawn at 5Hz is 20 forks a second spent on a cosmetic.
progress_elapsed_var() {
    local __var="$1" secs=$(( $3 - $2 ))
    (( secs < 0 )) && secs=0

    if (( secs < 60 )); then
        printf -v "$__var" '%ds' "$secs"
    elif (( secs < 3600 )); then
        printf -v "$__var" '%dm%02ds' $(( secs / 60 )) $(( secs % 60 ))
    else
        printf -v "$__var" '%dh%02dm' $(( secs / 3600 )) $(( (secs % 3600) / 60 ))
    fi
}

# progress_tail <file> [max-chars] — the last non-blank line of a log, which is
# what the run is actually sitting on.
#
# Bounded on purpose: read the last few KB, not the file. `tail -n 1` on a
# runaway log hands a multi-gigabyte "line" to a command substitution and bash
# dies growing the buffer — a progress report must not be able to kill the run it
# is reporting on.
progress_tail() {
    local file="$1" limit="${2:-100}" line
    [ -f "$file" ] || return 0

    # \r becomes a line break rather than being deleted: a curl meter rewrites one
    # line for a whole download, and deleting the carriage returns would glue the
    # entire meter into a single "last line" whose first 100 characters are its
    # oldest state. Split on it and the newest state is the last line, which is
    # the one worth showing.
    line=$(tail -c 4096 "$file" 2>/dev/null \
        | tr '\r' '\n' \
        | sed -e $'s/\033\\[[0-9;?]*[a-zA-Z]//g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | grep -v '^[[:space:]]*$' \
        | tail -n 1)

    printf '%s' "${line:0:$limit}"
}

# Width of the terminal the line is drawn on — which is /dev/tty, not stdout, so
# `tput cols` (which reads stdout) would measure the wrong thing when the run is
# piped somewhere.
_progress_measure() {
    local cols
    cols=$(stty size <"$PROGRESS_TTY" 2>/dev/null | awk '{print $2}')
    case "$cols" in
        ''|*[!0-9]*) cols=80 ;;
    esac
    (( cols > 0 )) || cols=80
    _PROGRESS_WIDTH=$cols
}
