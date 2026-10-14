# Base Variant

The foundation variant containing core CodingBooth functionality and setup scripts.

**Includes:**
- Ubuntu-based container -- a human-friendly made for development
- Default variant
- Web terminal via split-pane `ttyd` UI by default
- Optional classic single-session mode with `-e BOOTH_WEB_SPLIT=false`
- i3-style tiling shortcuts (Ctrl+Alt, Control+Option on a Mac) in the split UI — the toolbar keeps four layout buttons, the keys reach every other arrangement — see [BOOTH_CONSOLE.md](../../docs/BOOTH_CONSOLE.md#keyboard-shortcuts-tiling)
- Markdown view — pane document icon, or `Ctrl+Alt+m`, starts `viewmd --daemon` if needed and opens `http://booth:8765`
- Manage user ownership and permission for the workspace (project directory) on host and /home/coder/code on the container.
- 70+ setup scripts in `setups/` directory
- Common development tools and utilities
- `viewmd` -- browse the project's Markdown files in a browser (`viewmd --md README.md --expose`)
- `just` -- run project recipes from a Justfile (`just --list`, `just <recipe>`)
- `lazygit` -- terminal UI for git (`lazygit` inside a repository)
- `spf` (superfile) -- modern terminal file manager (`spf`, `spf <dir>`); `explorer` stays `mc`
- `differ` -- review what a coding agent changed and send it line comments (`differ review`)
- `folio` (EnvFolio) -- keep texts and secrets, load them as env vars (`folio init`, `folio exec --secrets <entry> -- <cmd>`)

**Usage:**
```bash
booth --variant base

# Classic single terminal mode (disable split UI)
booth --variant base -e BOOTH_WEB_SPLIT=false

# Optional URL mode switch (examples) — all still accepted; the ones
# without a toolbar button open and show as Other
# http://localhost:10000/#mode=single
# http://localhost:10000/#mode=hsplit
# http://localhost:10000/#mode=vsplit
# http://localhost:10000/#mode=quad
# http://localhost:10000/#mode=left-main
# http://localhost:10000/#mode=right-main
# http://localhost:10000/#mode=top-main
# http://localhost:10000/#mode=bottom-main
# http://localhost:10000/#mode=grid6        (3 columns x 2 rows)
# http://localhost:10000/#mode=h(1,v(2,3,4))   (any tiling layout)
```

**Purpose:** Serves as the base image for all other variants. Use directly for minimal, customizable environments or as a starting point for custom variants.
