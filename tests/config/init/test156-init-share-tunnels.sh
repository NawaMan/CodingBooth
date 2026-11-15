#!/bin/bash
source "$(dirname "$0")/../test-helpers--source.sh"

begin

boothfile="$prj/.booth/Boothfile"
config="$prj/.booth/config.toml"

# --- 1. cloudflared: version arg from the catalog, Share auto-selected -------
run booth config $prj --no-tui --select "cloudflared"
assert-line "$boothfile" "arg CLOUDFLARED_VERSION=" "$(template-default cloudflared CLOUDFLARED_VERSION)" "CLOUDFLARED_VERSION default"
assert-line "$boothfile" 'setup cloudflared --version ${CLOUDFLARED_VERSION}' "" "cloudflared setup line"
assert-line "$boothfile" 'setup cloudflared-share' "" "cloudflared+share is auto-selected"

run booth config $prj --no-tui --overwrite --select "cloudflared:2026.10.7"
assert-line "$boothfile" "arg CLOUDFLARED_VERSION=" "2026.10.7" "CLOUDFLARED_VERSION pin"

# --- 2. ngrok: token passthrough, Share auto-selected ------------------------
run booth config $prj --no-tui --overwrite --select "ngrok"
assert-line "$boothfile" 'setup ngrok' "" "ngrok setup line"
assert-line "$boothfile" 'setup ngrok-share' "" "ngrok+share is auto-selected"
assert-line "$config" 'run-args = ' '["-e", "NGROK_AUTHTOKEN"]' "NGROK_AUTHTOKEN is passed from the host"

# --- 3. ~share drops the command, keeps the tool ------------------------------
run booth config $prj --no-tui --overwrite --select "ngrok~share/cloudflared~share"
assert-line "$boothfile" 'setup ngrok' "" "ngrok kept without its Share"
if grep -qE '^setup (ngrok|cloudflared)-share' "$boothfile"; then
    echo "  ❌ ~share should drop the share setup lines"
    cat "$boothfile"
    exit 1
fi
echo "  ✅ ~share drops ngrok-share and cloudflared-share"

finally
