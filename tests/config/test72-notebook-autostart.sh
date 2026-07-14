#!/bin/bash
# The notebook auto-start + expose extensions.
#
# `notebook` installs a /usr/local/bin/start-notebook launcher but nothing ever calls it —
# outside the notebook variant you had to start JupyterLab by hand. `notebook/autostart`
# nohups it from a startup script so a booth running some OTHER UI (code-server, a desktop,
# or here plain base) is also serving JupyterLab on NOTEBOOK_PORT. `notebook/expose`
# publishes that port to the host.
#
# The auto-start MUST be a no-op on the notebook variant: start-notebook-wrapped already
# runs JupyterLab there on this very port (18888, behind the booth's nginx), so a second
# one would fight it for the port. That guard is the reason this test asserts on
# BOOTH_VARIANT_TAG being base — it is the branch that is supposed to launch.
source "$(dirname "$0")/test-helpers--source.sh"

begin

run booth config $prj --no-tui --variant base --select "notebook+autostart+expose"

booth-collect "
echo -n '1: ' ; test -f .booth/startups/65-notebook-autostart--startup.sh && echo 'present' || echo 'not found' ;
echo -n '2: ' ; grep -q 'BOOTH_VARIANT_TAG' .booth/startups/65-notebook-autostart--startup.sh && echo 'guarded' || echo 'unguarded' ;
echo -n '3: ' ; grep -q '\"18888:18888\"' .booth/config.toml && echo 'published' || echo 'not found' ;
echo -n '4: ' ; echo \"\${BOOTH_VARIANT_TAG:-unset}\" ;
echo -n '5: ' ; which start-notebook || echo 'not found' ;
echo -n '6: ' ; for i in \$(seq 1 45); do curl -sf -o /dev/null http://127.0.0.1:18888/lab && break ; sleep 1 ; done ;
                curl -sf -o /dev/null http://127.0.0.1:18888/lab && echo 'serving' || echo 'not serving' ;
"

assert-line "$tmpfile" "1: " "present"                     "the auto-start startup script is generated"
assert-line "$tmpfile" "2: " "guarded"                     "auto-start is guarded by variant (no-op on the notebook variant)"
assert-line "$tmpfile" "3: " "published"                   "the expose extension publishes the notebook port"
assert-line "$tmpfile" "4: " "base"                        "this booth is NOT the notebook variant (guard's launch branch)"
assert-line "$tmpfile" "5: " "/usr/local/bin/start-notebook" "the start-notebook launcher is on PATH"
assert-line "$tmpfile" "6: " "serving"                     "JupyterLab is auto-started and serving on port 18888"
finally
