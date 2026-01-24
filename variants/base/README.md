# Base Variant

The foundation variant containing core CodingBooth functionality and setup scripts.

**Includes:**
- Ubuntu-based container -- a human-friendly made for development
- Default variant
- Manage user ownership and permission for the workspace (project directory) on host and /home/coder/code on the container.
- 70+ setup scripts in `setups/` directory
- Common development tools and utilities

**Usage:**
```bash
booth --variant base
```

**Purpose:** Serves as the base image for all other variants. Use directly for minimal, customizable environments or as a starting point for custom variants.
