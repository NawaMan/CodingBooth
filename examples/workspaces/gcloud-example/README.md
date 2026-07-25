# Google Cloud Example

This example is a booth preconfigured for Google Cloud development with the gcloud CLI. Your host `~/.config/gcloud` is mounted into the container so `gcloud auth list` and `gcloud config list` work as soon as the booth starts. Seeding the host gcloud credentials means the CLI and SDKs are authenticated the moment the booth opens — no `gcloud auth login` dance inside the container, no service-account JSON checked into the repo. Your logins stay on the host where they belong and the booth just borrows them, so onboarding to a GCP project is "launch the booth" rather than a page of setup steps. Nothing secret ends up in git or in an image you might later share.

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

The `.booth/config.toml` mounts `~/.config/gcloud/` read-only to `/etc/cb-home-seed/.config/gcloud/`.
At container startup, this is copied to `/home/coder/.config/gcloud/`.

This means:
- Your host credentials stay protected (read-only mount)
- The container gets a writable copy
- gcloud CLI and SDKs work out of the box

## Try It

```bash
../../codingbooth
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
