# AWS Cloud Development Example

Develop and deploy to AWS from an isolated, reproducible CodingBooth environment.
This example demonstrates AWS CLI integration — your credentials stay safe on your host while the booth gets everything it needs to interact with AWS services. Every team member gets the same AWS tooling, same SDK versions, and project-specific configuration without polluting their host setup.

## Table of Contents

- [Why Run AWS Development in CodingBooth?](#why-run-aws-development-in-codingbooth)
- [Quick Start](#quick-start)
- [Credentials Separation Pattern](#credentials-separation-pattern)
- [Interactive Runnable Documentation](#interactive-runnable-documentation)
- [Configuration](#configuration)
- [Security Notes](#security-notes)


## Why Run AWS Development in CodingBooth?

Running AWS development inside CodingBooth provides a **secure, consistent environment** for cloud work:

| Benefit                  | Description                                                                                                              |
|--------------------------|--------------------------------------------------------------------------------------------------------------------------|
| **Credentials Safety**   | Your AWS credentials stay on your host (read-only mount). The container gets a copy, never the original.                |
| **Reproducibility**      | Every developer gets the same AWS CLI version, same SDKs, same tools. No "works on my machine" issues.                  |
| **Project Isolation**    | Each project can have its own AWS profile/region configuration without affecting other projects or your host.           |
| **Team Consistency**     | New team members run `./coding-booth` and have a working AWS environment immediately. No setup docs to follow.          |
| **Safe Experimentation** | Test IAM policies, try new services, experiment freely. Your host AWS config stays untouched.                           |
| **Clean Teardown**       | When you're done, the workspace disappears. No leftover AWS CLI configs or cached credentials on your host.             |

## Quick Start

**Prerequisites:** AWS credentials configured on your host (`~/.aws/credentials` and `~/.aws/config`)

```bash
# Start the workspace
cd examples/workspaces/aws-example
../../coding-booth

# Inside the workspace, AWS CLI is ready:
aws sts get-caller-identity

# Or open the Jupyter notebook for an interactive guide
```

**Interactive Guide (Jupyter Notebook):**
- [`AWS-NoteBook.ipynb`](AWS-NoteBook.ipynb) - Step-by-step AWS operations with runnable cells

## Credentials Separation Pattern

CodingBooth supports separating **secrets** (kept safe on your host) from **configuration** (committed with the project):

| What                    | Where                      | Committed?             |
|-------------------------|----------------------------|------------------------|
| Credentials (secrets)   | Host `~/.aws/credentials`  | No - user keeps safe   |
| Config (profile/region) | `.booth/home/.aws/config`  | Yes - shared with team |

**How it works:**
```toml
# .booth/config.toml - mount credentials from host (read-only)
run-args = [
    "-v", "~/.aws:/etc/cb-home-seed/.aws:ro",
]
```

```ini
# .booth/home/.aws/config - project-specific profile (committed to repo)
[default]
region = ap-southeast-1

[profile my-project-prod]
region = us-east-1
role_arn = arn:aws:iam::123456789:role/ProjectRole
source_profile = default
```

This way you never forget which AWS profile/region to use for each project — it's defined in the repo. Team members just need matching profile names in their host credentials.

## Interactive Runnable Documentation

This example includes a Jupyter Notebook for **documentation that actually runs**:

- [`AWS-NoteBook.ipynb`](AWS-NoteBook.ipynb) - Interactive AWS operations guide

Benefits:
- Step-by-step guides with explanations and executable code cells
- New team members follow along and run each step
- No copy-paste errors - just click "Run"
- Documentation stays in sync because it's tested by running it

## Configuration

`.booth/config.toml`:
```toml
variant = "notebook"

run-args = [
    # AWS credentials (home-seeding pattern)
    "-v", "~/.aws:/etc/cb-home-seed/.aws:ro",
]
```

The `cb-home-seed` pattern:
1. Host `~/.aws/` is mounted read-only to `/etc/cb-home-seed/.aws/`
2. At container startup, contents are copied to `/home/coder/.aws/`
3. The container has a writable copy; your host files stay protected

## Security Notes

| Aspect              | How It's Protected                                          |
|---------------------|-------------------------------------------------------------|
| Host credentials    | Mounted read-only (`:ro`) — container cannot modify them    |
| Container changes   | Don't affect your host — the container gets a copy          |
| Version control     | Credentials are NOT stored in the repo                      |
| Teardown            | Stop the booth and all credential copies are gone           |
