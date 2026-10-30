#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# provision-example.sh  (EXPERIMENT -- see docs/REUSE_BOOTH.md)
#
# Replays an example's .booth/Boothfile on the machine itself, the way the
# compiled Dockerfile would in an image:
#   arg K=V            -> substituted into later lines
#   env K=V            -> exported now, and kept in /etc/profile.d/05-cb-example-env.sh
#                         with /home/coder rewritten to the real user's home
#   setup X a...       -> X--setup.sh a...      (root, login shell)
#   install M p...     -> M--install.sh p...    (root, login shell)
#   run [--mount=type=bind,target=T] cmd
#                      -> cmd                   (root, login shell; T is a symlink to
#                                                the example folder, the build context)
#   copy src... dest   -> cp -a                 (src globs relative to the example folder)
#   workdir/expose/label -> skipped, logged
# The example's own .booth/setups/ comes first on PATH, as in a booth, so a project
# setup (lamp-init, sales-explorer-icon) is found and shadows a built-in one.
# Every line is attempted; a failing setup is recorded and the next one runs,
# so one pass yields the whole report (written to $REPORT).
#
# Usage: sudo CB_TARGET=gha|host CB_USER_NAME=x CB_USER_HOME=/home/x REPORT=file \
#             provision-example.sh <example-dir>
# -----------------------------------------------------------------------------

set -uo pipefail

EXAMPLE="${1:?usage: provision-example.sh <example-dir>}"
BOOTHFILE="$EXAMPLE/.booth/Boothfile"
CB_USER_HOME="${CB_USER_HOME:?CB_USER_HOME is required}"
REPORT="${REPORT:-$HOME/host-provision-report.txt}"
ENV_FILE=/etc/profile.d/05-cb-example-env.sh
[ "$EUID" -eq 0 ] || { echo "❌ Run as root (use sudo)" >&2; exit 1; }

export PATH="/opt/codingbooth/setups:$PATH"
[ -d "$EXAMPLE/.booth/setups" ] && export PATH="$(cd "$EXAMPLE/.booth/setups" && pwd):$PATH"
declare -A ARGS=()
: > "$ENV_FILE"
echo "# Profile: env lines of $BOOTHFILE (host-provision experiment)" >> "$ENV_FILE"
chmod 644 "$ENV_FILE"

record() { printf '%-5s %s\n' "$1" "$2" | tee -a "$REPORT"; }

# ${NAME} from arg lines (the form the catalog writes); a bare $NAME and anything
# else is left for the shell.
subst_args() {
  local s="$1" k
  for k in "${!ARGS[@]}"; do
    s="${s//\$\{$k\}/${ARGS[$k]}}"
  done
  printf '%s' "$s"
}

run_line() {
  local label="$1" cmd="$2" log
  log="$(mktemp)"
  printf '\n[provision-example] --- %s\n' "$cmd"
  if bash -lc "$cmd" < /dev/null 2>&1 | tee "$log"; then     # no tty: skip_setup exits 0
    if grep -q '^SKIP: ' "$log"; then
      record SKIP "$label  ($(grep -m1 '^SKIP: ' "$log" | cut -c7-120))"
    else
      record PASS "$label"
    fi
  else
    record FAIL "$label  (last line: $(grep -v '^\s*$' "$log" | tail -n 1 | cut -c1-120))"
  fi
  rm -f "$log"
}

echo "== $(basename "$EXAMPLE") (CB_TARGET=${CB_TARGET:-?}, home=$CB_USER_HOME)" | tee -a "$REPORT"
[ -f "$BOOTHFILE" ] || record SKIP "no .booth/Boothfile (config.toml only)"

