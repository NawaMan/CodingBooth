#!/bin/bash
# Rust: what `booth config` emits for the toolchain environment, the writable-toolchain
# extensions, and the caches.
#
#  - `rust` puts RUSTUP_HOME and the cargo bin dirs on the IMAGE environment, so `booth
#    exec` (no shell, no /etc/profile.d) finds cargo, rustfmt, clippy and installed tools.
#  - toolchain-file is auto-selected and copies only rust-toolchain(.toml), never the whole
#    project, into the build.
#  - registry-cache (project-local, .booth/cache/) is auto-selected; cargo-cache (a writable
#    host mount that needs consent) is not.
#  - sccache is opt-in: it installs sccache and sets RUSTC_WRAPPER on the container
#    environment (never the image's), with the host's ~/.cache/sccache as the cache.
#  - targets / components / gui-deps emit their install lines.
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"
counts="$prj/counts.txt"

# count-lines <file> <fixed-string>: how many lines contain it.
function count-lines() { grep -cF -- "$2" "$1" 2>/dev/null || true; }

# --- Defaults ---------------------------------------------------------------
run booth config $prj --no-tui --select "rust"

assert-line "$boothfile" "env RUSTUP_HOME=" "/opt/rust/rustup"                       "RUSTUP_HOME is an image env"
assert-line "$boothfile" "env PATH=" '/home/coder/.cargo/bin:/opt/rust/cargo/bin:$PATH' "cargo bin dirs are on the image PATH"
assert-line "$boothfile" "setup rust-toolchain-file " "/tmp/cb-rust-toolchain"        "toolchain-file is auto-selected"
assert-line "$boothfile" "copy .booth/Boothfile " "rust-toolchai[n] rust-toolchain.tom[l] /tmp/cb-rust-toolchain/" \
                                                                                        "toolchain-file copies only the toolchain files"
{
    echo "host-registry=$(count-lines "$config" '.cargo/registry:/home/coder/.cargo/registry')"
    echo "registry-cache=$([[ -f $prj/.booth/cache/home/coder/.cargo/registry/.mount-this ]] && echo yes || echo no)"
    echo "git-cache=$([[ -f $prj/.booth/cache/home/coder/.cargo/git/.mount-this ]] && echo yes || echo no)"
    echo "context-mount=$(count-lines "$boothfile" 'type=bind,target=/tmp/ctx')"
    echo "sccache=$(count-lines "$boothfile" 'setup sccache')"
} > "$counts"
assert-line "$counts" "host-registry="  "0"   "cargo-cache (host mount) is not auto-selected"
assert-line "$counts" "registry-cache=" "yes" "registry-cache persists ~/.cargo/registry"
assert-line "$counts" "git-cache="      "yes" "registry-cache persists ~/.cargo/git"
assert-line "$counts" "context-mount="  "0"   "no step mounts the whole project by default"
assert-line "$counts" "sccache="        "0"   "sccache is not auto-selected"

# --- targets / components / gui-deps -----------------------------------------
run booth config $prj --no-tui --overwrite \
    --select 'rust+targets:"wasm32-unknown-unknown,aarch64-unknown-linux-gnu"+components:"llvm-tools"+gui-deps'

assert-line "$boothfile" "arg RUST_TARGETS="    "wasm32-unknown-unknown,aarch64-unknown-linux-gnu" "RUST_TARGETS arg"
assert-line "$boothfile" "install rustup target " '${RUST_TARGETS}'                             "install rustup target line"
assert-line "$boothfile" "arg RUST_COMPONENTS=" "llvm-tools"                                    "RUST_COMPONENTS arg"
assert-line "$boothfile" "install rustup component " '${RUST_COMPONENTS}'                       "install rustup component line"
{
    echo "gui-xkbcommon=$(count-lines "$boothfile" 'libxkbcommon-dev')"
    echo "gui-before-rust=$(awk '/^install apt .*libxkbcommon-dev/{a=NR} /^setup rust /{r=NR} END{print (a && r && a<r) ? "yes" : "no"}' "$boothfile")"
} > "$counts"
assert-line "$counts" "gui-xkbcommon="   "1"   "gui-deps installs the GUI libraries"
assert-line "$counts" "gui-before-rust=" "yes" "gui-deps runs before setup rust (order 45)"

# --- Opting out / opting in ----------------------------------------------------
run booth config $prj --no-tui --overwrite --select 'rust+cargo-cache~toolchain-file'
{
    echo "host-registry=$(count-lines "$config" '.cargo/registry:/home/coder/.cargo/registry')"
    echo "toolchain-file=$(count-lines "$boothfile" 'setup rust-toolchain-file')"
} > "$counts"
assert-line "$counts" "host-registry="  "1" "cargo-cache still mounts the host registry when selected"
assert-line "$counts" "toolchain-file=" "0" "~toolchain-file drops the toolchain step"

# --- sccache ---------------------------------------------------------------------
run booth config $prj --no-tui --overwrite --select 'rust+sccache'
assert-line "$boothfile" "arg SCCACHE_VERSION=" "$(template-default rust+sccache SCCACHE_VERSION)" \
                                                                        "sccache default version is the catalog's"
assert-line "$boothfile" "setup sccache " '--version ${SCCACHE_VERSION}' "setup sccache line"
{
    echo "wrapper-env=$(count-lines "$config" '"RUSTC_WRAPPER=sccache"')"
    echo "wrapper-image=$(count-lines "$boothfile" 'RUSTC_WRAPPER')"
    echo "host-cache=$(count-lines "$config" '$HOME/.cache/sccache:/home/coder/.cache/sccache:create')"
} > "$counts"
assert-line "$counts" "wrapper-env="   "1" "RUSTC_WRAPPER is set on the container environment"
assert-line "$counts" "wrapper-image=" "0" "RUSTC_WRAPPER is not on the image environment (build-time cargo install)"
assert-line "$counts" "host-cache="    "1" "the host's ~/.cache/sccache is the cache, created when missing"

run booth config $prj --no-tui --overwrite --select 'rust+sccache:0.18.0'
assert-line "$boothfile" "arg SCCACHE_VERSION=" "0.18.0" "sccache version pin"

finally
