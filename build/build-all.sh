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

ALL_DEPENDENT_VARIANTS=(notebook codeserver desktop-xfce desktop-kde)

# ── State ─────────────────────────────────────────────────────────────

DOCKER_FLAGS=()        # flags forwarded to docker-build.sh
VARIANTS_TO_BUILD=()   # dependent variants (excludes base)
STOP_REQUESTED=false

# Per-step status: pending | running | done | failed | cancelled
declare -A STATUS
STATUS[cli]=pending
STATUS[base]=pending

# PIDs of background variant builds
declare -A PIDS

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
            --push)     DOCKER_FLAGS+=("--push");     shift ;;
            --no-cache) DOCKER_FLAGS+=("--no-cache");  shift ;;
            -h|--help)  Usage; exit 0 ;;
            *)          positional+=("$1");            shift ;;
        esac
    done

    if (( ${#positional[@]} > 0 )); then
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

    # Initialise status for each dependent variant
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        STATUS[$v]=pending
    done
}

Usage() {
    cat <<'EOF'
Usage: ./build/build-all.sh [--push] [--no-cache] [variant ...]

Builds the CLI, then the base Docker image, then the remaining variants in
parallel.  A live status graph is displayed during the build.

Options:
  --push          Forward to docker-build.sh (push + sign)
  --no-cache      Forward to docker-build.sh (no layer cache)
  -h, --help      Show this help

Variants (if none provided, all are built):
  base, notebook, codeserver, desktop-xfce, desktop-kde

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
    if (( ${#line} > max_len )); then
        line="${line:0:$max_len}..."
    fi
    echo -n "$line"
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
    tmp="CLI";  w=$(( 2 + ${#tmp} )); (( w > max_total )) && max_total=$w
    tmp="BASE"; w=$(( 2 + ${#tmp} )); (( w > max_total )) && max_total=$w

    # Variant lines: visual prefix "    ├─ " = 7 columns
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        tmp=$(echo "$v" | tr '[:lower:]-' '[:upper:] ')
        w=$(( 7 + ${#tmp} )); (( w > max_total )) && max_total=$w
    done

    # Pad widths = max_total minus each visual prefix width
    TOP_PAD=$(( max_total - 2 ))
    VARIANT_PAD=$(( max_total - 7 ))
    (( VARIANT_PAD < 1 )) && VARIANT_PAD=1
}

draw_graph() {
    if [[ "$GRAPH_DRAWN" == true ]]; then
        # Move cursor up to overwrite previous graph
        printf '\033[%dA' "$GRAPH_LINES"
    fi

    local s

    # CLI
    s="${STATUS[cli]}"
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
    s="${STATUS[base]}"
    printf "  %-${TOP_PAD}s  " "BASE"
    status_icon "$s"
    if [[ "$s" == "running" ]]; then
        local progress
        progress=$(last_log_line "${LOG_DIR}/base.log")
        if [[ -n "$progress" ]]; then
            printf " ${C_GRAY}%s${C_RESET}" "$progress"
        fi
    fi
    printf "\033[K${C_RESET}\n"

    # Dependent variants
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        s="${STATUS[$v]}"
        local label
        label=$(echo "$v" | tr '[:lower:]-' '[:upper:] ')
        local branch="├─"
        if [[ "$v" == "${VARIANTS_TO_BUILD[-1]}" ]]; then
            branch="└─"
        fi
        printf "    ${branch} %-${VARIANT_PAD}s  " "$label"
        status_icon "$s"
        if [[ "$s" == "running" ]]; then
            local progress
            progress=$(last_log_line "${LOG_DIR}/${v}.log")
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

# ── Ctrl+C handler ───────────────────────────────────────────────────

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
    # Kill background variant builds
    for v in "${!PIDS[@]}"; do
        local pid="${PIDS[$v]}"
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
    done

    # Sync final statuses from files, then mark anything not done as cancelled
    sync_variant_statuses
    for v in "${!STATUS[@]}"; do
        if [[ "${STATUS[$v]}" == "pending" || "${STATUS[$v]}" == "running" ]]; then
            STATUS[$v]=cancelled
        fi
    done
}

# ── Build steps ───────────────────────────────────────────────────────

build_cli() {
    STATUS[cli]=running
    draw_graph

    if "${SCRIPT_DIR}/cli-build.sh" > "${LOG_DIR}/cli.log" 2>&1; then
        STATUS[cli]=done
    else
        STATUS[cli]=failed
    fi
    draw_graph
}

build_base() {
    STATUS[base]=running
    draw_graph

    if "${SCRIPT_DIR}/docker-build.sh" "${DOCKER_FLAGS[@]}" base > "${LOG_DIR}/base.log" 2>&1; then
        STATUS[base]=done
    else
        STATUS[base]=failed
    fi
    draw_graph
}

# Run a variant build in the background.
# Communicates status back to the parent via a file in LOG_DIR.
run_variant_bg() {
    local v="$1"
    local status_file="${LOG_DIR}/${v}.status"
    echo "running" > "$status_file"

    if "${SCRIPT_DIR}/docker-build.sh" "${DOCKER_FLAGS[@]}" "$v" > "${LOG_DIR}/${v}.log" 2>&1; then
        echo "done" > "$status_file"
    else
        echo "failed" > "$status_file"
    fi
}

# Read status from background status files and update STATUS array.
sync_variant_statuses() {
    for v in "${VARIANTS_TO_BUILD[@]}"; do
        local status_file="${LOG_DIR}/${v}.status"
        if [[ -f "$status_file" ]]; then
            STATUS[$v]=$(cat "$status_file")
        fi
    done
}

# Poll background builds until all are finished, redrawing the graph.
poll_variants() {
    while true; do
        sync_variant_statuses
        draw_graph

        # Check if all variants are finished
        local all_done=true
        for v in "${VARIANTS_TO_BUILD[@]}"; do
            local s="${STATUS[$v]}"
            if [[ "$s" == "running" || "$s" == "pending" ]]; then
                all_done=false
                break
            fi
        done

        if [[ "$all_done" == true ]]; then
            break
        fi
        if [[ "$STOP_REQUESTED" == true ]]; then
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

    draw_graph

    # ── Step 1: CLI ──
    build_cli
    if [[ "${STATUS[cli]}" == "failed" ]]; then
        echo -e "${C_RED}CLI build failed. See ${LOG_DIR}/cli.log${C_RESET}"
        exit 1
    fi
    if [[ "$STOP_REQUESTED" == true ]]; then exit 1; fi

    # ── Step 2: Base ──
    build_base
    if [[ "${STATUS[base]}" == "failed" ]]; then
        echo -e "${C_RED}Base build failed. See ${LOG_DIR}/base.log${C_RESET}"
        exit 1
    fi
    if [[ "$STOP_REQUESTED" == true ]]; then exit 1; fi

    # ── Step 3: Remaining variants in parallel ──
    if (( ${#VARIANTS_TO_BUILD[@]} > 0 )); then
        for v in "${VARIANTS_TO_BUILD[@]}"; do
            if [[ "$STOP_REQUESTED" == true ]]; then break; fi
            STATUS[$v]=running
            run_variant_bg "$v" &
            PIDS[$v]=$!
        done

        draw_graph

        # Poll until all background builds finish
        poll_variants
    fi

    # Clean up status files
    rm -f "${LOG_DIR}"/*.status

    # ── Summary ──
    echo -e "${C_BOLD}Build Logs:${C_RESET} ${LOG_DIR}/"
    echo ""

    local has_failure=false
    for v in "${!STATUS[@]}"; do
        if [[ "${STATUS[$v]}" == "failed" ]]; then
            echo -e "  ${C_RED}FAILED:${C_RESET} $v  →  ${LOG_DIR}/${v}.log"
            has_failure=true
        fi
    done

    if [[ "$has_failure" == true ]]; then
        exit 1
    fi

    echo -e "${C_GREEN}All builds completed successfully.${C_RESET}"
}

Main "$@"
