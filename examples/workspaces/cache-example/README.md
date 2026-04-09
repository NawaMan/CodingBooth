# Cache Example

This example demonstrates how to persist files and directories across container restarts using `.booth/cache/`.

## Setup

This project was created with:

```bash
booth config . --no-tui --select shell-history \
    --set cache-files=home/coder/.my_app_history \
    --set cache-dirs=home/coder/.my_app_data
```

## Try It

```bash
# Start the booth
../../booth

# Inside the container — write some data:
echo "hello from session 1" >> ~/.my_app_history
echo "important notes" > ~/.my_app_data/notes.txt
history  # shell history is also being saved

# Exit and restart:
exit
../../booth

# Your data is still here:
cat ~/.my_app_history           # → "hello from session 1"
cat ~/.my_app_data/notes.txt    # → "important notes"
history                         # → previous commands still there
```

## What's Persisted

| Path | Source | Mount Type |
|------|--------|------------|
| `~/.bash_history` | `shell-history` template | file |
| `~/.zsh_history` | `shell-history` template | file |
| `~/.my_app_history` | `cache-files` in config.toml | file |
| `~/.my_app_data/` | `cache-dirs` in config.toml | directory |

## How It Works

- `cache-files` creates individual file bind mounts
- `cache-dirs` creates directory bind mounts (via `.mount-this` marker)
- `.booth/cache/` is gitignored — data stays on this machine only
- Cache files are created automatically at booth startup from `config.toml`
- Deleting `.booth/cache/` is safe — it will be recreated on next start

See [BOOTH_LOCALCACHE.md](../../../docs/BOOTH_LOCALCACHE.md) for the full guide.
