# Apt Example

Demonstrates installing **Debian/Ubuntu system packages** with `install apt`, frozen to
an Ubuntu archive snapshot for reproducible rebuilds.

**Stack:** base workspace + apt-installed CLI tools

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/apt-example
booth

# 2. Inside the booth — try the preinstalled tools
jq --version
tree --version
rg --version          # the apt package is `ripgrep`; the binary is `rg`
printenv APT_SNAPSHOT  # the snapshot the archive was frozen to
```

## What's included

| Component | Details                                              |
|-----------|------------------------------------------------------|
| Runtime   | base                                                 |
| Packages  | `jq`, `tree`, `ripgrep`                              |
| Pinning   | `APT_SNAPSHOT=20250601T000000Z` (whole-archive freeze) |

## How it works

The `.booth/Boothfile` is just:

```
env APT_SNAPSHOT=20250601T000000Z

install apt jq tree ripgrep
```

- **`install apt <pkgs>`** installs system packages, the same way `install pip` /
  `install npm` install language packages. Pin a version with apt's native syntax:
  `install apt jq=1.7.1-3build1`.
- **`APT_SNAPSHOT`** freezes the *entire* apt archive to a point in time using
  [Ubuntu's snapshot service](https://documentation.ubuntu.com/server/how-to/software/snapshot-service/),
  so every rebuild resolves the same versions — including transitive dependencies you
  never named. The id is a UTC timestamp, `YYYYMMDDTHHMMSSZ` (anything from 2023-03-01).
  When `booth config` generates a booth it stamps this line with the configuration date
  automatically; here it is pinned to a fixed snapshot for a deterministic demo.
- **Remove the `env APT_SNAPSHOT=...` line** to track the live archive instead (no
  `--snapshot`); apt then resolves whatever is current at build time.

Why pin the snapshot rather than just the package version? The live apt archive keeps
only the *current* version of most packages, so a bare `jq=1.7.1-3build1` pin stops
resolving once a newer build lands. Freezing the snapshot keeps the whole resolution
installable. See [REPRODUCIBILITY.md](../../../docs/REPRODUCIBILITY.md#apt--pin-the-snapshot-not-the-package).

Edit the `install apt ...` line in `.booth/Boothfile` to customise the package set.
