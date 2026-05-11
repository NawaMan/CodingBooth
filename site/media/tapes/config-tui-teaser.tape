# Teaser (~25s) — show booth config TUI: tour tabs, search a database, save.
# Render: vhs config-tui-teaser.tape  (outputs land in this directory)

Output config-tui-teaser.gif
Output config-tui-teaser.mp4

Set FontSize 16
Set Width 1280
Set Height 720
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set PlaybackSpeed 1.0

# --- silent setup: put sandbox booth on PATH, empty temp dir ---
Hide
Type "export PATH=$PWD/.sandbox:$PATH"
Enter
Type "cd /tmp && rm -rf cb-demo && mkdir cb-demo && cd cb-demo"
Enter
Type "clear"
Enter
Show

# --- 1. fresh dir, one command ---
Type "booth config"
Sleep 400ms
Enter
Sleep 2.5s

# --- 2. tour the category tabs (Right cycles tabs) — land on Databases ---
Right
Sleep 1s
Right
Sleep 1.2s

# --- 3. search for postgres (on Databases tab) ---
Tab
Sleep 400ms
Type "post"
Sleep 1.2s
Down
Sleep 500ms
Space
Sleep 1.8s

# --- 4. save & exit ---
Ctrl+S
Sleep 1.5s

# --- 5. show the artifact ---
Type "ls -la .booth/"
Enter
Sleep 2.8s
