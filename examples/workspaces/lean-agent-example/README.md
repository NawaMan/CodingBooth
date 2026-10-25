# Lean Agent Example (experimental)

An AI agent proving theorems in [Lean 4](https://lean-lang.org), in a sandbox. This booth has
[Claude Code](https://docs.claude.com/en/docs/claude-code) and
[lean-lsp-mcp](https://github.com/oOo0oOo/lean-lsp-mcp), an MCP server that gives the agent what
a person gets from the infoview: the goal at any line, the errors in a file, and lemma search.
So the agent writes a proof one step at a time and checks each step, instead of guessing and
rebuilding.

`Exercises/` has five theorems left as `sorry`: from a warm-up (`a + b = b + a`) through Gauss's
formula and Nicomachus's theorem to two facts about a list-reversing function. Ask Claude to
prove them, or prove them yourself in **Neovim with lean.nvim**, which is also in this booth.

Lean checks every proof, so you don't have to trust the agent. A proof Lean accepts is correct,
whoever wrote it. The one thing to check yourself is that the theorem **statements** did not
change, and `CLAUDE.md` tells the agent not to change them.

> **Experimental.** The `lean` template and its `mcp` and `nvim` extensions are new and not
> battle-tested yet.

**Stack:** Lean 4.35.0 (core library, no Mathlib), Claude Code, lean-lsp-mcp 0.31.0,
Neovim + lean.nvim, base variant (terminal)

## Quick start

Log in to Claude Code on the host first (`claude`, then `/login`). The booth reuses that login,
read-only, the same way as [claude-example](../claude-example/).

```bash
cd examples/workspaces/lean-agent-example
just status        # 5 exercise(s) still open
just prove         # Claude proves them on its own, then lake build checks the result
just status        # 0 exercise(s) still open
```

Or work with Claude interactively:

```bash
booth              # a shell in the booth
claude             # then, for example: "Prove two_mul_sumTo in Exercises/Basic.lean"
```

The first time, Claude Code asks whether to use the `lean-lsp` server from `.mcp.json`. The
project's `.claude/settings.json` already enables it, so that question may not appear. Type `/mcp`
in Claude Code to see the server and its tools.

To start over, restore the exercises with git on the host:
`git checkout -- examples/workspaces/lean-agent-example/Exercises`.

## Prove them yourself, in Neovim

```bash
just nvim                          # opens Exercises/Basic.lean
just nvim Exercises/Lists.lean
```

| Key / command | Does |
|---------------|------|
| `\i` | toggle the infoview: the goal at the cursor, updated as you move |
| `\forall` + space | types `∀`; also `\to` → `→`, `\N` → `ℕ`, `\le` → `≤`, `\l` → `←` |
| `:LeanGoal` | show the goal at the cursor in a window |
| `:LeanRestartFile` | re-check the file from the start |
| `]d` / `[d` | next / previous error or warning |

Your own Neovim config (`~/.config/nvim`) is copied in too. lean.nvim is set up after it. To set
it up yourself, put `vim.g.booth_lean = false` in your `init.lua` and call
`require("lean").setup { ... }` there.

## How the pieces connect

| Piece | Where | What it does |
|-------|-------|--------------|
| `lean+mcp` | the booth | installs `lean-lsp-mcp` and `ripgrep` |
| `.mcp.json` | this folder | tells Claude Code to start `lean-lsp-mcp` as the `lean-lsp` server |
| `.claude/settings.json` | this folder | enables that server; allows its tools, `lake build`, and edits under `Exercises/` without asking |
| `CLAUDE.md` | this folder | how to work: read goals with `lean_goal`, check with `lean_diagnostic_messages`, never change a statement |
| `lean+nvim` | the booth | lean.nvim, set up system-wide |
| `claude-code` | the booth | Claude Code, logged in with your host login |

To add the MCP server to your own Lean project, select `lean+mcp` (with `claude-code`) and copy
`.mcp.json` and `.claude/settings.json` from here. For a Mathlib project, see
[lean-mathlib-example](../lean-mathlib-example/).

## Tests

The tests do not call Claude, so they cost nothing and need no login. They check:

1. Every tool is installed.
2. The exercises build, with exactly 5 left as `sorry`.
3. **The MCP server answers as it does for Claude Code:** a small MCP client
   (`.cb-tests/mcp_check.py`) starts `lean-lsp-mcp`, asks `lean_goal` for the goal at the
   `sorry` in `two_mul_sumTo`, and gets Gauss's formula back. `lean_diagnostic_messages`
   reports the `sorry`s.
4. **Neovim:** a headless Neovim opens `Exercises/Basic.lean`, lean.nvim starts the Lean
   language server, and its diagnostics reach Neovim.
