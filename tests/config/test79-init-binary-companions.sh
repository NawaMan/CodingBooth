#!/bin/bash
# Phase 1 binary companions: protobuf, buf, ffmpeg, graphviz templates
# and the protobuf+go protoc plugins extension.
source "$(dirname "$0")/test-helpers--source.sh"

begin

# --- ffmpeg ---
run booth config $prj --no-tui --select "ffmpeg"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "install apt " 'ffmpeg'  "ffmpeg installs via apt"

# --- graphviz ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "graphviz"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "install apt " 'graphviz'  "graphviz installs via apt"

# --- protobuf (protoc) ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "protobuf"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "install apt " 'protobuf-compiler'  "protobuf installs protoc via apt"

# --- protobuf + Go plugins (requires go) ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "go/protobuf+go"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "install apt " 'protobuf-compiler'  "protobuf+go still installs protoc"
assert-line "$boothfile" "install go google.golang.org/protobuf/cmd/protoc-gen-go@" 'latest'  "protoc-gen-go plugin"
assert-line "$boothfile" "install go google.golang.org/grpc/cmd/protoc-gen-go-grpc@" 'latest'  "protoc-gen-go-grpc plugin"
assert-line "$boothfile" "arg GO_VERSION=" '1.25.7'  "go auto-selected for protobuf+go"

# --- buf default version ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "buf"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg BUF_VERSION=" 'latest'  "buf default version is latest"
assert-line "$boothfile" "setup buf --version " '${BUF_VERSION}'  "buf setup uses BUF_VERSION"

# --- buf pinned version ---
run rm -Rf $prj
mkdir -p $prj
run booth config $prj --no-tui --select "buf:1.72.0"
boothfile="$prj/.booth/Boothfile"
assert-line "$boothfile" "arg BUF_VERSION=" '1.72.0'  "buf version pin"

finally
