#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

# Test 1: Orca defaults come from the catalog
run booth config $prj --no-tui --select "orca"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg ORCA_VERSION=' "$(template-default orca ORCA_VERSION)" "default version is the catalog's"
assert-line "$boothfile" 'arg ORCA_PORT='    "$(template-default orca ORCA_PORT)"    "default port is the catalog's"
assert-line "$boothfile" 'setup orca ' '--version ${ORCA_VERSION} --port ${ORCA_PORT}' "setup passes version and port"

# Test 2: version and port pins land
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "orca:1.4.238,6800"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg ORCA_VERSION=' '1.4.238' "version pin"
assert-line "$boothfile" 'arg ORCA_PORT='    '6800'    "port pin"

# Test 3: serve autostarts orca-serve on the port param
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "orca:latest,6800+serve"
startup="$prj/.booth/startups/65-orca-serve--startup.sh"
assert-line "$startup" 'PORT='   '${ORCA_PORT:-6800}'                       "serve uses the port param"
assert-line "$startup" 'nohup '  'orca-serve "$PORT" > "$LOG_FILE" 2>&1 &'  "serve runs orca-serve"

# Test 4: expose publishes the port AND hands the host port to orca-serve,
# which advertises it in the pairing link the host browser dials.
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "orca+serve+expose:26768"
config="$prj/.booth/config.toml"
assert-line "$config" '    "-p", ' "\"26768:$(template-default orca ORCA_PORT)\"," "expose host-port override"
assert-line "$config" '    "-e", ' '"ORCA_HOST_PORT=26768"'                        "host port is passed to the booth"

finally
