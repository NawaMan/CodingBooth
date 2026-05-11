# Full walkthrough (~55s) — config TUI: variant cycle, language + extension,
# database via search, save, show generated .booth/.
# Render: vhs config-tui-full.tape

Output config-tui-full.gif
Output config-tui-full.mp4

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

# --- 1. launch ---
Type "booth config"
Sleep 400ms
Enter
Sleep 3s

# --- 2. cycle the variant on the Config tab ---
# Navigate down to the Variant row (exact step count may need tuning).
Down 2
Sleep 600ms
Enter            # enter cycle-edit on Variant
Sleep 600ms
Right            # next variant
Sleep 700ms
Right            # codeserver
Sleep 700ms
Enter            # commit
Sleep 1.2s

# --- 3. Languages tab — pick a Go template + extension ---
Right
Sleep 900ms
Down 2
Sleep 500ms
Enter            # expand / select go
Sleep 1.2s
Down
Sleep 500ms
Space            # toggle an extension under go
Sleep 1.2s

# --- 4. Databases tab — search for postgres ---
Right
Sleep 600ms
Tab
Sleep 400ms
Type "post"
Sleep 1.2s
Down
Sleep 500ms
Space
Sleep 1.4s

# --- 5. back to Config to see the summary ---
Escape
Sleep 200ms
Left 2
Sleep 1.5s

# --- 6. save & exit ---
Ctrl+S
Sleep 1.5s

# --- 7. inspect the generated workspace ---
Type "ls -la .booth/"
Enter
Sleep 2.5s
Type "cat .booth/Boothfile 2>/dev/null | head -20"
Enter
Sleep 3s
