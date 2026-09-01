#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

#
# build-all.sh - Build CLI + Docker images with a live status display
#
# Builds the CLI first, then the base variant, then all remaining variants
# in parallel. Shows a live-updating status graph.
#
set -uo pipefail

# Change to project root
cd "$(dirname "$0")/.." || exit 1

if [[ ! -f "version.txt" ]] || [[ ! -d "variants" ]]; then
    echo "Error: This script must be run from the project root directory."
    echo "   Usage: ./build/build-all.sh [options] [variant ...]"
    exit 1
fi

# ── Settings ──────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_DIR="${SCRIPT_DIR}/logs"

ALL_DEPENDENT_VARIANTS=(notebook codeserver desktop-xfce desktop-kde desktop-lxqt desktop-wayland)

# ── State ─────────────────────────────────────────────────────────────

DOCKER_FLAGS=()        # flags forwarded to docker-build.sh
VARIANTS_TO_BUILD=()   # dependent variants (excludes base)
STOP_REQUESTED=false
PUSH_REQUESTED=false   # mirror of --push in DOCKER_FLAGS
NO_CACHE_REQUESTED=false  # mirror of --no-cache; drives the pre-build cache prune
PRUNE_REQUESTED=true      # --no-prune opts out of that prune

# Status files are used instead of associative arrays for bash 3.2 compatibility
# Status for each step stored in ${LOG_DIR}/${step}.status
CLI_STATUS="pending"
BASE_STATUS="pending"

# Per-variant PIDs stored in separate variables (bash 3.2 doesn't support associative arrays)
PIDS_NOTEBOOK=""
PIDS_CODESERVER=""
PIDS_DESKTOP_XFCE=""
PIDS_DESKTOP_KDE=""
PIDS_DESKTOP_LXQT=""

# ── ANSI Colors ───────────────────────────────────────────────────────

C_RESET='\033[0m'
C_WHITE='\033[0;37m'
C_GREEN='\033[1;32m'
C_BLUE='\033[1;34m'
C_RED='\033[1;31m'
C_GRAY='\033[0;90m'
C_BOLD='\033[1m'

# ── Parse args ────────────────────────────────────────────────────────

ParseArgs() {
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --push)     DOCKER_FLAGS+=("--push"); PUSH_REQUESTED=true; shift ;;
            --no-cache) DOCKER_FLAGS+=("--no-cache"); NO_CACHE_REQUESTED=true; shift ;;
            --no-prune) PRUNE_REQUESTED=false;         shift ;;
            -h|--help)  Usage; exit 0 ;;
            *)          positional+=("$1");            shift ;;
        esac
    done

    if [[ ${#positional[@]} -gt 0 ]]; then
        # User specified variants — filter out "base" (always built) and keep the rest
        for v in "${positional[@]}"; do
            if [[ "$v" == "base" ]]; then
                continue  # base is always built first
            fi
            VARIANTS_TO_BUILD+=("$v")
        done
        # If user only said "base", nothing else to build
    else
        VARIANTS_TO_BUILD=("${ALL_DEPENDENT_VARIANTS[@]}")
    fi
}

Usage() {
    cat <<'EOF'
Usage: ./build/build-all.sh [--push] [--no-cache] [variant ...]

Builds the CLI, then the base Docker image, then the remaining variants in
parallel.  A live status graph is displayed during the build.

Options:
  --push          Forward to docker-build.sh (push + sign)
  --no-cache      Forward to docker-build.sh (no layer cache). Also discards the
                  build cache first — see --no-prune.
  --no-prune      Keep the existing build cache even with --no-cache.
  -h, --help      Show this help

Variants (if none provided, all are built):
  base, notebook, codeserver, desktop-xfce, desktop-kde, desktop-lxqt

Logs are written to build/logs/.

Press Ctrl+C during a build to stop gracefully.
EOF
}

# ── Status graph ──────────────────────────────────────────────────────

# last_log_line: read last non-empty line from a log file, trimmed to max length.
last_log_line() {
    local log_file="$1" max_len="${2:-60}"
    [[ -f "$log_file" ]] || return
    local line
    line=$(tail -1 "$log_file" 2>/dev/null | tr -d '\r')
    [[ -z "$line" ]] && return
    if [[ ${#line} -gt $max_len ]]; then
        line="${line:0:$max_len}..."
    fi
    echo -n "$line"
}

# last_step_counter: extract the most recent BuildKit "N/T" step counter from a
# docker build log (plain progress prints step headers like "#12 [base 5/17] RUN ...").
# The counter appears only on the step header, so scan the whole log and take the
# last one.  Echoes e.g. "5/17", or nothing if the log has no step header yet.
last_step_counter() {
    local log_file="$1"
    [[ -f "$log_file" ]] || return
    grep -oE '\[[^]]*[0-9]+/[0-9]+\]' "$log_file" 2>/dev/null \
        | tail -1 \
        | grep -oE '[0-9]+/[0-9]+'
}

status_icon() {
    case "$1" in
        pending)   echo -ne "${C_WHITE}◯" ;;
        running)   echo -ne "${C_BLUE}⟳" ;;
        done)      echo -ne "${C_GREEN}✔" ;;
        failed)    echo -ne "${C_RED}✘" ;;
        cancelled) echo -ne "${C_GRAY}—" ;;
    esac
}

