#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# Remove the Docker assets left behind by the booths in examples/workspaces/ —
# and only those — instead of `docker system prune -a --volumes`, which also
# takes every other project's images, volumes and data.
#
# What counts as an example asset (see cli/src/pkg/booth for the naming):
#   containers  stopped, label cb.managed=true, cb.code-path under */examples/workspaces/*
#   sidecars    stopped, label cb.role=sidecar, cb.parent = an example booth name
#   images      codingbooth-local:<example-folder>-<variant>-<version>
#   volumes     cb-home-<example booth>  (persisted homes)
#   networks    <example booth>-<port>-net / -egress-net  (DinD / egress)
#
# Never touched: running booths (and so their images / volumes / networks), the
# shared service volumes (booth-pgdata, booth-mysqldata, ... — every project using
# those templates shares them), and base images (nawaman/codingbooth:*).
#
# Compatible with macOS's stock Bash 3.2.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXAMPLES_DIR="$(cd "$SCRIPT_DIR/../examples/workspaces" && pwd)"
ENGINE="${BOOTH_ENGINE:-docker}"

DRYRUN=false
ASSUME_YES=false
DANGLING=false
BUILD_CACHE=false

show_help() {
    cat <<EOF
Usage: ./build/clean-examples.sh [options]

Remove the containers, images, home volumes and networks created by the booths in
examples/workspaces/. Lists what it found, asks, then removes it.

Options:
  -n, --dry-run      List what would be removed; remove nothing
  -y, --yes          Do not ask for confirmation
      --dangling     Also remove dangling (<none>) images — any project's
      --build-cache  Also clear the build cache — any project's (it is only a cache)
  -h, --help         Show this help

Running booths are skipped, and so is anything they use. Shared service volumes
(booth-pgdata, booth-mysqldata, ...) and base images are never removed.

Engine: \$BOOTH_ENGINE (default: docker).
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run)  DRYRUN=true ;;
        -y|--yes)      ASSUME_YES=true ;;
        --dangling)    DANGLING=true ;;
        --build-cache) BUILD_CACHE=true ;;
        -h|--help)     show_help; exit 0 ;;
        *) echo "Unknown option: $1" >&2; show_help >&2; exit 1 ;;
    esac
    shift
done

if ! "$ENGINE" info >/dev/null 2>&1; then
    echo "Error: '$ENGINE' is not reachable — is the daemon running?" >&2
    exit 1
fi