while IFS= read -r raw || [ -n "$raw" ]; do
  line="${raw%%#*}"                                         # drop comments
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  [ -n "$line" ] || continue
  cmd="${line%% *}"
  rest="${line#"$cmd"}"; rest="${rest# }"
  case "$cmd" in
    arg)
      ARGS["${rest%%=*}"]="${rest#*=}"
      ;;
    env)
      key="${rest%%=*}"
      val="$(subst_args "${rest#*=}")"
      val="${val//\/home\/coder/$CB_USER_HOME}"
      printf 'export %s="%s"\n' "$key" "$val" >> "$ENV_FILE"
      eval "export $key=\"$val\""                            # like Dockerfile ENV: visible to later lines
      ;;
    setup)
      expanded="$(subst_args "$rest")"
      name="${expanded%% *}"
      args="${expanded#"$name"}"
      run_line "setup $expanded" "$name--setup.sh$args"
      ;;
    install)
      expanded="$(subst_args "$rest")"
      mgr="${expanded%% *}"
      args="${expanded#"$mgr"}"
      run_line "install $expanded" "$mgr--install.sh$args"
      ;;
    run)
      expanded="$(subst_args "$rest")"
      ctx=""
      if [[ "$expanded" =~ ^--mount=type=bind,target=([^[:space:]]+)[[:space:]]+(.*)$ ]]; then
        ctx="${BASH_REMATCH[1]}"; expanded="${BASH_REMATCH[2]}"
        rm -rf "$ctx"; ln -s "$(cd "$EXAMPLE" && pwd)" "$ctx"
      fi
      run_line "run ${expanded:0:100}" "cd / && $expanded"
      [ -z "$ctx" ] || rm -f "$ctx"
      ;;
    copy)
      expanded="$(subst_args "$rest")"
      read -ra parts <<< "$expanded"
      dest="${parts[-1]}"; unset 'parts[-1]'
      run_line "copy $expanded" "mkdir -p '$dest' && cd '$(cd "$EXAMPLE" && pwd)' && shopt -s nullglob && for f in ${parts[*]}; do cp -a \"\$f\" '$dest'; done"
      ;;
    workdir|expose|label)
      record SKIP "$cmd $rest  (not replayed outside a container)"
      ;;
    *)
      record SKIP "$line  (unknown directive)"
      ;;
  esac
done < <([ -f "$BOOTHFILE" ] && cat "$BOOTHFILE")

# .booth/config.toml holds the run-time settings: the variant (the image a
# booth starts from), run-args (env, volumes, ports, devices), cmds, dind, ...
# None of them is replayed. Each is recorded as DROP, so a PASS elsewhere in the
# report is not read as "the same as the booth". On gha the variant is BASE instead:
# a gha run is defined as a base booth (--variant base), so it is overridden, not lost.
# Under `booth prepare` (CB_PREPARE_VARIANT set) the variant and the -e KEY=VALUE
# run-args are carried out by prepare itself, so they are APPLY, not DROP.
CONFIG="$EXAMPLE/.booth/config.toml"
if [ -f "$CONFIG" ]; then
  while IFS= read -r item; do
    case "$item" in
      variant*) if [ "${CB_TARGET:-}" = gha ]; then
                  record BASE "$item  (config.toml; a gha run is a base booth, like --variant base)"
                elif [ -n "${CB_PREPARE_VARIANT:-}" ]; then
                  record APPLY "$item  (config.toml; booth prepare replayed variant $CB_PREPARE_VARIANT)"
                else
                  record DROP "$item  (config.toml, not replayed; host: undecided)"
                fi ;;
      "run-args -e "?*=*|"run-args --env "?*=*|"run-args --env="?*=*|"run-args -e"[!\ ]*=*)
                if [ -n "${CB_PREPARE_VARIANT:-}" ]; then
                  record APPLY "$item  (config.toml; booth prepare exports it, /home/coder -> $CB_USER_HOME)"
                else
                  record DROP "$item  (config.toml, not replayed)"
                fi ;;
      *)        record DROP "$item  (config.toml, not replayed)" ;;
    esac
  done < <(awk '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    in_args {
      line = $0
      while (match(line, /"([^"\\]|\\.)*"/)) {
        arg = substr(line, RSTART + 1, RLENGTH - 2); line = substr(line, RSTART + RLENGTH)
        if (flag != "") { print "run-args " flag " " arg; flag = "" }
        else if (arg ~ /^-(e|v|p)$/ || arg ~ /^--(env|volume|mount|publish|device|cap-add|add-host)$/) flag = arg
        else print "run-args " arg
      }
      if ($0 ~ /\]/) in_args = 0
      next
    }
    /^run-args[[:space:]]*=/ { in_args = 1; if ($0 ~ /\]/) in_args = 0; next }
    /^[A-Za-z0-9_-]+[[:space:]]*=/ { print $0 }
  ' "$CONFIG")
fi
