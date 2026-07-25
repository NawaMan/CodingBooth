# Firebase Example

This example is a booth preconfigured for Firebase development with the Firebase CLI. Your host Firebase CLI credentials (`~/.config/configstore/firebase-tools.json`) are mounted read-only and seeded into the container, so `firebase login:list` and `firebase projects:list` work right away. The credentials are seeded read-only from the host rather than committed, so `firebase deploy`, `projects:list`, and the rest are authenticated the instant the booth starts — no re-login, no token pasted into the project. Your Firebase login lives on the host and the booth simply borrows a copy, keeping it out of git and out of any image you build or share. Onboarding a teammate to the project becomes "open the booth" instead of walking them through `firebase login` and hoping they don't commit the token.

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

The `.booth/config.toml` mounts Firebase-related config directories read-only to `/etc/cb-home-seed/`.
At container startup, these are copied to `/home/coder/.config/`.

This means:
- Your host credentials stay protected (read-only mount)
- The container gets a writable copy
- Firebase CLI works out of the box

## Try It

### From Host

```bash
../../../codingbooth -- ./test-connection.sh
```

### From Container

```bash
../../codingbooth
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
