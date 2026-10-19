#!/bin/bash
. "$(dirname "$0")/report.sh"
report "child (#!/bin/bash)"
"$(dirname "$0")/grandchild.sh"
