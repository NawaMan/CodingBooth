# AWS Example

This example demonstrates using `ws-home-seed` to mount AWS credentials from your host machine into the container.

## Prerequisites

You need AWS credentials configured on your host:
```bash
~/.aws/credentials
~/.aws/config
```

If you don't have these, set them up with:
```bash
aws configure
```

## How It Works

The `ws--config.toml` mounts `~/.aws/` read-only to `/tmp/ws-home-seed/.aws/`.
At container startup, this is copied to `/home/coder/.aws/`.

This means:
- Your host credentials stay protected (read-only mount)
- The container gets a writable copy
- AWS CLI and SDKs work out of the box

## Try It

```bash
../../workspace
# Then in the container:
aws sts get-caller-identity
```

## What's Mounted

| Host Path | Container Path | Notes |
|-----------|----------------|-------|
| `~/.aws/` | `/home/coder/.aws/` | Copied at startup |

## Security Notes

- Credentials are NOT stored in version control
- The mount uses `:ro` (read-only) to protect your host files
- Changes inside the container don't affect your host credentials
