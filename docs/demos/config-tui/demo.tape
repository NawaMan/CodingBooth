# VHS demo: booth config TUI
# Install VHS: go install github.com/charmbracelet/vhs@latest
# Run:         vhs docs/demos/config-tui/demo.tape
#
# This produces a ~30s GIF showing:
#   1. Launch booth config TUI
#   2. Search and select Go
#   3. Search and select Python
#   4. Search and select claude-code
#   5. Switch to Config tab, change variant
#   6. Ctrl+S to save

Output docs/demos/config-tui/demo.gif

Set Shell "bash"
Set FontSize 14
Set Width 1200
Set Height 700
Set Framerate 30
Set Theme "Catppuccin Mocha"
Set TypingSpeed 50ms
Set Padding 10

# ── Launch ───────────────────────────────────────────────────────────

Type "booth config --templates-path ./templates"
Sleep 300ms
Enter
Sleep 1500ms

# ── Go to Languages tab ─────────────────────────────────────────────

Right
Sleep 800ms

# ── Search for "go" and select it ────────────────────────────────────

Tab
Sleep 300ms
Type "go"
Sleep 800ms

# Return to list and select Go (first match)
Tab
Sleep 300ms
Space
Sleep 800ms

# ── Search for "python" and select it ────────────────────────────────

Tab
Sleep 300ms
# Clear previous search
Backspace Backspace
Sleep 200ms
Type "python"
Sleep 800ms

# Return to list and select Python
Tab
Sleep 300ms
Space
Sleep 800ms

# ── Clear search, go to AI Tools tab ────────────────────────────────

Tab
Sleep 200ms
Escape
Sleep 400ms

# Navigate to AI Tools tab (from Languages, go right through Databases, Tools, IDEs, Desktops, Browsers, AI Tools = 6 rights)
Right Right Right Right Right Right
Sleep 800ms

# ── Select claude-code ───────────────────────────────────────────────

# AI Tools sorted: antigravity, claude-code — so claude-code is 2nd item
Down
Sleep 300ms
Space
Sleep 1000ms

# ── Switch to Config tab ─────────────────────────────────────────────

# Go left 7 times to get back to Config (tab 0)
Left Left Left Left Left Left Left
Sleep 800ms

# ── Change variant — cycle from base to codeserver ───────────────────
# Variant is the first config field, cursor starts there
# Space cycles: base -> notebook -> codeserver

Space
Sleep 400ms
Space
Sleep 1000ms

# ── Save ─────────────────────────────────────────────────────────────

Ctrl+S
Sleep 2500ms
