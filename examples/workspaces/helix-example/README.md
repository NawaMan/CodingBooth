# Helix Example

A one-file note opened with [Helix](https://helix-editor.com/). The booth installs the `hx` binary and its runtime tree (grammars, queries, themes). `HELIX_RUNTIME` points at that tree, so `hx --health` lists the shipped grammars. The Nord theme is the shared config at `.booth/shared/home/coder/.config/helix/config.toml`, bind-mounted to `~/.config/helix/`.

**Stack:** Helix 25.07.1, `helix+config-shared`

## Quick start

```bash
cd examples/workspaces/helix-example
../../../codingbooth

# inside the booth
hx notes/welcome.md
hx --health
just health
```

## What's included

| Component | Details |
|-----------|---------|
| Editor | Helix 25.07.1 (`hx` plus `/opt/helix/runtime`) |
| Config | Nord theme, shared through git |
| Sample | `notes/welcome.md` |

Pin another release with `HELIX_VERSION` in `.booth/Boothfile`, or `@helix` for the recipe in `.booth/recipes/helix.recipe`.
