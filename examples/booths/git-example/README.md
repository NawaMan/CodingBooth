# Git Example

A booth that can commit as you and push to GitHub, without copying any key or token into the
project or the image. It brings in two things from the host:

| Piece | What it does |
| --- | --- |
| `git-credential` | Mounts your host `~/.gitconfig` read-only and copies it into the booth's home at startup, so commits carry your `user.name` / `user.email`, and your aliases work. |
| `gh` + `token` | Installs the GitHub CLI and passes `GH_TOKEN` / `GITHUB_TOKEN` (and `GH_ENTERPRISE_TOKEN` / `GH_HOST`) from the host. gh is git's credential helper for github.com, so `git push` over HTTPS uses the token too. |

The booth was generated with:

```bash
booth config --no-tui --overwrite --select gh+token/git-credential
```

## Quick Start

**Prerequisites:** a host `~/.gitconfig`, and a GitHub login on the host (`gh auth login`) or a
personal access token.

```bash
cd examples/workspaces/git-example

# Hand the host's gh login to the booth (gh keeps it in the keyring, not in a file):
GH_TOKEN=$(gh auth token) ./booth

# Inside the booth:
git config user.email       # your host identity
gh auth status              # logged in via GH_TOKEN
gh repo clone <owner>/<repo>
```

A fine-grained personal access token works the same way: `export GH_TOKEN=github_pat_...` before
`./booth`. To avoid typing it each time, put `GH_TOKEN=...` in `.booth/.env` (which is gitignored).
That file reaches the booth even without the `token` extension.

### Run it

```bash
just --list
just info                   # booth--info: what this booth is
just shell                  # a shell in the booth, starting it if needed
```

## How it works

- **Identity:** `~/.gitconfig` arrives at `/etc/cb-home-seed/.gitconfig` (read-only) and is copied
  into `/home/coder` at startup. Changing git config in the booth changes the copy, never your
  host file.
- **Pushing:** the gh setup registers gh as the credential helper for github.com (and `GH_HOST`).
  When the booth has no `ssh` client, a `git@github.com:` remote is rewritten to HTTPS in the
  booth's `~/.gitconfig` (not the repo's), so a repository cloned over SSH can still push with the
  token.
- **No token, no harm:** a variable not set on the host is left out of the booth entirely, so
  starting it without `GH_TOKEN` just gives you an unauthenticated gh.

## Caveats

- **Host-only credential helpers do not run.** If your `~/.gitconfig` names a helper by a host
  path (`osxkeychain`, a Git Credential Manager binary), it is copied in but fails in the booth.
  gh covers github.com; other hosts need their own token or helper.
- **The token is visible to the booth.** It is in the container's environment, so anything running
  in the booth can read it, and `docker inspect` on the host shows it. Give an agent a
  narrowly-scoped fine-grained token, not your full login.
- `git-credential` is still marked untested in its template. Report what works and what does not.

## Customize

```bash
# Pin gh:
./booth config --no-tui --overwrite --add-select gh:2.103.3

# Add GitHub Copilot CLI (mounts ~/.config/github-copilot read-only):
./booth config --no-tui --overwrite --add-select gh+copilot
```
