# Home Directory Customization

CodingBooth provides mechanisms for populating the user's home directory with custom files at container startup. There are two patterns: **seed** (no-clobber) and **override**.

Back to [README](../README.md)

---

## Table of Contents

- [Project Home Seed](#project-home-seed-boothhome-seed)
- [Project Home Override](#project-home-override-boothhome)
- [Host Home Seed](#host-home-seed-etccb-home-seed)
- [Host Home Override](#host-home-override-etccb-home)
- [Precedence Order](#precedence-order)
- [Common Credential Seeding Examples](#common-credential-seeding-examples)
- [Why You Shouldn't Seed Everything](#why-you-shouldnt-seed-everything)

---

## Project Home Seed (`.booth/home-seed/`)

Create a `.booth/home-seed/` folder in your project to provide team-wide defaults that **will not overwrite** existing files.

**How it works:**
- Place files in `.booth/home-seed/` with the same structure as `$HOME`.
- At container startup, files are copied to `/home/coder/` **without overwriting** existing files.
- Good for providing default templates that users can customize.

## Project Home Override (`.booth/home/`)

Create a `.booth/home/` folder in your project to provide team-wide configs that **will overwrite** existing files.

**How it works:**
- Place files in `.booth/home/` with the same structure as `$HOME`.
- At container startup, files are copied to `/home/coder/` **overwriting** existing files.
- Good for enforcing consistent team configurations.

**Example structure:**
```
my-project/
├── .booth/config.toml
├── .booth/Dockerfile
├── .booth/home-seed/        # Defaults (won't overwrite)
│   └── .config/
│       └── myapp/
│           └── config.yaml  # Default config template
└── .booth/home/             # Overrides (will overwrite)
    ├── .bashrc              # Team bashrc (enforced)
    └── .gitconfig           # Team git settings (enforced)
```

> **Warning:**
> Do NOT put secrets, credentials, or personal tokens in `.booth/home/` or `.booth/home-seed/` — these folders are meant to be committed to version control and shared with your team.

## Host Home Seed (`/etc/cb-home-seed/`)

Mount host files read-only to `/etc/cb-home-seed/` for **personal credentials** that should not be version-controlled.

**How it works:**
1. Mount host files read-only to `/etc/cb-home-seed/` (preserving the relative path structure)
2. At container startup, files are copied to `/home/coder/` **without overwriting** existing files
3. The user gets a writable copy; the host's original files stay protected

## Host Home Override (`/etc/cb-home/`)

Mount host files read-only to `/etc/cb-home/` for **personal configs** that should override other sources.

**How it works:**
1. Mount host files read-only to `/etc/cb-home/` (preserving the relative path structure)
2. At container startup, files are copied to `/home/coder/` **overwriting** existing files

**Example (`.booth/config.toml`):**
```toml
run-args = [
    "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro",
    "-v", "~/.config/github-copilot:/etc/cb-home-seed/.config/github-copilot:ro"
]
```

**Use cases:**
- **Credentials** — gcloud, GitHub Copilot, SSH keys (apps may refresh tokens)
- **Personal IDE settings** — VS Code, IntelliJ configurations
- **Personal dotfiles** — `.bashrc`, `.gitconfig` customizations

## Precedence Order

Files are copied in this order:

1. **`.booth/home-seed/`** (project folder) — Team defaults, no-clobber
2. **`.booth/home/`** (project folder) — Team overrides, will overwrite
3. **`/etc/cb-home-seed/`** (host mounts) — Personal defaults, no-clobber
4. **`/etc/cb-home/`** (host mounts) — Personal overrides, will overwrite

The **seed** sources use `cp -rn` (no-clobber) — they only copy if the file doesn't exist.
The **override** sources use `cp -r` — they always copy, overwriting existing files.

> **Tip:**
> Use **seed** for fallback defaults — "if no setup script provided this file, use this one."
> Use **override** for enforced configs — "regardless of what's already there, always use this file."

## Fine-Grained Copy with `.mount-this`

By default, the home copy stages recursively copy individual files. You can control granularity using the `.mount-this` marker — the same mechanism used by [`.booth/cache/`](BOOTH_LOCALCACHE.md):

- **Directory with `.mount-this`** — the entire directory is copied as a unit (like `cp -r` of the whole directory)
- **Directory without `.mount-this`** — only individual files in that directory are copied, then subdirectories are recursed into

This is useful when a source directory should only contribute specific files rather than replacing an entire target directory. For example, to seed only `.credentials.json` from `~/.claude/` without overwriting other files in `~/.claude/`:

```toml
# .booth/config.toml — mount only the credential file, not the whole directory
run-args = [
    "-v", "~/.claude/.credentials.json:/etc/cb-home/.claude/.credentials.json:ro",
]
```

Since `/etc/cb-home/.claude/` has no `.mount-this` marker, only `.credentials.json` is copied into `~/.claude/` — leaving any other files (settings, projects, history) untouched.

Compare with mounting a directory that has `.mount-this`:
```
/etc/cb-home-seed/.myapp/
    .mount-this          # ← marker present: copy entire directory
    config.yaml
    data/
        cache.db
```

This copies everything in `.myapp/` (including `data/cache.db`) to `~/.myapp/` as a unit.

---

## Common Credential Seeding Examples

Here are common credentials you might want to seed from your host:

```toml
# .booth/config.toml
run-args = [
    # Git credentials and config
    "-v", "~/.gitconfig:/etc/cb-home-seed/.gitconfig:ro",
    "-v", "~/.git-credentials:/etc/cb-home-seed/.git-credentials:ro",

    # SSH keys (for git over SSH)
    "-v", "~/.ssh:/etc/cb-home-seed/.ssh:ro",

    # AWS CLI credentials
    "-v", "~/.aws:/etc/cb-home-seed/.aws:ro",

    # Google Cloud credentials
    "-v", "~/.config/gcloud:/etc/cb-home-seed/.config/gcloud:ro",

    # Azure CLI credentials
    "-v", "~/.azure:/etc/cb-home-seed/.azure:ro",

    # GitHub CLI
    "-v", "~/.config/gh:/etc/cb-home-seed/.config/gh:ro",

    # GitHub Copilot
    "-v", "~/.config/github-copilot:/etc/cb-home-seed/.config/github-copilot:ro",

    # Claude Code (config as seed, credentials as override for freshness)
    "-v", "~/.claude.json:/etc/cb-home-seed/.claude.json:ro",
    "-v", "~/.claude/.credentials.json:/etc/cb-home/.claude/.credentials.json:ro",

    # OpenAI Codex
    "-v", "~/.codex:/etc/cb-home-seed/.codex:ro",

    # Firebase CLI
    "-v", "~/.config/configstore/firebase-tools.json:/etc/cb-home-seed/.config/configstore/firebase-tools.json:ro",

    # Kubernetes (kubectl, helm)
    "-v", "~/.kube:/etc/cb-home-seed/.kube:ro",

    # Terraform
    "-v", "~/.terraformrc:/etc/cb-home-seed/.terraformrc:ro",

    # Neovim config
    "-v", "~/.config/nvim:/etc/cb-home-seed/.config/nvim:ro",
    "-v", "~/.local/share/nvim:/etc/cb-home-seed/.local/share/nvim:ro"
]
```

> **Tip:** Only include the credentials you actually need. Each mount adds startup overhead.

## Why You Shouldn't Seed Everything

It's tempting to mount your entire `~/.config` or even `~` into the container. **Don't.**

**It defeats the purpose of containers.** The whole point of CodingBooth is a clean, reproducible environment. Bringing too much host state recreates the "works on my machine" problem you're trying to escape.

**Version and architecture conflicts.** Your host's Neovim plugins might be compiled for a different glibc. Your IDE settings might reference paths that don't exist in the container. Your shell config might source files that aren't there.

**Security exposure.** Your home directory contains more secrets than you remember — browser cookies, chat history, cached tokens in random dotfiles, SSH keys you forgot about. Every bind mount increases your attack surface.

**State confusion.** `cb-home-seed` *copies* files at startup (it doesn't sync). You might edit config in the container thinking it persists to host, or edit on host thinking the container will see it. Neither happens.

**Breaks team reproducibility.** If everyone seeds different things, environments diverge. When a new team member joins, they can't reproduce the issues you're seeing.

**Debugging becomes harder.** When something breaks, is it the container image, or something you seeded from host? The more you seed, the harder it is to isolate problems.

**The philosophy:** Seed the *minimum* credentials needed for your specific workflow. Authentication tokens, SSH keys for git, cloud CLI credentials — yes. Your entire dotfile collection — no.

> **Reality check:** If you find yourself needing to seed most of your home directory, ask yourself: do you actually need a container? Maybe the friction is telling you something.

## Persisting the Entire Home Directory

If you want the home directory to survive across sessions (IDE settings, browser history, app configs), use `--persist-home` instead of seeding. This stores `/home/coder` in a Docker named volume that persists across container exits and restarts.

See [Persist Home Directory](BOOTH_PERSIST_HOME.md) for details.
