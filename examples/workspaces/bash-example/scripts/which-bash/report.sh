# Sourced by the which-bash scripts. Prints one line: where we are, the bash
# running it, and whether declare -A works (bash 4 and later).
report() {
  if ( declare -A probe 2>/dev/null ); then assoc=yes; else assoc=no; fi
  printf '%-24s %-20s declare -A: %s\n' "$1" "$BASH_VERSION" "$assoc"
}
