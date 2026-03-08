#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

begin

# Test 1: Dotnet with default channel (9.0)
run booth init new $prj --select "dotnet"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg DOTNET_CHANNEL=' '9.0'  "default channel is 9.0"
assert-line "$boothfile" 'setup dotnet --channel ' '${DOTNET_CHANNEL}'  "Boothfile uses param reference"

# Test 2: Dotnet with custom channel
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "dotnet:8.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'arg DOTNET_CHANNEL=' '8.0'  "custom channel 8.0"

# Test 3: VS Code extension auto-selected
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "dotnet"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'setup dotnet-code-' 'extension'  "vscode extension auto-selected"

# Test 4: wasm-tools extension (explicit)
run rm -Rf $prj
mkdir -p $prj
run booth init new $prj --select "dotnet+wasm-tools"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" 'run dotnet workload install ' 'wasm-tools --skip-manifest-update'  "wasm-tools workload installed"

finally
