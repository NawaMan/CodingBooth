#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ============================================================================
# Demo Startup Script
#
# This script runs at container startup, after all system hooks.
# Uses: Show a welcome message and set up a friendly dev environment.
# ============================================================================

set -euo pipefail

if [[ "${WS_SILENCE_BUILD:-false}" != "true" ]]; then
  echo "🚀 Running demo startup script..."
fi

# Create a welcome message file on the desktop
DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/WELCOME.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Welcome to Workspace Demo!</title>
  <style>
    body { font-family: 'Segoe UI', Tahoma, sans-serif; background: linear-gradient(135deg, #1a1a2e, #16213e); color: #eee; padding: 40px; max-width: 800px; margin: auto; }
    h1 { color: #00d9ff; text-align: center; }
    h2 { color: #ff6b6b; border-bottom: 2px solid #ff6b6b; padding-bottom: 8px; margin-top: 30px; }
    table { width: 100%; border-collapse: collapse; margin: 20px 0; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #444; }
    th { background: #0f3460; color: #00d9ff; }
    tr:hover { background: #1f4068; }
    code { background: #0f3460; padding: 3px 8px; border-radius: 4px; color: #00ff88; font-family: 'Consolas', monospace; }
    a { color: #00d9ff; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .emoji { font-size: 1.2em; }
    ul { line-height: 2; }
    li { margin: 5px 0; }
    .footer { text-align: center; margin-top: 40px; font-size: 1.5em; }
  </style>
</head>
<body>
  <h1><span class="emoji">🎉</span> Welcome to Workspace Demo!</h1>
  <p>You're running inside a containerized development environment.</p>

  <h2><span class="emoji">🚀</span> Quick Start</h2>
  <table>
    <tr><th>Action</th><th>Command</th></tr>
    <tr><td>Open terminal</td><td>Click Terminal in taskbar</td></tr>
    <tr><td>Run Python demo</td><td><code>python3 ~/workspace/Demo.py</code></td></tr>
    <tr><td>Run Java demo</td><td><code>java -cp ~/workspace Demo</code></td></tr>
    <tr><td>Open Jupyter</td><td><a href="http://localhost:10000" target="_blank">http://localhost:10000</a></td></tr>
  </table>

  <h2><span class="emoji">📦</span> What's Included</h2>
  <ul>
    <li>✅ Python 3 with Jupyter Notebook</li>
    <li>✅ Java JDK with JJava kernel</li>
    <li>✅ XFCE Desktop Environment</li>
    <li>✅ Code editors (VS Code, vim, etc.)</li>
  </ul>

  <h2><span class="emoji">📁</span> Files in Workspace</h2>
  <ul>
    <li><code>Demo.py</code> - Python hello world</li>
    <li><code>Demo.java</code> - Java hello world</li>
    <li><code>Demo-*.ipynb</code> - Jupyter notebooks</li>
  </ul>

  <p class="footer"><span class="emoji">💻</span> Happy coding!</p>
</body>
</html>
EOF

# Add a simple desktop notification if notify-send is available
if command -v notify-send &> /dev/null; then
  # Delay to ensure desktop is ready
  (sleep 5 && notify-send "Workspace Ready" "Welcome to the demo environment! 🚀" --icon=dialog-information) &
fi

# Create a fun ASCII art file
cat > "$HOME/.motd" << 'EOF'

 __        __         _                                
 \ \      / /__  _ __| | _____ _ __   __ _  ___ ___    
  \ \ /\ / / _ \| '__| |/ / __| '_ \ / _` |/ __/ _ \   
   \ V  V / (_) | |  |   <\__ \ |_) | (_| | (_|  __/   
    \_/\_/ \___/|_|  |_|\_\___/ .__/ \__,_|\___\___|   
                              |_|                       
                                          Demo Edition

EOF

# Append MOTD to bashrc if not already there
if ! grep -q ".motd" "$HOME/.bashrc" 2>/dev/null; then
  echo '[ -f ~/.motd ] && cat ~/.motd' >> "$HOME/.bashrc"
fi

if [[ "${WS_SILENCE_BUILD:-false}" != "true" ]]; then
  echo "✅ Demo startup complete!"
fi
