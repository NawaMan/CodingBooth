#!/bin/bash
source "$(dirname "$0")/test-helpers--source.sh"

# Covers the new protobuf language plugins (rust, java, nodejs, python, ruby,
# cpp, grpc-web), the Ant build-tool extension, GraalVM as a JDK_VENDOR choice,
# and the CUDA Toolkit template -- each asserting the one line that proves the
# right install mechanism got wired, not just that the referenced script
# exists (test86) or that its params are used somewhere (test88).

begin

boothfile="$prj/.booth/Boothfile"
configtoml="$prj/.booth/config.toml"

# --- protobuf language plugins -------------------------------------------
run booth config $prj --no-tui --select 'protobuf+rust'
assert-line "$boothfile" "install cargo protoc-gen-prost" ""    "protobuf+rust installs protoc-gen-prost via cargo"
assert-line "$boothfile" "install cargo protoc-gen-tonic" ""    "protobuf+rust installs protoc-gen-tonic via cargo"

run booth config $prj --no-tui --overwrite --select 'protobuf+java'
assert-line "$boothfile" "setup protoc-gen-grpc-java" ' ${PROTOC_GEN_GRPC_JAVA_VERSION}' "protobuf+java installs via its own setup script"

run booth config $prj --no-tui --overwrite --select 'protobuf+nodejs'
assert-line "$boothfile" "install npm ts-proto" ""               "protobuf+nodejs installs ts-proto via npm"

run booth config $prj --no-tui --overwrite --select 'protobuf+python'
assert-line "$boothfile" "install pip grpcio-tools" ""           "protobuf+python installs grpcio-tools via pip"

run booth config $prj --no-tui --overwrite --select 'protobuf+ruby'
assert-line "$boothfile" "install gem grpc-tools" ""              "protobuf+ruby installs grpc-tools via gem"

run booth config $prj --no-tui --overwrite --select 'protobuf+cpp'
assert-line "$boothfile" "install apt protobuf-compiler-grpc" ""  "protobuf+cpp installs grpc_cpp_plugin via apt"

run booth config $prj --no-tui --overwrite --select 'protobuf+grpc-web'
assert-line "$boothfile" "setup protoc-gen-grpc-web" ' ${PROTOC_GEN_GRPC_WEB_VERSION}' "protobuf+grpc-web installs via its own setup script"

# --- Ant ------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select 'java+ant'
assert-line "$boothfile" "setup ant" ' ${ANT_VERSION}'            "java+ant installs via setup ant"

# --- GraalVM as a JDK_VENDOR choice ----------------------------------------
# Positional params: java:JDK_VERSION,JDK_VENDOR.
run booth config $prj --no-tui --overwrite --select 'java:25,graalvm'
assert-line "$boothfile" "setup jdk" ' ${JDK_VERSION} ${JDK_VENDOR}' "java:25,graalvm still compiles to setup jdk"
assert-line "$boothfile" "arg JDK_VENDOR=" "graalvm"                 "JDK_VENDOR=graalvm reaches the Boothfile"

# --- CUDA -------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select 'cuda'
assert-line "$boothfile" "setup cuda" ' ${CUDA_VERSION}'          "cuda installs via setup cuda"
assert-line "$configtoml" 'run-args = ' '["--gpus", "all"]'       "cuda wires --gpus all into run-args"

finally
