#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "nodejs+npm-install"

# Create a package.json with express as a dependency
cat > "$prj/package.json" <<'PACKAGE'
{
  "name": "test-npm-install",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.21.0"
  }
}
PACKAGE

booth-collect "
echo -n '1: ' ; node -e \"require('express'); console.log('OK')\" 2>&1 ;
"

assert-line "$tmpfile" "1: " "OK"  "express is installed via npm-install"
finally
