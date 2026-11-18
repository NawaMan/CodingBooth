#!/bin/bash
# Which bash runs each level of a script tree. Every script here keeps its
# ordinary shebang; nothing names bash-3.2. Run it two ways and compare:
#   ./scripts/which-bash.sh               every level is the image's bash
#   use-bash 3.2 ./scripts/which-bash.sh  every level is 3.2
# Each level also tries an associative array (declare -A), which bash 4 added.
# On 3.2 it fails, so the column shows the behaviour, not only the version.
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/which-bash/report.sh"

report "top (#!/bin/bash)"
report_sourced() { report "function / source"; }
report_sourced
( report "subshell ( )" )
"$here/which-bash/child.sh"
"$here/which-bash/env-child.sh"
bash -c ". '$here/which-bash/report.sh'; report 'bash -c'"
sh -c 'printf "%-24s %s\n" "sh -c" "dash (not bash)"'
