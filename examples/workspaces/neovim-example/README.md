# Neovim Example

This example demonstrates using `.booth/home/` to share team-wide neovim configuration.

## What's Included

- `.booth/home/.config/nvim/init.lua` - Basic neovim configuration
- `.booth/home/.config/nvim/lua/` - Lua modules for neovim

## How It Works

The `.booth/home/` folder is copied to `/home/coder/` at container startup.
This means everyone on the team gets the same neovim setup automatically.

## Try It

```bash
../../coding-booth
# Then in the container:
nvim
```

## Customizing

- Add your team's neovim plugins to `.booth/home/.config/nvim/`
- Personal overrides can be added via `cb-home-seed` in `.booth/config.toml`
