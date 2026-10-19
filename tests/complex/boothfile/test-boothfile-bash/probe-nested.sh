#!/bin/bash
# Each level reports the bash it runs under. Under use-bash every line is the
# chosen release; without it every line is the distro bash.
echo "top:$BASH_VERSION"
./probe-nested-child.sh
./probe-nested-env.sh
bash -c 'echo "bash-c:$BASH_VERSION"'
