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
| Trust | `/home/coder/code` is pre-trusted (no Restricted Mode prompt) |
| Sample | `src/hello.py` |

## Notes

- **No GPU.** Zed renders through software Vulkan. It works, but scrolling and resizing are slower than on real hardware.
- **Trusted project.** `/home/coder/code` and everything under it are always trusted, so Zed does not open them in Restricted Mode, including on the first launch in a new booth. Zed has no setting for one trusted folder, so the `zed` launcher records it in Zed's own database before Zed starts. Folders outside `~/code` are asked about as usual.
- **Your own settings.** To bring your host settings, add this to `.booth/config.toml`:
  `run-args = ["-v", "~/.config/zed:/etc/cb-home-seed/.config/zed:ro"]`
- **Another release.** Change `ZED_VERSION` in `.booth/Boothfile` with `booth config --select zed:<version>`.
