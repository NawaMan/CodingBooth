# Deploying the codingbooth.io site

The website is part of **this** repository under [`site/`](../site/). It uses
symlinks up into the repo (`site/images -> ../docs/images`,
`site/install.sh -> ../install.sh`), so the DreamHost host holds a **full clone**
of `CodingBooth` and its web root serves the `site/` subdirectory.

"Deploying" therefore means making that checkout match `origin/main`. This used
to be a manual SSH session; the [`Deploy Site`](../.github/workflows/deploy-site.yaml)
workflow now does it automatically on every push to `main` that touches the site
(and on-demand via **Actions → Deploy Site → Run workflow**).

Because the repo is **public**, the pull on DreamHost needs no GitHub
credential — the only secret involved is an SSH key that lets GitHub Actions log
in to DreamHost.

### Why `reset --hard`, not `git pull`

The DreamHost checkout is a **read-only mirror** — it never carries local commits
worth keeping. And the public history is periodically **force-pushed** (the
retiming workflow), so a plain `git pull` fails:

```
 + d52ab566...353f834d main -> origin/main  (forced update)
fatal: Need to specify how to reconcile divergent branches.
```

The deploy therefore does `git fetch --prune origin && git reset --hard origin/main`,
which mirrors any history — forced or not — with no divergence to reconcile.

If the checkout is ever stuck in that divergent state, run the same two commands
by hand to recover it:

```bash
cd ~/CodingBooth
git fetch --prune origin
git reset --hard origin/main
```

---

## Short example-download links

`site/.htaccess` rewrites friendly URLs to the GitHub Releases assets, so no zip
is ever stored on the web host:

| Friendly URL | Redirects to |
|---|---|
| `https://codingbooth.io/examples/aws-example.zip` | newest stable release's `aws-example.zip` |
| `https://codingbooth.io/examples/0.63.0/aws-example.zip` | that exact version's asset |

The `latest` form always tracks the newest release, so it never needs updating.
DreamHost has `mod_rewrite` and per-directory `.htaccess` enabled by default; the
rules take effect as soon as the `.htaccess` is deployed (the first run of the
deploy workflow).

> **Verify the web root once.** The `.htaccess` must land in the directory Apache
> actually serves for `codingbooth.io`. The home dir contains both `CodingBooth/`
> (the git checkout) and `codingbooth.io/`, so confirm how they relate:
>
> ```bash
> ls -ld ~/codingbooth.io && readlink ~/codingbooth.io
> ```
>
> If `~/codingbooth.io` is a **symlink to `~/CodingBooth/site`**, everything works
> as-is. If instead the DreamHost panel's *Web Directory* for the domain is set
> directly to `/home/<user>/CodingBooth/site`, that also works. But if
> `~/codingbooth.io` is a **separate real directory**, the served files aren't the
> git checkout — point the panel's Web Directory at `…/CodingBooth/site` (or make
> `~/codingbooth.io` a symlink to it) so deploys and this `.htaccess` take effect.

Verify after deploy:

```bash
curl -sIL https://codingbooth.io/examples/aws-example.zip | grep -iE 'HTTP/|location'
# expect: 302 ... -> github.com/.../releases/latest/download/aws-example.zip, then 200
```

---

## One-time setup

You do this once. **You generate and hold the key; it is never shared with anyone
building this repo.**

### 1. Create a dedicated deploy key

```bash
ssh-keygen -t ed25519 -C "gha-deploy-codingbooth" -f dreamhost_deploy -N ""
# creates: dreamhost_deploy (private)  dreamhost_deploy.pub (public)
```

### 2. Authorize the public key on DreamHost

Append the **public** half to the DreamHost user's authorized keys:

```bash
ssh YOUR_USER@YOUR_HOST 'cat >> ~/.ssh/authorized_keys' < dreamhost_deploy.pub
# then confirm key-only login works:
ssh -i dreamhost_deploy YOUR_USER@YOUR_HOST 'echo ok && cd ~/CodingBooth && git status -sb'
```

The deploy uses `git reset --hard origin/main`, so the checkout does **not** need
to be a clean fast-forwardable clone — a hard reset overwrites any local/divergent
state. (That also means anything you edit directly on the server under
`~/CodingBooth` will be discarded on the next deploy; make changes in the repo,
not on the box.)

### 3. Add the GitHub Actions secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Value |
|---|---|
| `DREAMHOST_SSH_KEY` | full contents of the **private** `dreamhost_deploy` file |
| `DREAMHOST_HOST` | DreamHost server hostname, e.g. `pdx1-shared-a1-39.dreamhost.com` |
| `DREAMHOST_USER` | the SSH username, e.g. `dh_hpffnn` |
| `DREAMHOST_PATH` | absolute path to the repo checkout, e.g. `/home/dh_hpffnn/CodingBooth` (the dir containing `site/`) |
| `DREAMHOST_PORT` | *(optional)* SSH port; omit for the default `22` |

### 4. Trigger it

Push a site change to `main`, or run **Actions → Deploy Site → Run workflow**.
Until the secrets exist the job exits green with a "skipping" message, so it is
safe to merge the workflow before finishing setup.

---

## Security notes

- The private key lives only in GitHub's encrypted secret store and in a
  short-lived file on the runner that the job deletes when it finishes.
- Use a **dedicated** key for this (as above), not your personal SSH key, so it
  can be revoked by removing one line from `~/.ssh/authorized_keys`.
- The workflow trusts the DreamHost host key on first connection (TOFU). To pin
  it instead, add a `DREAMHOST_KNOWN_HOSTS` secret
  (`ssh-keyscan -H YOUR_HOST`) and write it to `~/.ssh/known_hosts` in place of
  the `ssh-keyscan` line.
- Consider locking the key down on the DreamHost side with a forced command in
  `authorized_keys` (e.g. `command="cd PATH && git pull --ff-only"`) so a leaked
  key can only pull, not open a shell.