# Number of lines the graph occupies (computed once after parsing args)
GRAPH_LINES=0

compute_graph_lines() {
    # CLI + BASE + one line per dependent variant + 3 footer lines (blank + Logs + Hint)
    GRAPH_LINES=$(( 2 + ${#VARIANTS_TO_BUILD[@]} + 3 ))
}

GRAPH_DRAWN=false

# Compute column width so all lines align to the same total width.
# Top-level prefix "  " = 2 chars.  Variant prefix "    ├─ " = 8 chars.
# We compute the total width (prefix + label) and derive pad widths from that.
TOP_PAD=0
VARIANT_PAD=0

compute_column_widths() {
    local max_total=0 w tmp

    # Top-level lines: visual prefix "  " = 2 columns
    tmp="CLI";  w=$(( 2 + ${#tmp} )); [[ $w -gt $max_total ]] && max_total=$w
    tmp="BASE"; w=$(( 2 + ${#tmp} )); [[ $w -gt $max_total ]] && max_total=$w

    # Variant lines: visual prefix "    ├─ " = 7 columns
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        tmp=$(echo "$v" | tr '[:lower:]-' '[:upper:] ')
        w=$(( 7 + ${#tmp} )); [[ $w -gt $max_total ]] && max_total=$w
    done

    # Pad widths = max_total minus each visual prefix width
    TOP_PAD=$(( max_total - 2 ))
    VARIANT_PAD=$(( max_total - 7 ))
    [[ $VARIANT_PAD -lt 1 ]] && VARIANT_PAD=1
}

# Get status variable name for a step
get_status_var() {
    local step="$1"
    case "$step" in
        cli)     echo "$CLI_STATUS" ;;
        base)    echo "$BASE_STATUS" ;;
        notebook)     cat "${LOG_DIR}/notebook.status" 2>/dev/null || echo "pending" ;;
        codeserver)   cat "${LOG_DIR}/codeserver.status" 2>/dev/null || echo "pending" ;;
        desktop-xfce) cat "${LOG_DIR}/desktop-xfce.status" 2>/dev/null || echo "pending" ;;
        desktop-kde)  cat "${LOG_DIR}/desktop-kde.status" 2>/dev/null || echo "pending" ;;
        desktop-lxqt) cat "${LOG_DIR}/desktop-lxqt.status" 2>/dev/null || echo "pending" ;;
        desktop-wayland) cat "${LOG_DIR}/desktop-wayland.status" 2>/dev/null || echo "pending" ;;
        *)       echo "pending" ;;
    esac
}

# Set status variable for a step
set_status() {
    local step="$1" status="$2"
    case "$step" in
        cli)     CLI_STATUS="$status" ;;
        base)    BASE_STATUS="$status" ;;
        *)       echo "$status" > "${LOG_DIR}/${step}.status" ;;
    esac
}

