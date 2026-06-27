**Docker Sandboxes (`sbx`) released a new version.**

| | |
|---|---|
| Pinned baseline | `${baseline}` |
| Latest release | [`${latest}`](${rel_url}) |
${milestone}

### Why this matters
The planned `--sandbox-mode sbx` isolation backend shells out to the `sbx` CLI.
Because sbx is pre-1.0 and has broken its CLI before, every release is a potential
break of that integration.

### What to check
- [ ] Read the [release notes](${rel_url}) for changes to `sbx run` / its flags.
- [ ] Note any new or removed breaking changes (e.g. the deprecated `sbx run <name>` form being removed).
- [ ] Decide whether sbx is now mature enough to promote `--sandbox-mode sbx` from experimental.
- [ ] When reviewed, bump `.github/sbx-watch-baseline.txt` to `${latest}` to silence this watch until the next release.

### Latest release notes (truncated)
```
${notes}
```

---
<sub>Opened automatically by `.github/workflows/sbx-watch.yaml`. See `docs/plans/Sandbox-Isolation-Modes.md`.</sub>
