# Walkthrough — config TUI: pick a language with an extension, a database via
# search, save, show the generated .booth/.
# The TUI opens on the Languages tab (index 1), not Config.
# Render: vhs config-tui.tape

Output config-tui.gif
Output config-tui.mp4

Set FontSize 16
Set Width 1280
Set Height 720
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set PlaybackSpeed 1.0

# --- silent setup ---
Hide
Type "export PATH=$PWD/.sandbox:$PATH"
Enter
Type "cd /tmp && rm -rf cb-demo-full && mkdir cb-demo-full && cd cb-demo-full"
Enter
Type "clear"
Enter
Show

# --- 1. launch (opens on Languages tab) ---
Type "booth config"
Sleep 400ms
Enter
Sleep 2.5s

# --- 2. pick Go with linter extension on the Languages tab ---
Down 2
Sleep 500ms
Space            # select template
Sleep 800ms
Down
Sleep 400ms
Space            # toggle extension under it
Sleep 1.4s

# --- 3. hop to Databases and search "post" ---
Right
Sleep 800ms
Tab
Sleep 400ms
Type "post"
Sleep 1s
Down
Sleep 400ms
Space
Sleep 1.6s

# --- 4. go back to Config tab to glance at variant + project fields ---
Left 2
Sleep 1.6s

# --- 5. save & exit ---
Ctrl+S
Sleep 1.5s

# --- 6. inspect the generated workspace ---
Type "ls -la .booth/"
Enter
Sleep 2.2s
Type "cat .booth/Boothfile 2>/dev/null | head -20"
Enter
Sleep 3s
