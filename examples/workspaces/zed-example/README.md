# Zed Example

A small Python file opened in [Zed](https://zed.dev/) on the booth's XFCE desktop. The booth installs Zed from its official release, adds it to the desktop and dock, and wraps the launcher so a bare `zed` opens this project.

**Stack:** XFCE desktop, Zed 1.25.3

## Quick start

```bash
cd examples/workspaces/zed-example
../../../codingbooth          # then open http://localhost:50811

# inside the booth (or click the Zed icon in the dock)
zed                           # opens /home/coder/code
zed src/hello.py
just --list
```

## What's included

| Component | Details |
|-----------|---------|
| Editor | Zed 1.25.3 at `/opt/zed-current`, launcher `/usr/local/bin/zed` |
| Rendering | Mesa's software Vulkan driver (lavapipe), because a booth has no GPU |
| Settings | `~/.config/zed/settings.json` is created with `"auto_update": false` the first time |
| Sample | `src/hello.py` |

## Notes

- **No GPU.** Zed renders through software Vulkan. It works, but scrolling and resizing are slower than on real hardware.
- **Restricted Mode.** Zed asks whether to trust a project the first time you open it. That prompt comes from Zed, not the booth.
- **Your own settings.** To bring your host settings, add this to `.booth/config.toml`:
  `run-args = ["-v", "~/.config/zed:/etc/cb-home-seed/.config/zed:ro"]`
- **Another release.** Change `ZED_VERSION` in `.booth/Boothfile` with `booth config --select zed:<version>`.