draw_graph() {
    if [[ "$GRAPH_DRAWN" == "true" ]]; then
        # Move cursor up to overwrite previous graph
        printf '\033[%dA' "$GRAPH_LINES"
    fi

    local s

    # CLI
    s="$CLI_STATUS"
    printf "  %-${TOP_PAD}s  " "CLI"
    status_icon "$s"
    if [[ "$s" == "running" ]]; then
        local progress
        progress=$(last_log_line "${LOG_DIR}/cli.log")
        if [[ -n "$progress" ]]; then
            printf " ${C_GRAY}%s${C_RESET}" "$progress"
        fi
    fi
    printf "\033[K${C_RESET}\n"

    # BASE
    s="$BASE_STATUS"
    printf "  %-${TOP_PAD}s  " "BASE"
    status_icon "$s"
    if [[ "$s" == "running" ]]; then
        local progress counter
        counter=$(last_step_counter "${LOG_DIR}/base.log")
        progress=$(last_log_line "${LOG_DIR}/base.log")
        if [[ -n "$counter" ]]; then
            printf " ${C_BLUE}[%s]${C_RESET}" "$counter"
        fi
        if [[ -n "$progress" ]]; then
            printf " ${C_GRAY}%s${C_RESET}" "$progress"
        fi
    fi
    printf "\033[K${C_RESET}\n"

    # Dependent variants
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        s=$(get_status_var "$v")
        local label
        label=$(echo "$v" | tr '[:lower:]-' '[:upper:] ')
        local branch="├─"
        local last_idx=$((${#VARIANTS_TO_BUILD[@]} - 1))
        if [[ "${VARIANTS_TO_BUILD[$last_idx]}" == "$v" ]]; then
            branch="└─"
        fi
        printf "    ${branch} %-${VARIANT_PAD}s  " "$label"
        status_icon "$s"
        if [[ "$s" == "running" ]]; then
            local progress counter
            counter=$(last_step_counter "${LOG_DIR}/${v}.log")
            progress=$(last_log_line "${LOG_DIR}/${v}.log")
            if [[ -n "$counter" ]]; then
                printf " ${C_BLUE}[%s]${C_RESET}" "$counter"
            fi
            if [[ -n "$progress" ]]; then
                printf " ${C_GRAY}%s${C_RESET}" "$progress"
            fi
        fi
        printf "\033[K${C_RESET}\n"
    done

    printf "\033[K\n"
    printf "${C_GRAY}Logs:  ${LOG_DIR}/${C_RESET}\033[K\n"
    printf "${C_GRAY}Hint:  Ctrl+C to stop   Ctrl+Z to leave this run in the background${C_RESET}\033[K\n"
    GRAPH_DRAWN=true
}

# ── Ctrl+C handler ────────────────────────────────────────────────────

handle_sigint() {
    echo ""
    echo -ne "${C_BOLD}Ctrl+C received.${C_RESET} Type ${C_RED}stop${C_RESET} to stop, or press Enter to continue: "
    # Temporarily restore default SIGINT so a second Ctrl+C during read kills us
    trap - INT
    local answer=""
    read -r answer || true
    trap handle_sigint INT

    if [[ "$answer" == "stop" ]]; then
        STOP_REQUESTED=true
        cancel_running
        draw_graph
        echo -e "${C_RED}Build stopped by user.${C_RESET}"
        exit 1
    fi
}

cancel_running() {
    # Kill background variant builds by PID variable
    if [[ -n "$PIDS_NOTEBOOK" ]] && kill -0 "$PIDS_NOTEBOOK" 2>/dev/null; then
        kill "$PIDS_NOTEBOOK" 2>/dev/null || true
        wait "$PIDS_NOTEBOOK" 2>/dev/null || true
    fi
    if [[ -n "$PIDS_CODESERVER" ]] && kill -0 "$PIDS_CODESERVER" 2>/dev/null; then
        kill "$PIDS_CODESERVER" 2>/dev/null || true
        wait "$PIDS_CODESERVER" 2>/dev/null || true
    fi
    if [[ -n "$PIDS_DESKTOP_XFCE" ]] && kill -0 "$PIDS_DESKTOP_XFCE" 2>/dev/null; then
        kill "$PIDS_DESKTOP_XFCE" 2>/dev/null || true
        wait "$PIDS_DESKTOP_XFCE" 2>/dev/null || true
    fi
    if [[ -n "$PIDS_DESKTOP_KDE" ]] && kill -0 "$PIDS_DESKTOP_KDE" 2>/dev/null; then
        kill "$PIDS_DESKTOP_KDE" 2>/dev/null || true
        wait "$PIDS_DESKTOP_KDE" 2>/dev/null || true
    fi
    if [[ -n "$PIDS_DESKTOP_LXQT" ]] && kill -0 "$PIDS_DESKTOP_LXQT" 2>/dev/null; then
        kill "$PIDS_DESKTOP_LXQT" 2>/dev/null || true
        wait "$PIDS_DESKTOP_LXQT" 2>/dev/null || true
    fi

    # Mark anything not done as cancelled
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        local status_file="${LOG_DIR}/${v}.status"
        if [[ -f "$status_file" ]]; then
            local s
            s=$(cat "$status_file")
            if [[ "$s" == "running" || "$s" == "pending" ]]; then
                echo "cancelled" > "$status_file"
            fi
        fi
    done
    if [[ "$CLI_STATUS" == "running" || "$CLI_STATUS" == "pending" ]]; then
        CLI_STATUS="cancelled"
    fi
    if [[ "$BASE_STATUS" == "running" || "$BASE_STATUS" == "pending" ]]; then
        BASE_STATUS="cancelled"
    fi
}

# ── Docker login (once, before parallel builds) ───────────────────────
#
# Performed once in the parent so concurrent children don't race the macOS
# keychain credential helper (error -25299: "item already exists").  Children
# then receive --skip-login.
docker_login_once() {
    if [[ -z "${DOCKERHUB_USERNAME:-}" || -z "${DOCKERHUB_TOKEN:-}" ]]; then
        echo -e "${C_RED}❌ DOCKERHUB_USERNAME and DOCKERHUB_TOKEN must both be set for --push.${C_RESET}"
        exit 3
    fi

    echo -e "${C_GRAY}Logging in to Docker Hub as ${DOCKERHUB_USERNAME}...${C_RESET}"
    if ! echo "${DOCKERHUB_TOKEN}" | docker login -u "${DOCKERHUB_USERNAME}" --password-stdin >/dev/null; then
        echo -e "${C_RED}❌ Docker login failed.${C_RESET}"
        exit 4
    fi

    DOCKER_FLAGS+=("--skip-login")
}

# ── Build cache prune ─────────────────────────────────────────────────
#
# --no-cache means every layer is rebuilt from scratch, so nothing already in the
# build cache will be read — but buildkit still *writes* a full fresh set on the
# way through. Run that a few times and the cache is the largest thing on the
# disk: this repo reached 536 GB of it, most of a 1.1 TB root filesystem, which
# is what prompted this.
#
# So --no-cache now discards the cache before building rather than piling another
# copy on top of it. It only ever removes cache — never images, containers or
# volumes — and cache is rebuildable by definition. The cost is that any *other*
# project's next build is cold too, which is why --no-prune exists.
prune_build_cache() {
    local before after
    before=$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null | awk -F'\t' '$1=="Build Cache"{print $2}')

    echo -e "${C_GRAY}Pruning the Docker build cache (--no-cache would not reuse it anyway)...${C_RESET}"
    if ! docker buildx prune --force --all > "${LOG_DIR}/prune.log" 2>&1; then
        echo -e "${C_RED}Warning: could not prune the build cache; see ${LOG_DIR}/prune.log${C_RESET}"
        echo ""
        return 0
    fi

    after=$(docker system df --format '{{.Type}}\t{{.Size}}' 2>/dev/null | awk -F'\t' '$1=="Build Cache"{print $2}')
    echo -e "${C_GRAY}Build cache: ${before:-unknown} -> ${after:-unknown}${C_RESET}"
    echo ""
}

# ── Build steps ───────────────────────────────────────────────────────

build_cli() {
    CLI_STATUS="running"
    draw_graph

    if "${SCRIPT_DIR}/cli-build.sh" > "${LOG_DIR}/cli.log" 2>&1; then
        CLI_STATUS="done"
    else
        CLI_STATUS="failed"
    fi
    draw_graph
}

# Tag the freshly-built base as the "locally rebuilt" image the complex tests gate on
# (tests/common--source.sh → use_local_base_image). The gate exists so those tests skip
# on a machine that never rebuilt the base — but the tag used to be applied by hand, so
# it went stale at every version bump and the tests silently stopped running. Tagging it
# here keeps the gate tracking the build that is actually under test.
tag_local_base() {
    local version
    version="$(tr -d ' \t\n\r' < version.txt 2>/dev/null)"
    [[ -z "$version" ]] && return 0
    docker tag "nawaman/codingbooth:base-${version}" "cb-local/codingbooth:base-${version}" \
        >> "${LOG_DIR}/base.log" 2>&1 || true
}

build_base() {
    BASE_STATUS="running"
    draw_graph

    if "${SCRIPT_DIR}/docker-build.sh" "${DOCKER_FLAGS[@]+"${DOCKER_FLAGS[@]}"}" base > "${LOG_DIR}/base.log" 2>&1; then
        BASE_STATUS="done"
        tag_local_base
    else
        BASE_STATUS="failed"
    fi
    draw_graph
}

# Run a variant build in the background.
# Communicates status back to the parent via a file in LOG_DIR.
run_variant_bg() {
    local v="$1"
    local status_file="${LOG_DIR}/${v}.status"
    echo "running" > "$status_file"

    if "${SCRIPT_DIR}/docker-build.sh" "${DOCKER_FLAGS[@]+"${DOCKER_FLAGS[@]}"}" "$v" > "${LOG_DIR}/${v}.log" 2>&1; then
        echo "done" > "$status_file"
    else
        echo "failed" > "$status_file"
    fi
}

# Get PID variable name for a variant
get_pid_var() {
    local v="$1"
    case "$v" in
        notebook)     echo "$PIDS_NOTEBOOK" ;;
        codeserver)   echo "$PIDS_CODESERVER" ;;
        desktop-xfce) echo "$PIDS_DESKTOP_XFCE" ;;
        desktop-kde)  echo "$PIDS_DESKTOP_KDE" ;;
        desktop-lxqt) echo "$PIDS_DESKTOP_LXQT" ;;
        *)       echo "" ;;
    esac
}

