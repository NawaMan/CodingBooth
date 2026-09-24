#!/usr/bin/env bash
# Copyright 2025-2026 : Nawa Manusitthipol
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.

# default-terminal--setup.sh <alacritty|kitty> — makes an already-installed
# alternate terminal (see alacritty--setup.sh / kitty--setup.sh) the DE's
# default, so "Open Terminal Here" / the desktop's terminal keybinding /
# right-click menu launch it instead of the DE's stock terminal.
#
# Each desktop keeps this preference in a different place, and none of them
# is something a Boothfile setup can write at build time — they all live
# under the runtime user's $HOME, which does not exist yet (build-time HOME
# is /root). So this only writes the Wayland choice to a file at build
# time; the X11 desktops' registry files are written by a startup script,
# same pattern as the font seeding in alacritty--setup.sh / kitty--setup.sh.
#
#   XFCE   ~/.config/xfce4/helpers.rc        TerminalEmulator=<term>
#   KDE    ~/.config/kdeglobals              [General] TerminalApplication=<term>
#          ~/.config/kglobalshortcutsrc      Ctrl+Alt+T moved from Konsole to <term>
#   LXQt   ~/.config/pcmanfm-qt/lxqt/settings.conf   [System] Terminal=<term>
#          ~/.config/lxqt/globalkeyshortcuts.conf    Ctrl+Alt+T -> <term>
#   labwc  no registry — the terminal is hardcoded in wayland--setup.sh's
#          runtime-generated autostart/menu.xml. Made swappable there via
#          $DEFAULT_TERMINAL, read from /opt/codingbooth/default-terminal.
#
# Only one desktop is normally present in a given booth image, so the
# startup script detects which one via its session binary and only touches
# that DE's file — the other branches are no-ops.

set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO" >&2; exit 1' ERR

if [[ $EUID -ne 0 ]]; then
  echo "❌ This script must be run as root (use sudo)" >&2
  exit 1
fi

TERM_APP="${1:-}"
case "$TERM_APP" in
  alacritty|kitty) ;;
  *)
    echo "❌ default-terminal: unsupported terminal '${TERM_APP}' (expected alacritty or kitty)" >&2
    exit 1
    ;;
esac

echo "🔧 Making ${TERM_APP} the default terminal…"

# ---- Wayland (labwc): a file start-wayland reads directly. Not a profile.d
# export — the desktop is launched by booth-entry's `runuser -u coder -- …`,
# which is not a login shell and never sources /etc/profile.d. Harmless on the
# other desktops, which don't read it.
DEFAULT_TERMINAL_FILE="/opt/codingbooth/default-terminal"
install -d "$(dirname "$DEFAULT_TERMINAL_FILE")"
printf '%s\n' "$TERM_APP" > "$DEFAULT_TERMINAL_FILE"
chmod 0644 "$DEFAULT_TERMINAL_FILE"

# ---- Debian's system-wide "default terminal" (x-terminal-emulator), used by
# anything that asks for a terminal generically. Both packages register as an
# alternative, but auto mode can prefer another by priority (foot on labwc,
# xfce4-terminal on XFCE), so pin it.
TERM_BIN="$(command -v "$TERM_APP")"
if ! update-alternatives --list x-terminal-emulator 2>/dev/null | grep -qx "$TERM_BIN"; then
  update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator "$TERM_BIN" 50
fi
update-alternatives --set x-terminal-emulator "$TERM_BIN"

