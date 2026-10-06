set -u
a=()
# The form that is safe on bash 3.2 (macOS /bin/bash) and on bash 5.
echo ${a[@]+"${a[@]}"}
echo survived