# Poll background builds until all are finished, redrawing the graph.
poll_variants() {
    while true; do
        draw_graph

        # Check if all variants are finished
        local all_done=true
        for v in "${VARIANTS_TO_BUILD[@]}"; do
            local s
            s=$(get_status_var "$v")
            if [[ "$s" == "running" || "$s" == "pending" ]]; then
                all_done=false
                break
            fi
        done

        if [[ "$all_done" == "true" ]]; then
            break
        fi
        if [[ "$STOP_REQUESTED" == "true" ]]; then
            break
        fi

        sleep 2
    done
}

# ── Main ──────────────────────────────────────────────────────────────

Main() {
    ParseArgs "$@"
    compute_graph_lines
    compute_column_widths

    mkdir -p "$LOG_DIR"
    # Clean up old status files
    rm -f "${LOG_DIR}"/*.status

    trap handle_sigint INT

    echo -e "${C_BOLD}CodingBooth Build${C_RESET}"
    echo ""

    # Before anything is built: a --no-cache run cannot use the existing cache,
    # so carrying it through the run only costs disk.
    if [[ "$NO_CACHE_REQUESTED" == "true" && "$PRUNE_REQUESTED" == "true" ]]; then
        prune_build_cache
    fi

    # Log in to Docker Hub once, before any parallel child build attempts it.
    if [[ "$PUSH_REQUESTED" == "true" ]]; then
        docker_login_once
    fi

    draw_graph

    # ── Step 1: CLI ──
    build_cli
    if [[ "$CLI_STATUS" == "failed" ]]; then
        echo -e "${C_RED}CLI build failed. See ${LOG_DIR}/cli.log${C_RESET}"
        exit 1
    fi
    if [[ "$STOP_REQUESTED" == "true" ]]; then exit 1; fi

    # ── Step 2: Base ──
    build_base
    if [[ "$BASE_STATUS" == "failed" ]]; then
        echo -e "${C_RED}Base build failed. See ${LOG_DIR}/base.log${C_RESET}"
        exit 1
    fi
    if [[ "$STOP_REQUESTED" == "true" ]]; then exit 1; fi

    # ── Step 3: Remaining variants in parallel ──
    if [[ ${#VARIANTS_TO_BUILD[@]} -gt 0 ]]; then
        for v in "${VARIANTS_TO_BUILD[@]}"; do
            if [[ "$STOP_REQUESTED" == "true" ]]; then break; fi
            echo "running" > "${LOG_DIR}/${v}.status"
            run_variant_bg "$v" &
            # Store PID in the appropriate variable
            case "$v" in
                notebook)     PIDS_NOTEBOOK=$! ;;
                codeserver)   PIDS_CODESERVER=$! ;;
                desktop-xfce) PIDS_DESKTOP_XFCE=$! ;;
                desktop-kde)  PIDS_DESKTOP_KDE=$! ;;
                desktop-lxqt) PIDS_DESKTOP_LXQT=$! ;;
            esac
        done

        draw_graph

        # Poll until all background builds finish
        poll_variants
    fi

    # ── Summary ───────────────────────────────────────────────────────

    echo -e "${C_BOLD}Build Logs:${C_RESET} ${LOG_DIR}/"
    echo ""

    local has_failure=false
    # Check CLI and base
    if [[ "$CLI_STATUS" == "failed" ]]; then
        echo -e "  ${C_RED}FAILED:${C_RESET} cli  →  ${LOG_DIR}/cli.log"
        has_failure=true
    fi
    if [[ "$BASE_STATUS" == "failed" ]]; then
        echo -e "  ${C_RED}FAILED:${C_RESET} base  →  ${LOG_DIR}/base.log"
        has_failure=true
    fi
    # Check variants. Must read the .status files BEFORE cleaning them up,
    # otherwise get_status_var defaults to "pending" and failures are missed.
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        local s
        s=$(get_status_var "$v")
        if [[ "$s" == "failed" ]]; then
            echo -e "  ${C_RED}FAILED:${C_RESET} $v  →  ${LOG_DIR}/${v}.log"
            has_failure=true
        fi
    done

    # Clean up status files now that the summary has consumed them.
    rm -f "${LOG_DIR}"/*.status

    if [[ "$has_failure" == "true" ]]; then
        exit 1
    fi

    echo -e "${C_GREEN}All builds completed successfully.${C_RESET}"
}

Main "$@"
