# Claude Code in a Booth

Claude Code works best when it can act: run your tests, install a package, edit files, try a
command and read the error. On your host, every one of those actions reaches your real home folder,
SSH keys and cloud credentials, so you end up approving each step by hand.

A booth gives Claude a place to act freely. It is a container with Claude Code already installed,
your project mounted at `/home/coder/code`, and nothing else from your host unless you put it
there. You keep your login, your settings and your session history, and Claude gets a sandbox in
which "yes, go ahead" is a reasonable default.

This article shows the two ways to use it:

- **As a chat partner inside the booth** (the main use). You open a session and work with Claude
  on the project, the way you would at your desk.
- **As a one-shot command** for scripts, Justfile recipes and quick questions.

Two ready-made examples go with it:
[claude-example](../../../examples/workspaces/claude-example/) (reuses the host's `claude`
login) and [claude-token-example](../../../examples/workspaces/claude-token-example/) (logs in with
a token).

## 1. Add Claude Code to your project

From your project folder:

```bash
booth config --select claude-code+auto-accept
```

Or run `booth config` and pick **Claude Code** under AI Tools in the TUI. This writes `.booth/`
with these pieces:

| Piece | What it does |
| --- | --- |
| `claude-code` | Installs the `claude` CLI in the image. No Node setup on your side. |
| `credential` *(on by default)* | Mounts your host's Claude login into the booth, read-only. |
| `settings-cache` *(on by default)* | Keeps `~/.claude` (settings, history, sessions) across booth restarts. |
| `auto-accept` | Lets Claude use its tools without asking, but denies destructive git commands and `rm -rf /`. |

**Log in once on the host** (`claude`, then `/login`) and every booth from this folder is logged
in too. On macOS the login lives in the Keychain and cannot be mounted. Use a token instead:

```bash
booth config --select claude-code+auto-accept+token-credential~credential
claude setup-token                        # on the host, once; copy the sk-ant-oat01-... token
export CLAUDE_CODE_OAUTH_TOKEN=sk-ant-oat01-...
```

[claude-token-example](../../../examples/workspaces/claude-token-example/) covers the token
route in full, including how to keep the token out of your shell history.

## 2. Chat with Claude inside the booth

This is the everyday use. Start the booth and open a session:

```bash
booth            # a shell in the booth, in /home/coder/code
claude           # a Claude Code session on your project
```

From then on, work with it as you would on your host:

```text
> The login test fails since yesterday. Find out why and fix it.
> Add a --dry-run flag to the deploy script, with a test.
> Explain how the cache layer decides when to evict.
```

What changes inside the booth:

- **Fewer prompts.** With `auto-accept`, Claude installs packages, runs the test suite and edits
  files without stopping at every step. The deny list still blocks force-pushes, `git reset
  --hard`, `git clean -f` and similar commands, and a startup hook protects mounted volumes from
  `rm -rf`. To see the rules, read `.booth/home-seed/.claude/settings.json`.
- **A smaller blast radius.** Anything Claude installs or breaks stays in the container. Your
  project folder is shared, so edits show up in your editor on the host as Claude makes them.
  Review them with `git diff` as usual.
- **Sessions survive.** `settings-cache` keeps `~/.claude`, so after a restart `claude --continue`
  picks up the last conversation, and `claude --resume` lists older ones.
- **Online lookups work.** `WebSearch` and `WebFetch` are allowed, so Claude can check
  documentation or a changelog while it works.

You do not have to open a shell first. From the host:

```bash
booth exec --run --it -- claude
```

This starts the booth if it is not already running, and opens Claude in it. `--it` gives the
session a terminal. Both examples wrap this as `just claude`.

Keep a second terminal on the host for your editor, `git` and anything that needs your own
credentials. Claude works in the booth, and you review and push from the host.

## 3. One-shot tasks

Sometimes you want an answer or a small job done, not a conversation. `claude -p` prints the
result and exits. Inside the booth:

```bash
claude -p "Summarise what changed in the last five commits"
claude -p "List the TODO comments in src/ as a markdown table" > todos.md
```

From the host, put it in a script and call the script through the booth. That way quoting stays
simple, and you can restrict the tools for unattended runs:

```bash
# scripts/ask-claude.sh
claude -p "$1" --allowedTools "Read" "Glob" "Grep" "Bash(ls:*)" </dev/null
```

```bash
./booth exec --run -- scripts/ask-claude.sh "Which config keys does the server read?"
```

The examples ship this as `just ask "your prompt"` (add `--quiet` first to hide the booth's
start/stop messages), and
[claude-example](../../../examples/workspaces/claude-example/README.md#vet-a-repo-before-you-run-it)
builds a bigger job on the same idea. `just vet <git-url>` clones a stranger's repository into the
booth and has Claude write a safety report on it, before anything from it runs on your machine.

> **Quoting.** `./booth -- claude -p "'your prompt'"` also works for a quick test, but the words
> after `--` are run through `bash -lc`, so the prompt needs two layers of quotes. A script or a
> Justfile recipe avoids that.

## Try it

```bash
cd examples/workspaces/claude-example      # or claude-token-example
./booth                                    # then: claude
```

Ask it about the example itself ("What does `just vet` do, step by step?"), let it change
something, and watch the change appear in your editor on the host.
