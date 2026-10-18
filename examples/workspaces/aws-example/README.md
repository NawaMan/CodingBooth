# AWS Cloud Development Example

This example is an isolated booth for developing against AWS with the AWS CLI. Your host `~/.aws/config`, `~/.aws/credentials` and SSO token cache are mounted read-only and copied into the booth's home at startup (the `cb-home-seed` pattern), so commands like `aws sts get-caller-identity` work as soon as the booth starts — provided your host credentials are valid. An included Jupyter notebook walks through common operations. Your keys never enter the project tree, git history, a Dockerfile or the image, and the booth cannot modify your host `~/.aws`. Anything running in the booth can still *read* the copy and act with your full permissions, so give an agent a narrowly scoped profile or role rather than your admin keys.

## Table of Contents

- [Why Run AWS Development in CodingBooth?](#why-run-aws-development-in-codingbooth)
- [Quick Start](#quick-start)
- [Credentials Separation Pattern](#credentials-separation-pattern)
- [Interactive Runnable Documentation](#interactive-runnable-documentation)
- [Configuration](#configuration)
- [Security Notes](#security-notes)


## Why Run AWS Development in CodingBooth?

| Benefit                  | Description                                                                                                                                       |
|--------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|
| **Host files protected** | Your AWS files are mounted read-only. The booth works on a copy, so nothing in it can change or delete your host `~/.aws`.                        |
| **No keys in the repo**  | Credentials come from each developer's own host at startup — never from the project, a Dockerfile, an env file or the image.                      |
| **Consistent tooling**   | Everyone gets the same Python and the same setup. Pin `AWS_CLI_VERSION` (see [Configuration](#configuration)) to get the same AWS CLI too.        |
| **Project Isolation**    | A profile/region config can live with the project (see below) without touching your host.                                                       |
| **Team Onboarding**      | A new team member with AWS credentials on their host runs `booth` and has a working AWS CLI. No install steps to follow.                         |
| **Clean Teardown**       | By default the container — and its credential copy — is removed when the booth stops. Nothing is left on your host.                              |

## Quick Start

**Prerequisites:** AWS credentials configured on your host (`~/.aws/credentials` and/or `~/.aws/config`, or an SSO login)

```bash
# Start the workspace
cd examples/workspaces/aws-example
booth

# Inside the workspace, AWS CLI is ready:
aws sts get-caller-identity

# Or open the Jupyter notebook for an interactive guide
```

If you use AWS SSO and your session has expired, run `aws sso login` inside the booth. That refreshes the booth's copy of the token cache, not your host's.

**Interactive Guide (Jupyter Notebook):**
- [`AWS-NoteBook.ipynb`](AWS-NoteBook.ipynb) - Step-by-step AWS operations with runnable cells

## Credentials Separation Pattern

CodingBooth can keep **secrets** (on your host) apart from **configuration** (committed with the project). This example ships only the first half; the second is a pattern you can add:

| What                    | Where                      | Committed?             |
|-------------------------|----------------------------|------------------------|
| Credentials (secrets)   | Host `~/.aws/credentials`  | No - user keeps safe   |
| Config (profile/region) | `.booth/home/.aws/config`  | Yes - shared with team |

To add a project config, commit a file like this:

```ini
# .booth/home/.aws/config - project-specific profile (committed to repo)
[default]
region = ap-southeast-1

[profile my-project-prod]
region = us-east-1
role_arn = arn:aws:iam::123456789:role/ProjectRole
source_profile = default
```

It **replaces** your host `~/.aws/config` in the booth rather than merging with it: files in `.booth/home/` are copied in first, and the host seed never overwrites a file that is already there. Any host profile the project file does not define — SSO profiles included — is not available in the booth. The credentials file is unaffected, so each team member needs host credentials under the profile names the project config refers to (`default` in the example above). See [docs/BOOTH_HOME.md](../../../docs/BOOTH_HOME.md#precedence-order) for the precedence order.

## Interactive Runnable Documentation

This example includes a Jupyter Notebook (bash kernel) for **documentation that actually runs**:

- [`AWS-NoteBook.ipynb`](AWS-NoteBook.ipynb) - Interactive AWS operations guide

Benefits:
- Step-by-step guides with explanations and executable code cells
- New team members follow along and run each step
- No copy-paste errors - just click "Run"
- Documentation stays in sync because it's tested by running it

## Configuration

`.booth/config.toml` (AWS lines; the file also seeds pip and Claude Code settings):
```toml
variant = "notebook"

run-args = [
    "-v", "~/.aws/config:/etc/cb-home-seed/.aws/config:ro",
    "-v", "~/.aws/credentials:/etc/cb-home-seed/.aws/credentials:ro",
    "-v", "~/.aws/sso/cache:/etc/cb-home-seed/.aws/sso/cache:ro",
]
```

Only these three are seeded; anything else in your host `~/.aws` (CLI aliases under `cli/`, for example) is not.

The `cb-home-seed` pattern:
1. Each host file is mounted read-only under `/etc/cb-home-seed/.aws/`
2. At container startup, they are copied to `/home/coder/.aws/` (without overwriting a file already there)
3. The booth has a writable copy; your host files stay protected

The AWS CLI version comes from `.booth/Boothfile`, which installs `latest` by default — each image build picks up whatever is current. Pin it for a reproducible version:

```bash
# from this folder; rewrites .booth/Boothfile with arg AWS_CLI_VERSION=2.27.0
booth config --no-tui --overwrite --add-select 'aws-cli:2.27.0'
```

## Security Notes

| Aspect              | How It's Protected                                                                                                                          |
|---------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| Host credentials    | Mounted read-only (`:ro`) — the booth cannot modify them                                                                                     |
| Container changes   | Don't affect your host — the booth works on a copy                                                                                           |
| Version control     | Credentials are NOT stored in the repo                                                                                                       |
| Reading the copy    | **Not protected.** Anything running in the booth — you, a script, an agent — can read the keys and use your full permissions. Seed a scoped profile when that matters. |
| Teardown            | A default run removes the container and its copy when the booth stops. With `--keep-alive` or `--persist-home` the copy survives in the stopped container or the home volume until you `booth remove` it. |
| Seeding happens once | With `--persist-home`, the home is seeded only on first start; later changes to your host credentials do not reach the booth until the volume is removed. |