# ---- X11 desktops: per-user registry files, written once at container
# start (build-time HOME is /root, not the runtime user's home).
STARTUP_FILE="/usr/share/startup.d/58-cb-default-terminal--startup.sh"
install -d "$(dirname "$STARTUP_FILE")"
{
  printf '#!/usr/bin/env bash\nset -uo pipefail\n\nTERM_APP=%q\n' "$TERM_APP"
  cat <<'STARTUP'

# XFCE — exo's per-user override of /etc/xdg/xfce4/helpers.rc. The catalog
# id ("alacritty"/"kitty") already exists system-wide as an XFCE helper
# (xfce4-helpers ships stubs for both regardless of whether the binary is
# installed), so no helper .desktop needs to be authored here.
if command -v xfce4-session >/dev/null 2>&1; then
  HELPERS_RC="$HOME/.config/xfce4/helpers.rc"
  if ! grep -q '^TerminalEmulator=' "$HELPERS_RC" 2>/dev/null; then
    mkdir -p "$(dirname "$HELPERS_RC")"
    printf 'TerminalEmulator=%s\n' "$TERM_APP" >> "$HELPERS_RC"
    echo "✅ cb-default-terminal: set XFCE TerminalEmulator=$TERM_APP in $HELPERS_RC"
  fi
fi

# KDE — kdeglobals' General/TerminalApplication, read by Dolphin's "Open
# Terminal Here" and the desktop's own "Open Terminal" action.
if command -v startplasma-x11 >/dev/null 2>&1; then
  KDEGLOBALS="$HOME/.config/kdeglobals"
  if ! grep -q '^TerminalApplication=' "$KDEGLOBALS" 2>/dev/null; then
    KWRITECONFIG=kwriteconfig5
    command -v kwriteconfig6 >/dev/null 2>&1 && KWRITECONFIG=kwriteconfig6
    "$KWRITECONFIG" --file kdeglobals --group General --key TerminalApplication "$TERM_APP" || true
    echo "✅ cb-default-terminal: set KDE TerminalApplication=$TERM_APP in $KDEGLOBALS"
  fi

  # Ctrl+Alt+T is Konsole's own global shortcut (X-KDE-Shortcuts in its
  # .desktop), which ignores TerminalApplication — so move it: Konsole's
  # launch key to none, the terminal's .desktop to Ctrl+Alt+T. Skipped if the
  # terminal already has a shortcut group, or Konsole was rebound by hand.
  SHORTCUTS="$HOME/.config/kglobalshortcutsrc"
  TERM_DESKTOP="$(ls /usr/share/applications 2>/dev/null | grep -ix "${TERM_APP}.desktop" | head -1)"
  if [[ -n "$TERM_DESKTOP" ]] && ! grep -qF "[$TERM_DESKTOP]" "$SHORTCUTS" 2>/dev/null; then
    KREADCONFIG=kreadconfig5
    command -v kreadconfig6 >/dev/null 2>&1 && KREADCONFIG=kreadconfig6
    KONSOLE_LAUNCH="$("$KREADCONFIG" --file kglobalshortcutsrc --group org.kde.konsole.desktop --key _launch 2>/dev/null)"
    if [[ -z "$KONSOLE_LAUNCH" || "$KONSOLE_LAUNCH" == Ctrl+Alt+T,* ]]; then
      TERM_NAME="$(sed -n 's/^Name=//p' "/usr/share/applications/$TERM_DESKTOP" | head -1)"
      "$KWRITECONFIG" --file kglobalshortcutsrc --group org.kde.konsole.desktop --key _k_friendly_name "Konsole" || true
      "$KWRITECONFIG" --file kglobalshortcutsrc --group org.kde.konsole.desktop --key _launch "none,Ctrl+Alt+T,Konsole" || true
      "$KWRITECONFIG" --file kglobalshortcutsrc --group "$TERM_DESKTOP" --key _k_friendly_name "${TERM_NAME:-$TERM_APP}" || true
      "$KWRITECONFIG" --file kglobalshortcutsrc --group "$TERM_DESKTOP" --key _launch "Ctrl+Alt+T,none,${TERM_NAME:-$TERM_APP}" || true
      echo "✅ cb-default-terminal: moved KDE Ctrl+Alt+T from Konsole to $TERM_DESKTOP"
    fi
  fi
fi

if command -v lxqt-session >/dev/null 2>&1; then
  # PCManFM-Qt (desktop right-click + file manager): [System] Terminal= in
  # its lxqt profile. It reads the user file OR /etc/xdg's copy, never a
  # merge, so seed from the system copy or its wallpaper settings are lost.
  # It also writes its compiled-in fallback (Terminal=xterm, which is not
  # even installed) back on exit, so that value counts as unset, not as a
  # user choice.
  PCM_CONF="$HOME/.config/pcmanfm-qt/lxqt/settings.conf"
  if [[ ! -f "$PCM_CONF" ]]; then
    mkdir -p "$(dirname "$PCM_CONF")"
    if [[ -f /etc/xdg/pcmanfm-qt/lxqt/settings.conf ]]; then
      cp /etc/xdg/pcmanfm-qt/lxqt/settings.conf "$PCM_CONF"
    else
      : > "$PCM_CONF"
    fi
  fi
  if grep -q '^Terminal=xterm$' "$PCM_CONF"; then
    sed -i "s/^Terminal=xterm\$/Terminal=${TERM_APP}/" "$PCM_CONF"
    echo "✅ cb-default-terminal: set PCManFM-Qt Terminal=$TERM_APP in $PCM_CONF"
  elif ! grep -q '^Terminal=' "$PCM_CONF"; then
    if grep -q '^\[System\]' "$PCM_CONF"; then
      sed -i "/^\[System\]/a Terminal=${TERM_APP}" "$PCM_CONF"
    else
      printf '\n[System]\nTerminal=%s\n' "$TERM_APP" >> "$PCM_CONF"
    fi
    echo "✅ cb-default-terminal: set PCManFM-Qt Terminal=$TERM_APP in $PCM_CONF"
  fi

  # Ctrl+Alt+T (lxqt-globalkeysd). Ubuntu ships the system defaults one
  # directory too deep (/etc/xdg/lxqt/globalkeyshortcuts.conf/<same name>),
  # so the daemon never loads them and the shortcut is otherwise unbound.
  # Left alone if the user already bound Ctrl+Alt+T to anything.
  KEYS_CONF="$HOME/.config/lxqt/globalkeyshortcuts.conf"
  if ! grep -q '^\[Control%2BAlt%2BT\.' "$KEYS_CONF" 2>/dev/null; then
    mkdir -p "$(dirname "$KEYS_CONF")"
    printf '\n[Control%%2BAlt%%2BT.100]\nComment=Terminal (%s)\nEnabled=true\nExec=%s\n' \
      "$TERM_APP" "$TERM_APP" >> "$KEYS_CONF"
    echo "✅ cb-default-terminal: bound LXQt Ctrl+Alt+T to $TERM_APP in $KEYS_CONF"
  fi
fi

exit 0
STARTUP
} > "$STARTUP_FILE"
chmod 0755 "$STARTUP_FILE"

cat <<EON
ℹ️ Default terminal set to ${TERM_APP}:
- XFCE / KDE / LXQt: written to the DE's own "default terminal" setting on
  first container start (~/.config/xfce4/helpers.rc, ~/.config/kdeglobals,
  PCManFM-Qt's settings.conf on LXQt), and Ctrl+Alt+T opens it on all three
  — never overwrites a value you set by hand afterwards.
- x-terminal-emulator (Debian's generic "default terminal") points at it.
- labwc (Wayland): /opt/codingbooth/default-terminal, read by the desktop's
  autostart, right-click "Terminal" menu item, and Super+Enter.
- The DE's own stock terminal (xfce4-terminal/Konsole/qterminal/foot) stays
  installed and reachable — this only changes what "open a terminal" runs.
EON
