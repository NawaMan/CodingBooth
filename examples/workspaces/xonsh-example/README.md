# Xonsh Example

A two-line [Xonsh](https://xon.sh/) script. Xonsh is a Python shell: `print(20 + 22)` and `echo @(6 * 7)` both mean 42. The install is a venv at `/opt/xonsh` (`xonsh[full]`), with `/usr/local/bin/xonsh` on `PATH` and in `/etc/shells`. This booth also selects `xonsh+default`, so the `coder` login shell is Xonsh. Catalog Python 3.13.15 is installed first (Xonsh needs 3.11 or newer).

**Stack:** Xonsh 0.24.2, Python 3.13.15, `xonsh+default`

## Quick start

```bash
cd examples/workspaces/xonsh-example
../../../codingbooth

# inside the booth
xonsh hello.xsh
just hello
getent passwd coder    # shell field is /usr/local/bin/xonsh
```

A command you pass on the `./booth --` line still runs under bash. The login shell changes when you open the booth with no command.

## What's included

| Component | Details |
|-----------|---------|
| Shell | Xonsh 0.24.2 in `/opt/xonsh` |
| Login shell | `USER_SHELL=/usr/local/bin/xonsh` |
| Sample | `hello.xsh` |

Pin another release with `XONSH_VERSION` in `.booth/Boothfile`, or `@xonsh` for the recipe in `.booth/recipes/xonsh.recipe`.
