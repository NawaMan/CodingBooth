# Azure Example

This example demonstrates using `ws-home-seed` to mount Azure CLI credentials from your host machine into the container.

## Prerequisites

You need Azure CLI credentials configured on your host:
```bash
~/.azure/
```

If you don't have these, set them up with:
```bash
az login
```

## How It Works

The `.ws/config.toml` mounts `~/.azure/` read-only to `/tmp/ws-home-seed/.azure/`.
At container startup, this is copied to `/home/coder/.azure/`.

This means:
- Your host credentials stay protected (read-only mount)
- The container gets a writable copy
- Azure CLI and SDKs work out of the box

## Try It

```bash
../../workspace
# Then in the container:
az account show
az account list
```

## What's Mounted

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `~/.azure/` | `/home/coder/.azure/` | Copied at startup |

## Security Notes

- Credentials are NOT stored in version control
- The mount uses `:ro` (read-only) to protect your host files
- Changes inside the container don't affect your host credentials
