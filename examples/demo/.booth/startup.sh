#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# ============================================================================
# Demo Startup Script
#
# This script runs at container startup, after all system hooks.
# The aims is to show what sort of thing you can do at the startup of a booth.
# ============================================================================

set -euo pipefail

if [[ "${CB_SILENCE_BUILD:-false}" != "true" ]]; then
  echo "🚀 Running demo startup script..."
fi

# Add a simple desktop notification if notify-send is available
if command -v notify-send &> /dev/null; then
  # Delay to ensure desktop is ready
  (sleep 5 && notify-send "Workspace Ready" "Welcome to the demo environment! 🚀" --icon=dialog-information) &
fi

# Create a fun ASCII art file
cat > "$HOME/.motd" << 'EOF'
=================================
== Welcome to CodingBooth Demo ==
=================================
EOF

# Append MOTD to bashrc if not already there
if ! grep -q ".motd" "$HOME/.bashrc" 2>/dev/null; then
  echo '[ -f ~/.motd ] && cat ~/.motd' >> "$HOME/.bashrc"
fi

# Set a custom background
mkdir -p "/home/coder/.config/xfce4/xfconf/xfce-perchannel-xml"
cat > "/home/coder/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorVNC-0" type="empty">
        <property name="workspace0" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/xfce/xfce-blue.jpg"/>
        </property>
        <property name="workspace1" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/xfce/xfce-blue.jpg"/>
        </property>
        <property name="workspace2" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/xfce/xfce-blue.jpg"/>
        </property>
        <property name="workspace3" type="empty">
          <property name="color-style" type="int" value="0"/>
          <property name="image-style" type="int" value="5"/>
          <property name="last-image" type="string" value="/usr/share/backgrounds/xfce/xfce-blue.jpg"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF

# Link Claude agent
ln -sf /opt/codingbooth/AGENT.md /home/coder/CLAUDE.md

if [[ "${CB_SILENCE_BUILD:-false}" != "true" ]]; then
  echo "✅ Demo startup complete!"
fi
