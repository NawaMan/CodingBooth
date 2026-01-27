#!/bin/bash
# Returns 0 if desktop environment is available, 1 otherwise.
# Update this script as display technology evolves.

# X11/VNC-based desktop
command -v Xvnc &>/dev/null && exit 0
command -v tigervncserver &>/dev/null && exit 0

# XFCE
command -v startxfce4 &>/dev/null && exit 0
command -v xfce4-session &>/dev/null && exit 0

# KDE
command -v startplasma-x11 &>/dev/null && exit 0
command -v plasmashell &>/dev/null && exit 0

# Wayland-based desktop (future)
command -v cage &>/dev/null && exit 0
command -v gamescope &>/dev/null && exit 0

exit 1
