#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth init new $prj --select "openssh+credential"

config="$prj/.booth/config.toml"

assert-line "$config" 'run-args = ' '["-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro"]'  "credential run-args in config"
finally
