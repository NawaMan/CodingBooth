#!/bin/bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# -----------------------------------------------------------------------------
# cb-has-desktop-running.sh
#
# Returns 0 if a desktop environment is currently running, 1 otherwise.
# This checks for running processes, not just installed packages.
# Update this script as display technology evolves.
# -----------------------------------------------------------------------------

# XFCE window manager
pgrep -x "xfwm4" > /dev/null 2>&1 && exit 0

# KDE window manager (X11)
pgrep -x "kwin_x11" > /dev/null 2>&1 && exit 0

# KDE window manager (Wayland)
pgrep -x "kwin_wayland" > /dev/null 2>&1 && exit 0

# GNOME (future)
pgrep -x "gnome-shell" > /dev/null 2>&1 && exit 0

# Generic X session check (fallback)
pgrep -x "Xvnc" > /dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]] && exit 0

exit 1
