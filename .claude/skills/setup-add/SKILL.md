---
name: setup-add
description: Deprecated alias — use setup-work instead. Adding a setup is now one mode of setup-work, which also covers modifying and fixing setups, templates, and extensions. Use when the user wants a new tool installable in a booth ("add a setup for X", "make X available in booths", "add X to the catalog").
---

# Add a setup → use `setup-work`

This skill has been folded into **`setup-work`**, which covers adding, modifying, *and* fixing
setups, templates, and extensions — and which additionally sets up a workspace where the change can
actually be run.

**Invoke `setup-work` now** and follow it in "add" mode (§1a). Everything that used to live here is
there, plus:

- the local-override try-it loop, so a script change can be exercised without rebuilding the base
  image,
- the workspace policy (offer `examples/workspaces/<name>-example` and ask; throwaway otherwise),
- the catalog guards to re-run after a template change,
- a functional test standard rather than a `--version` grep.

Nothing else in this file is current — do not work from it.
