# Google Cloud Example

This example demonstrates using `ws-home-seed` to mount Google Cloud credentials from your host machine into the container.

## Prerequisites

You need Google Cloud CLI credentials configured on your host:
```bash
~/.config/gcloud/
```

If you don't have these, set them up with:
```bash
gcloud auth login
gcloud auth application-default login
```

## How It Works

The `.ws/config.toml` mounts `~/.config/gcloud/` read-only to `/tmp/ws-home-seed/.config/gcloud/`.
At container startup, this is copied to `/home/coder/.config/gcloud/`.

This means:
- Your host credentials stay protected (read-only mount)
- The container gets a writable copy
- gcloud CLI and SDKs work out of the box

## Try It

```bash
../../workspace
# Then in the container:
gcloud auth list
gcloud config list
```

## What's Mounted

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `~/.config/gcloud/` | `/home/coder/.config/gcloud/` | Copied at startup |

## Security Notes

- Credentials are NOT stored in version control
- The mount uses `:ro` (read-only) to protect your host files
- Changes inside the container don't affect your host credentials
