# Base Variant

The foundation variant containing core CodingBooth functionality and setup scripts.

**Includes:**
- Ubuntu-based container -- a human-friendly made for development
- Default variant
- Web terminal via split-pane `ttyd` UI by default
- Optional classic single-session mode with `web-split = false` or `CB_WEB_SPLIT=false`
- Manage user ownership and permission for the workspace (project directory) on host and /home/coder/code on the container.
- 70+ setup scripts in `setups/` directory
- Common development tools and utilities
- `viewmd` -- browse the project's Markdown files in a browser (`viewmd --md README.md --expose`)

**Usage:**
```bash
booth --variant base

# Classic single terminal mode (disable split UI)
CB_WEB_SPLIT=false booth --variant base

# Optional URL mode switch (examples)
# http://localhost:10000/#mode=single
# http://localhost:10000/#mode=hsplit
# http://localhost:10000/#mode=vsplit
# http://localhost:10000/#mode=quad
# http://localhost:10000/#mode=left-main
# http://localhost:10000/#mode=top-main
```

**Purpose:** Serves as the base image for all other variants. Use directly for minimal, customizable environments or as a starting point for custom variants.