# Example names are the folder names: a booth's project name is its folder name.
NAMES=""
for dir in "$EXAMPLES_DIR"/*/; do
    name="$(basename "$dir")"
    [[ -d "$dir/.booth" ]] || continue
    # Escape regex metacharacters (a folder name is plain, but be safe about '.').
    name="$(printf '%s' "$name" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
    NAMES="${NAMES:+$NAMES|}$name"
done
if [[ -z "$NAMES" ]]; then
    echo "No examples found under $EXAMPLES_DIR" >&2
    exit 1
fi
# A booth's container name is the project name, plus a port suffix for a second
# booth from the same folder.
BOOTH_RE="^($NAMES)(-[0-9]+)?$"

# --- Collect ------------------------------------------------------------------

CONTAINERS="$("$ENGINE" ps -a --filter label=cb.managed=true \
        --format '{{.ID}}|{{.Names}}|{{.State}}|{{.Label "cb.code-path"}}|{{.Label "cb.role"}}|{{.Label "cb.parent"}}' \
    | awk -F'|' -v re="$BOOTH_RE" '
        $3 == "running" { next }
        $5 == "sidecar" { if ($6 ~ re) print $1 "|" $2 " (sidecar of " $6 ")"; next }
        $4 ~ /\/examples\/workspaces\// { print $1 "|" $2 }')"

RUNNING="$("$ENGINE" ps --filter label=cb.managed=true \
        --format '{{.Names}}|{{.Label "cb.code-path"}}' \
    | awk -F'|' '$2 ~ /\/examples\/workspaces\// { print $1 }')"

# Images a running container uses are left alone (a shared ID would otherwise be
# silently untagged rather than refused).
IN_USE="$("$ENGINE" ps --format '{{.Image}}' | tr '\n' ' ')"
IMAGES="$("$ENGINE" images --filter 'reference=codingbooth-local' \
        --format '{{.Repository}}:{{.Tag}}|{{.Size}}' \
    | awk -F'|' -v re="^codingbooth-local:($NAMES)-" -v used=" $IN_USE" \
        '$1 ~ re && index(used, " " $1 " ") == 0')"

VOLUMES="$("$ENGINE" volume ls -q --filter label=cb.managed=true \
    | awk -v re="^cb-home-($NAMES)(-[0-9]+)?$" '$0 ~ re')"

NETWORKS="$("$ENGINE" network ls --format '{{.Name}}' \
    | awk -v re="^($NAMES)-[0-9]+-(egress-)?net$" '$0 ~ re')"

# --- Report -------------------------------------------------------------------

count() { [[ -z "$1" ]] && echo 0 || printf '%s\n' "$1" | wc -l | tr -d ' '; }

section() { # title, lines, column-to-show
    local title="$1" lines="$2" col="${3:-}"
    echo "$title ($(count "$lines")):"
    if [[ -z "$lines" ]]; then
        echo "  (none)"
    elif [[ -n "$col" ]]; then
        printf '%s\n' "$lines" | awk -F'|' -v c="$col" '{ print "  " $c }'
    else
        printf '%s\n' "$lines" | sed 's/^/  /' | tr '|' '\t'
    fi
}

echo "Engine: $ENGINE    Examples: $EXAMPLES_DIR"
echo
section "Stopped containers" "$CONTAINERS" 2
section "Images"             "$IMAGES"
section "Home volumes"       "$VOLUMES"
section "Networks"           "$NETWORKS"
$DANGLING    && echo "Dangling images: all of them (--dangling)"
$BUILD_CACHE && echo "Build cache: all of it (--build-cache)"
if [[ -n "$RUNNING" ]]; then
    echo
    echo "Skipped — running example booths (stop them first to reclaim what they use):"
    printf '%s\n' "$RUNNING" | sed 's/^/  /'
fi
echo

TOTAL=$(( $(count "$CONTAINERS") + $(count "$IMAGES") + $(count "$VOLUMES") + $(count "$NETWORKS") ))
if [[ $TOTAL -eq 0 ]] && ! $DANGLING && ! $BUILD_CACHE; then
    echo "Nothing to clean."
    exit 0
fi

if $DRYRUN; then
    echo "Dry run — nothing removed."
    exit 0
fi

if ! $ASSUME_YES; then
    if [[ ! -t 0 ]]; then
        echo "Not a terminal — pass --yes to remove without asking." >&2
        exit 1
    fi
    read -r -p "Remove all of the above? [y/N] " answer
    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Cancelled."; exit 0 ;;
    esac
fi

# --- Remove -------------------------------------------------------------------
# One item at a time: the engine refuses anything still in use, and one refusal
# should not stop the rest.

FAILED=0
remove_each() { # label, lines ("id" or "id|shown-as"), command...
    local label="$1" lines="$2"; shift 2
    [[ -z "$lines" ]] && return 0
    local item id shown
    while IFS= read -r item; do
        id="${item%%|*}"
        shown="${item#*|}"
        if "$ENGINE" "$@" "$id" >/dev/null 2>&1; then
            echo "  removed $label $shown"
        else
            echo "  kept    $label $shown (in use or already gone)"
            FAILED=$((FAILED + 1))
        fi
    done <<< "$lines"
}

# Containers first, so their images, volumes and networks become free.
remove_each container "$CONTAINERS" rm
remove_each image     "$(printf '%s\n' "$IMAGES"     | cut -d'|' -f1 | sed '/^$/d')" rmi
remove_each volume    "$VOLUMES"  volume rm
remove_each network   "$NETWORKS" network rm

if $DANGLING; then
    echo "  pruning dangling images..."
    "$ENGINE" image prune -f | tail -n 1 | sed 's/^/  /'
fi
if $BUILD_CACHE; then
    echo "  pruning build cache..."
    "$ENGINE" builder prune -f | tail -n 1 | sed 's/^/  /'
fi

echo
if [[ $FAILED -gt 0 ]]; then
    echo "Done — $FAILED item(s) kept because they are in use."
else
    echo "Done."
fi
