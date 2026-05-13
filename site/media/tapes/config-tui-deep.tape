# Deep walkthrough — modal edits inside the config TUI:
#   1. cycle the Variant field on the Config tab
#   2. open a template's parameter editor (Enter, not Space)
# Generous Sleeps are intentional so keypress-overlay text can be added later.
# Render: vhs config-tui-deep.tape

Output config-tui-deep.gif
Output config-tui-deep.mp4

Set FontSize 16
Set Width 1280
Set Height 720
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set PlaybackSpeed 1.0

# --- silent setup: put the in-repo `booth` on PATH and start from /tmp ---
Hide
Type "export PATH=$PWD/.sandbox:$PATH"
Enter
Type "cd /tmp && rm -rf my-bun-app"
Enter
Type "clear"
Enter
Show

# --- 0. create and enter a fresh project dir ---
Type "mkdir my-bun-app"
Sleep 600ms
Enter
Sleep 2.4s
Type "cd my-bun-app"
Sleep 600ms
Enter
Sleep 3.6s

# --- 1. launch (opens on Languages tab) ---
Type "booth config"
Sleep 800ms
Enter
Sleep 6s

# --- 2. hop to the Config tab ---
Left
Sleep 4.4s

# --- 3. variant cycle: navigate, enter cycle-edit, swap, commit ---
# Cursor starts at the "Booth" group header (auto-skipped on Down);
# Down 1 → Booth Version, Down 2 → Variant.
Down 2
Sleep 4s
Enter                    # enter cycle-edit on Variant
Sleep 4.4s
Right                    # next variant value
Sleep 4s
Right                    # one more
Sleep 4s
Right                    # one more so the change is unmistakable
Sleep 4.4s
Enter                    # commit
Sleep 5s

# --- 4. back to Languages, select a template, then open its parameter editor ---
Right
Sleep 4s
# Cursor is on bun by default (alphabetical, position 0).
Space                    # SELECT bun — required before Enter will open param edit
Sleep 4s
Enter                    # open the right-pane param editor
Sleep 5s

# --- 5. tour the param fields, then back out ---
Down                     # next param (BUN_PKGS)
Sleep 4s
Up                       # back to the first param
Sleep 4s
Escape                   # leave param edit (selection is preserved)
Sleep 4s

# --- 6. save & exit ---
Ctrl+S
Sleep 4s

# --- 7. show the result ---
Type "cat .booth/Boothfile 2>/dev/null | head -20"
Enter
Sleep 7s
