# Firebase Example

This example demonstrates using `cb-home-seed` to mount Firebase credentials from your host machine into the container.

## Prerequisites

You need Firebase CLI credentials configured on your host:
```bash
~/.config/configstore/firebase-tools.json
```

If you don't have these, set them up with:
```bash
firebase login
```

## How It Works

The `.ws/config.toml` mounts Firebase-related config directories read-only to `/etc/cb-home-seed/`.
At container startup, these are copied to `/home/coder/.config/`.

This means:
- Your host credentials stay protected (read-only mount)
- The container gets a writable copy
- Firebase CLI works out of the box

## Try It

### From Host

```bash
../../../coding-booth -- ./test-connection.sh
```

### From Container

```bash
../../coding-booth
# Then in the container:
firebase login:list
firebase projects:list
```

## What's Mounted

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `~/.config/gcloud/` | `/home/coder/.config/gcloud/` | For GCP integration |
| `~/.config/configstore/` | `/home/coder/.config/configstore/` | Firebase CLI state |

## Security Notes

- Credentials are NOT stored in version control
- The mount uses `:ro` (read-only) to protect your host files
- Changes inside the container don't affect your host credentials
