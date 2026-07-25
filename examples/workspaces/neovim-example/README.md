# Neovim Example

This example demonstrates using `.booth/home/` to share a team-wide neovim configuration. It ships an `init.lua` and Lua modules under `.booth/home/.config/nvim/` that are copied into `/home/coder/` at container startup, so `nvim` launches with the same setup for everyone. Team config sharing: the `.booth/home` neovim config travels with the repo, so every teammate gets an identical editor setup automatically. No dotfile repos to clone, no "install these plugins first" onboarding steps, no drift between one developer's Neovim and the next — the config is version-controlled right alongside the code it edits. Update `init.lua`, commit, and the whole team's editor updates on their next booth start, while personal overrides remain possible via `cb-home-seed`.

## What's Included

- `.booth/home/.config/nvim/init.lua` - Basic neovim configuration
- `.booth/home/.config/nvim/lua/` - Lua modules for neovim

## How It Works

The `.booth/home/` folder is copied to `/home/coder/` at container startup.
This means everyone on the team gets the same neovim setup automatically.

## Try It

```bash
../../codingbooth
# Then in the container:
nvim
```

## Customizing

- Add your team's neovim plugins to `.booth/home/.config/nvim/`
- Personal overrides can be added via `cb-home-seed` in `.booth/config.toml`
