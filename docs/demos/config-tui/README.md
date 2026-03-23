# booth config TUI Demo

30-second GIF demo of the `booth config` interactive TUI.

## What it shows

1. Launch `booth config` TUI
2. Search and select **Go** (with auto-selected linter extension)
3. Search and select **Python**
4. Navigate to AI Tools, select **claude-code**
5. Switch to Config tab, change variant to **codeserver**
6. Save with Ctrl+S — generates `.booth/` files

## Record the GIF

```bash
# From project root
vhs docs/demos/config-tui/demo.tape
```

Output: `docs/demos/config-tui/demo.gif`

## Adjust

- Edit `demo.tape` to change selections, timing, or resolution
- Add `Sleep` to slow down, reduce to speed up
- See [VHS docs](https://github.com/charmbracelet/vhs) for all commands
