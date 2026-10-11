#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
set -euo pipefail
desktop="$1"
setups=/review/variants/base/setups
bash "$setups/booth-message-wrapper--setup.sh"
bash "$setups/booth-message-desktop-wrapped--setup.sh"
cp /review/variants/base/web-ttyd-split/login.html /usr/local/share/ttyd-split/login.html

# Install precisely the runtime heredocs emitted by the real setups, without
# downloading the desktop packages that this variant image already contains.
awk -v name="$desktop" '
  /^cat > / && (/STARTER_FILE/ || $0 ~ ("/usr/local/bin/start-" name " ")) && /<<.EOF.$/ { copy=1; next }
  copy && /^EOF$/ { exit }
  copy' "$setups/$desktop--setup.sh" >"/usr/local/bin/start-$desktop"
chmod +x "/usr/local/bin/start-$desktop"
awk '/^cat > "\$\{STARTUP_FILE\}" <<\x27STARTUP_EOF\x27/{copy=1;next}
     /^STARTUP_EOF$/{copy=0} copy' "$setups/tls--setup.sh" >/tmp/start-review-tls.sh

useradd -m cbauthtest
mkdir -p /home/coder/code/.booth/.tmp
chown -R cbauthtest:cbauthtest /home/coder/code
export BOOTH_TLS=true
bash /tmp/start-review-tls.sh
python3 /review/tests/complex/security/test-public-desktop-auth/probe.py "$desktop"
