#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin
run booth config $prj --no-tui --select "openssh+server+expose"

config="$prj/.booth/config.toml"

assert-line "$config" 'run-args = ' '["-p", "2222:2222"]'     "expose run-args in config"
finally
