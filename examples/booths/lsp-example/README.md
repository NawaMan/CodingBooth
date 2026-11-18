# LSP Example

A small project in five file types: Markdown, TOML, YAML, Bash, and TypeScript. Its booth
installs a language server for each, with the `lsp` template. Language servers are
editor-independent, so the same installed servers drive all four terminal editors here:
**TTT** (the booth's default editor), **Fresh**, **Helix**, and **Neovim**. In VS Code, the same
`lsp+…` picks add the matching extensions instead.

**Stack:** marksman, taplo, yaml-language-server, bash-language-server,
typescript-language-server (on Node.js), Fresh, Helix, Neovim + `neovim+lsp`

## Quick start

```bash
# 1. Launch the booth
cd examples/workspaces/lsp-example
booth

# 2. Inside the booth
just --list
just check                    # every server answers LSP initialize
ttt docs/guide.md             # TTT: the status bar shows Markdown ◉
fresh docs/guide.md           # Fresh: the status bar shows LSP (on)
hx settings.toml              # Helix: space k for hover
nvim src/greet.ts             # Neovim: K for hover, :checkhealth vim.lsp
```

## What it shows

| File               | Server                       | Try |
|--------------------|------------------------------|-----|
| `docs/guide.md`    | marksman                     | jump to a linked heading, see the broken link flagged |
| `settings.toml`    | taplo                        | break a line (`retries = = 3`) and watch the error |
| `deploy.yaml`      | yaml-language-server         | the `$schema` comment validates it as a GitHub workflow |
| `scripts/greet.sh` | bash-language-server         | remove the quotes around `${name}` for a shellcheck finding |
| `src/greet.ts`     | typescript-language-server   | call `greet(42)` for a type error |

## Installing a missing server from Fresh

Open a file whose server is not installed, for example a `.sql` file, and click the
`LSP (off)` indicator in Fresh's status bar. The popup offers **Install <server> (booth)**,
which runs the booth's `lsp--<server>--setup.sh` with `sudo` and starts the server. The palette
command **Booth: Install Language Server** lists every missing one. An install made this way
lasts until the booth is rebuilt; add the `lsp+<language>` selection to keep it:

```bash
booth config --no-tui --select 'lsp+markdown+toml+yaml+bash+typescript+sql' \
             --select 'neovim+lsp~config' --select helix --select fresh
```

or type server names directly: `lsp:sqls,pylsp`.

## How it is configured

`.booth/` is `booth config` output:

```bash
booth config --no-tui --select 'lsp+markdown+toml+yaml+bash+typescript' \
             --select 'neovim+lsp~config' --select helix --select fresh
```

`neovim+lsp~config` keeps Neovim's LSP wiring and leaves out the mount of your host
`~/.config/nvim`. Wiring and mount work together; the mount is only left out here so the
example behaves the same for everyone. The Neovim template also sets `$EDITOR` to `nvim`.
`ttt` is in the base image and starts the same servers on its own; `fresh` comes from the
`fresh` template, which also links its booth-lsp plugin.
