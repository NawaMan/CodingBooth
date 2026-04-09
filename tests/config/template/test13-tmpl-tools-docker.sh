#!/bin/bash
# Template test: Docker-in-Docker + Compose + Buildx + kind
# Note: Uses --dind flag for booth-collect so docker daemon is available.
source "$(dirname "$0")/../test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "dind/docker-compose/docker-buildx"

booth-collect-dind "
echo -n '1: ' ; command -v docker >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '2: ' ; docker compose version >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
echo -n '3: ' ; docker buildx version  >/dev/null 2>&1 && echo 'OK' || echo 'FAIL' ;
"

assert-line "$tmpfile" "1: " "OK"  "Docker (dind) is installed"
assert-line "$tmpfile" "2: " "OK"  "Docker Compose is installed"
assert-line "$tmpfile" "3: " "OK"  "Docker Buildx is installed"
finally
